import Darwin
import Foundation

struct VPNStatus: Equatable {
    enum Mode: Equatable {
        case off
        /// Tout le trafic Internet passe par le tunnel (route par défaut).
        case full
        /// Un VPN est actif mais la route par défaut reste le Wi-Fi/Ethernet (tunnel partiel, réseau privé, Tailscale…).
        case partial
    }

    var mode: Mode
    var name: String?
    var interface: String?
    var isActive: Bool { mode != .off }
}

/// Détection locale d'un VPN : aucune requête réseau, rien ne sort du Mac.
enum VPNDetector {
    static let tunnelPrefixes = ["utun", "ipsec", "ppp", "tun", "tap"]

    /// Nom affiché quand l'app VPN tourne mais n'est pas déclarée dans les réglages réseau de macOS.
    static let knownProviders: [(match: String, name: String)] = [
        ("protonvpn", "ProtonVPN"), ("nordvpn", "NordVPN"), ("mullvad", "Mullvad"), ("expressvpn", "ExpressVPN"),
        ("surfshark", "Surfshark"), ("windscribe", "Windscribe"), ("privateinternetaccess", "Private Internet Access"),
        ("tailscale", "Tailscale"), ("wireguard", "WireGuard"), ("openvpn", "OpenVPN"), ("cloudflarewarp", "Cloudflare WARP"),
        ("warp-svc", "Cloudflare WARP"), ("tunnelblick", "Tunnelblick"), ("forticlient", "FortiClient"),
        ("globalprotect", "GlobalProtect"), ("anyconnect", "Cisco AnyConnect"),
    ]

    static func isTunnel(_ interface: String) -> Bool {
        tunnelPrefixes.contains { interface.hasPrefix($0) }
    }

    // MARK: Analyse (fonctions pures)

    static func analyze(
        defaultInterface: String?,
        connectedServices: [String],
        tunnelsWithAddress: [String],
        processNames: [String]
    ) -> VPNStatus {
        let name = connectedServices.first ?? guessName(processNames)
        if let iface = defaultInterface, isTunnel(iface) {
            return VPNStatus(mode: .full, name: name, interface: iface)
        }
        // Tunnel actif hors route par défaut : on ne le signale que si on sait de quel VPN il s'agit
        // (les utun « système » d'Apple ne doivent pas déclencher de faux positif).
        if !connectedServices.isEmpty || (!tunnelsWithAddress.isEmpty && name != nil) {
            return VPNStatus(mode: .partial, name: name, interface: tunnelsWithAddress.first)
        }
        return VPNStatus(mode: .off, name: nil, interface: nil)
    }

    static func guessName(_ processNames: [String]) -> String? {
        let lowered = processNames.map { $0.lowercased().replacingOccurrences(of: " ", with: "") }
        for provider in knownProviders where lowered.contains(where: { $0.contains(provider.match) }) {
            return provider.name
        }
        return nil
    }

    /// `route -n get default` → ligne « interface: utun4 ».
    static func parseDefaultInterface(_ output: String) -> String? {
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("interface:") {
                return trimmed.dropFirst("interface:".count).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    /// `scutil --nc list` → noms des services VPN connectés.
    /// Ex. : `* (Connected)  61FB… VPN (ch.protonvpn.mac) "ProtonVPN"  [VPN:ch.protonvpn.mac]`
    static func parseConnectedServices(_ output: String) -> [String] {
        output.split(separator: "\n").compactMap { line in
            guard line.contains("(Connected)") else { return nil }
            let parts = line.split(separator: "\"", omittingEmptySubsequences: false)
            return parts.count >= 3 ? String(parts[1]) : nil
        }
    }

    // MARK: Lecture du système

    static func detect(processNames: [String]) -> VPNStatus {
        analyze(
            defaultInterface: run("/sbin/route", ["-n", "get", "default"]).flatMap(parseDefaultInterface),
            connectedServices: run("/usr/sbin/scutil", ["--nc", "list"]).map(parseConnectedServices) ?? [],
            tunnelsWithAddress: tunnelsWithIPv4(),
            processNames: processNames
        )
    }

    /// Interfaces de tunnel actives qui portent une adresse IPv4.
    static func tunnelsWithIPv4() -> [String] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return [] }
        defer { freeifaddrs(head) }
        var names: [String] = []
        var cursor = head
        while let ptr = cursor {
            defer { cursor = ptr.pointee.ifa_next }
            let name = String(cString: ptr.pointee.ifa_name)
            guard isTunnel(name), let addr = ptr.pointee.ifa_addr,
                  Int32(addr.pointee.sa_family) == AF_INET,
                  ptr.pointee.ifa_flags & UInt32(IFF_UP) != 0 else { continue }
            if !names.contains(name) { names.append(name) }
        }
        return names
    }

    private static func run(_ path: String, _ arguments: [String]) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = arguments
        let out = Pipe()
        task.standardOutput = out
        task.standardError = Pipe()
        do { try task.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return task.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
    }
}
