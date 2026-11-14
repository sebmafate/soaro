import Foundation
import Darwin

/// Lit CPU, mémoire, disque et processus. À appeler depuis un seul thread (le CPU
/// garde l'échantillon précédent pour calculer un delta).
final class SystemSampler {
    func snapshot() -> SystemSnapshot {
        SystemSnapshot(
            date: Date(),
            cpu: sampleCPU(),
            memory: sampleMemory(),
            disk: sampleDisk(),
            thermalState: ProcessInfo.processInfo.thermalState,
            uptime: Self.uptime()
        )
    }

    // MARK: CPU

    private typealias Ticks = (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)
    private var previousCores: [Ticks]?

    /// Cœurs d'efficacité (Apple Silicon) : ils sont énumérés en premier.
    private lazy var efficiencyCores: Int = Int(Self.sysctl("hw.perflevel1.logicalcpu", Int32(0)) ?? 0)

    func sampleCPU() -> CPUStats {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount)
        guard result == KERN_SUCCESS, let info else { return .zero }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: info)),
                vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            )
        }

        let stride = Int(CPU_STATE_MAX)
        var cores: [Ticks] = []
        for cpu in 0..<Int(cpuCount) {
            let base = cpu * stride
            cores.append((
                UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_USER)])),
                UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)])),
                UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)])),
                UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)]))
            ))
        }

        defer { previousCores = cores }
        guard let prev = previousCores, prev.count == cores.count else { return .zero }

        var perCore: [Double] = []
        var sumUser = 0.0, sumSystem = 0.0, sumTotal = 0.0
        for (now, before) in zip(cores, prev) {
            guard now.user >= before.user, now.system >= before.system, now.idle >= before.idle, now.nice >= before.nice else {
                perCore.append(0); continue
            }
            let dUser = Double((now.user - before.user) + (now.nice - before.nice))
            let dSystem = Double(now.system - before.system)
            let dIdle = Double(now.idle - before.idle)
            let total = dUser + dSystem + dIdle
            perCore.append(total > 0 ? (dUser + dSystem) / total : 0)
            sumUser += dUser; sumSystem += dSystem; sumTotal += total
        }
        guard sumTotal > 0 else { return CPUStats(user: 0, system: 0, perCore: perCore, efficiencyCores: min(efficiencyCores, perCore.count)) }
        return CPUStats(
            user: sumUser / sumTotal, system: sumSystem / sumTotal,
            perCore: perCore, efficiencyCores: min(efficiencyCores, perCore.count)
        )
    }

    // MARK: Mémoire

    func sampleMemory() -> MemoryStats {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        let total = ProcessInfo.processInfo.physicalMemory
        guard result == KERN_SUCCESS else {
            return MemoryStats(total: total, app: 0, wired: 0, compressed: 0, cached: 0, swapUsed: 0, pressure: .normal)
        }

        let page = UInt64(getpagesize())
        let app = (UInt64(stats.internal_page_count) &- UInt64(stats.purgeable_count)) * page
        let wired = UInt64(stats.wire_count) * page
        let compressed = UInt64(stats.compressor_page_count) * page
        let cached = (UInt64(stats.external_page_count) + UInt64(stats.purgeable_count)) * page

        let swap: xsw_usage? = Self.sysctl("vm.swapusage", xsw_usage())
        let level: Int32 = Self.sysctl("kern.memorystatus_vm_pressure_level", Int32(1)) ?? 1

        return MemoryStats(
            total: total,
            app: app,
            wired: wired,
            compressed: compressed,
            cached: cached,
            swapUsed: swap?.xsu_used ?? 0,
            pressure: MemoryPressure(level: level)
        )
    }

    // MARK: Disque

    private var cachedDisk: (stats: DiskStats, date: Date)?

    /// La capacité « important usage » interroge CacheDelete (coûteux) et change lentement :
    /// on ne la relit qu'au plus toutes les 30 s.
    func sampleDisk() -> DiskStats {
        if let cachedDisk, Date().timeIntervalSince(cachedDisk.date) < 30 { return cachedDisk.stats }
        let stats = readDisk()
        cachedDisk = (stats, Date())
        return stats
    }

    private func readDisk() -> DiskStats {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? url.resourceValues(forKeys: keys) else {
            return DiskStats(total: 0, available: 0)
        }
        return DiskStats(
            total: UInt64(max(0, values.volumeTotalCapacity ?? 0)),
            available: UInt64(max(0, values.volumeAvailableCapacityForImportantUsage ?? 0))
        )
    }

    // MARK: Uptime

    static func uptime() -> TimeInterval {
        guard let boot: timeval = sysctl("kern.boottime", timeval()) else {
            return ProcessInfo.processInfo.systemUptime
        }
        return Date().timeIntervalSince1970 - TimeInterval(boot.tv_sec)
    }

    // MARK: Processus

    /// Liste les processus via `ps` et les regroupe par application.
    static func processGroups() -> [ProcessGroup] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-axo", "pid=,pcpu=,rss=,comm="]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do { try task.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return parsePS(String(decoding: data, as: UTF8.self))
    }

    static func parsePS(_ output: String) -> [ProcessGroup] {
        var groups: [String: ProcessGroup] = [:]

        for line in output.split(separator: "\n") {
            // pid cpu rss comm (comm peut contenir des espaces)
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4,
                  let pid = Int32(parts[0]),
                  let cpu = Double(parts[1].replacingOccurrences(of: ",", with: ".")),
                  let rssKB = UInt64(parts[2])
            else { continue }

            let command = String(parts[3]).trimmingCharacters(in: .whitespaces)
            let (key, name, appPath) = identity(forCommand: command)

            if var group = groups[key] {
                group.cpu += cpu
                group.memory += rssKB * 1024
                group.pids.append(pid)
                groups[key] = group
            } else {
                groups[key] = ProcessGroup(
                    id: key, name: name, cpu: cpu, memory: rssKB * 1024,
                    pids: [pid], appPath: appPath
                )
            }
        }
        return Array(groups.values)
    }

    /// Détermine le nom et le bundle `.app` racine d'un exécutable.
    static func identity(forCommand command: String) -> (key: String, name: String, appPath: String?) {
        if let range = command.range(of: ".app/") ?? (command.hasSuffix(".app") ? command.range(of: ".app", options: .backwards) : nil) {
            let appPath = String(command[..<range.upperBound]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let fullPath = "/" + appPath
            let name = ((fullPath as NSString).lastPathComponent as NSString).deletingPathExtension
            return (fullPath, name, fullPath)
        }
        let name = (command as NSString).lastPathComponent
        return (name, name, nil)
    }

    /// Noms des processus en cours (pour reconnaître une app VPN).
    func runningProcessNames() -> [String] {
        Self.processGroups().map(\.name)
    }

    // MARK: sysctl

    /// Lecture d'un sysctl dont la valeur est un type « plain old data » (entier, struct C).
    static func sysctl<T>(_ name: String, _ initial: T) -> T? {
        var value = initial
        var size = MemoryLayout<T>.size
        let status = withUnsafeMutableBytes(of: &value) { buffer in
            sysctlbyname(name, buffer.baseAddress, &size, nil, 0)
        }
        return status == 0 ? value : nil
    }
}
