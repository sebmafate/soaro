import CoreWLAN
import Darwin
import Foundation

/// Débits réseau globaux. Seules les interfaces physiques (`en*`) sont comptées :
/// les tunnels VPN (`utun*`) rejouent le même trafic et le doubleraient.
final class NetworkSampler {
    private struct Counter { var rx: UInt32; var tx: UInt32 }
    private var previous: [String: Counter] = [:]
    private var previousDate: Date?
    private var wifiCache: (date: Date, info: WiFiInfo?)?

    /// CoreWLAN change lentement : on ne l'interroge qu'au plus toutes les 10 s.
    private func cachedWiFi(_ now: Date) -> WiFiInfo? {
        if let wifiCache, now.timeIntervalSince(wifiCache.date) < 10 { return wifiCache.info }
        let info = Self.wifi()
        wifiCache = (now, info)
        return info
    }

    func sample() -> NetworkStats {
        var rxDelta: UInt64 = 0
        var txDelta: UInt64 = 0
        var current: [String: Counter] = [:]
        var localIP: String?

        var head: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&head) == 0 {
            var cursor = head
            while let ptr = cursor {
                defer { cursor = ptr.pointee.ifa_next }
                let name = String(cString: ptr.pointee.ifa_name)
                guard name.hasPrefix("en"), let addr = ptr.pointee.ifa_addr else { continue }

                switch Int32(addr.pointee.sa_family) {
                case AF_LINK:
                    if let raw = ptr.pointee.ifa_data {
                        let data = raw.assumingMemoryBound(to: if_data.self).pointee
                        current[name] = Counter(rx: data.ifi_ibytes, tx: data.ifi_obytes)
                    }
                case AF_INET where localIP == nil:
                    localIP = Self.ipv4String(addr)
                default: break
                }
            }
            freeifaddrs(head)
        }

        let now = Date()
        defer { previous = current; previousDate = now }
        for (name, counter) in current {
            guard let before = previous[name] else { continue }
            rxDelta += Self.delta32(counter.rx, before.rx)
            txDelta += Self.delta32(counter.tx, before.tx)
        }

        var down = 0.0, up = 0.0
        if let previousDate {
            let dt = now.timeIntervalSince(previousDate)
            if dt > 0 { down = Double(rxDelta) / dt; up = Double(txDelta) / dt }
        }
        return NetworkStats(downRate: down, upRate: up, localIP: localIP, wifi: cachedWiFi(now), latencyMs: nil)
    }

    /// Les compteurs de `getifaddrs` sont sur 32 bits et repartent de zéro vers 4 Go.
    static func delta32(_ now: UInt32, _ before: UInt32) -> UInt64 {
        now >= before ? UInt64(now - before) : UInt64(now) + (UInt64(UInt32.max) + 1 - UInt64(before))
    }

    private static func ipv4String(_ addr: UnsafeMutablePointer<sockaddr>) -> String? {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else {
            return nil
        }
        let ip = String(cString: host)
        return ip.hasPrefix("169.254.") ? nil : ip   // ignore le link-local
    }

    // MARK: Wi-Fi

    static func wifi() -> WiFiInfo? {
        guard let interface = CWWiFiClient.shared().interface(), interface.powerOn() else { return nil }
        let rssi = interface.rssiValue()
        guard rssi != 0 else { return nil }   // 0 = non connecté
        return WiFiInfo(
            rssi: rssi,
            noise: interface.noiseMeasurement(),
            txRate: interface.transmitRate(),
            ssid: interface.ssid(),            // nil sans autorisation de localisation
            channel: interface.wlanChannel()?.channelNumber
        )
    }

    // MARK: Latence (ping)

    /// Latence aller-retour vers `host` en ms, ou `nil`. Génère un paquet ICMP : à n'appeler que si l'utilisateur l'a demandé.
    static func ping(host: String) -> Double? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/sbin/ping")
        task.arguments = ["-c", "1", "-t", "2", host]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do { try task.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return parsePing(String(decoding: data, as: UTF8.self))
    }

    static func parsePing(_ output: String) -> Double? {
        guard let range = output.range(of: "time=") else { return nil }
        let tail = output[range.upperBound...].prefix { $0.isNumber || $0 == "." || $0 == "," }
        return Double(tail.replacingOccurrences(of: ",", with: "."))
    }

    // MARK: Trafic par application (nettop)

    /// Débits par processus sur la dernière seconde. `nettop` prend ~2 s : à lancer hors du thread principal.
    static func processTraffic() -> [NetworkTrafficRow] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        // -P : une ligne par processus · -d : deltas · -t external : exclut le trafic local (loopback)
        task.arguments = ["-P", "-L", "2", "-s", "1", "-d", "-x", "-t", "external", "-J", "bytes_in,bytes_out"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do { try task.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return parseNettop(String(decoding: data, as: UTF8.self))
    }

    /// `nettop -L 2` imprime deux blocs séparés par un en-tête CSV ; le second contient les deltas.
    static func parseNettop(_ output: String) -> [NetworkTrafficRow] {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: true)
        guard let lastHeader = lines.lastIndex(where: { $0.hasPrefix(",bytes_in") }) else { return [] }

        var rows: [NetworkTrafficRow] = []
        for line in lines[(lastHeader + 1)...] {
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
            guard fields.count >= 3, let down = Double(fields[1]), let up = Double(fields[2]), down + up > 0 else { continue }
            // « Nom du processus.PID » — le nom peut lui-même contenir des points.
            let label = String(fields[0])
            guard let dot = label.lastIndex(of: "."), let pid = Int32(label[label.index(after: dot)...]) else { continue }
            rows.append(NetworkTrafficRow(pid: pid, name: String(label[..<dot]), down: down, up: up))
        }
        return rows
    }
}

struct NetworkTrafficRow: Equatable {
    var pid: Int32
    var name: String
    var down: Double   // octets sur l'intervalle d'une seconde
    var up: Double
}

// MARK: - Énergie par application (top)

enum EnergySampler {
    /// « Impact énergétique » par PID (colonne POWER de `top`). Prend ~2 s.
    static func impactByPID() -> [Int32: Double] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/top")
        task.arguments = ["-l", "2", "-s", "1", "-n", "25", "-o", "power", "-stats", "pid,power"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do { try task.run() } catch { return [:] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return parseTop(String(decoding: data, as: UTF8.self))
    }

    /// Ne garde le dernier échantillon (le premier est cumulé depuis le lancement).
    static func parseTop(_ output: String) -> [Int32: Double] {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: true)
        guard let header = lines.lastIndex(where: { $0.hasPrefix("PID") }) else { return [:] }
        var result: [Int32: Double] = [:]
        for line in lines[(header + 1)...] {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2, let pid = Int32(parts[0]), let power = Double(parts[1].replacingOccurrences(of: ",", with: ".")) else { continue }
            result[pid] = power
        }
        return result
    }
}

// MARK: - E/S disque par processus

enum ProcessIOSampler {
    struct Counters { var read: UInt64; var written: UInt64 }

    /// Octets lus/écrits cumulés par PID (`proc_pid_rusage`, sans droits spéciaux pour nos propres processus).
    static func counters(for pids: [Int32]) -> [Int32: Counters] {
        var result: [Int32: Counters] = [:]
        for pid in pids {
            var info = rusage_info_current()
            let status = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, $0)
                }
            }
            if status == 0 { result[pid] = Counters(read: info.ri_diskio_bytesread, written: info.ri_diskio_byteswritten) }
        }
        return result
    }
}
