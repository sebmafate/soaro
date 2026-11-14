import AppKit
import Foundation
import SystemConfiguration

/// Fiche d'identité du Mac (section « Ce Mac »). Lue une fois : ces valeurs ne changent pas.
struct MachineInfo: Equatable {
    struct Display: Equatable, Identifiable {
        var name: String
        var pixels: String        // « 3440 × 1440 »
        var refreshRate: Int      // Hz
        var id: String { name + pixels }
    }

    var modelName: String?          // « MacBook Pro »
    var modelIdentifier: String?    // « MacBookPro18,1 »
    var chip: String?               // « Apple M1 Pro »
    var serialNumber: String?
    var totalCores: Int
    var performanceCores: Int
    var efficiencyCores: Int
    var gpuCores: Int?
    var memory: UInt64
    var osVersion: String
    var displays: [Display]
    var computerName: String? = nil      // « MacBook Pro de Marie » : le nom choisi par l'utilisateur
    var localHostName: String? = nil     // nom sur le réseau local, sans « .local »

    var title: String {
        [modelName, chip.map { "(\($0.replacingOccurrences(of: "Apple ", with: "")))" }].compactMap { $0 }.joined(separator: " ")
    }

    /// Lecture complète. `system_profiler` prend quelques dixièmes de seconde : à lancer hors du thread principal.
    static func load() -> MachineInfo {
        let hardware = runSystemProfiler().flatMap(parseHardware) ?? [:]
        let total = Int(SystemSampler.sysctl("hw.ncpu", Int32(0)) ?? 0)
        let efficiency = Int(SystemSampler.sysctl("hw.perflevel1.logicalcpu", Int32(0)) ?? 0)
        let performance = Int(SystemSampler.sysctl("hw.perflevel0.logicalcpu", Int32(0)) ?? 0)
        let v = ProcessInfo.processInfo.operatingSystemVersion

        return MachineInfo(
            modelName: hardware["machine_name"],
            modelIdentifier: hardware["machine_model"],
            chip: hardware["chip_type"] ?? hardware["cpu_type"],
            serialNumber: hardware["serial_number"],
            totalCores: total,
            performanceCores: efficiency > 0 ? performance : total,
            efficiencyCores: efficiency,
            gpuCores: gpuCoreCount(),
            memory: ProcessInfo.processInfo.physicalMemory,
            osVersion: "macOS \(v.majorVersion).\(v.minorVersion)" + (v.patchVersion > 0 ? ".\(v.patchVersion)" : ""),
            displays: [],
            computerName: SCDynamicStoreCopyComputerName(nil, nil) as String?,
            localHostName: SCDynamicStoreCopyLocalHostName(nil) as String?
        )
    }

    /// Nom du Mac sur le réseau local (Bonjour), sans lecture de `system_profiler` : instantané.
    static func localNetworkName() -> String? {
        (SCDynamicStoreCopyLocalHostName(nil) as String?).map { "\($0).local" }
    }

    /// Les écrans se lisent sur le thread principal (AppKit).
    @MainActor
    static func currentDisplays() -> [Display] {
        NSScreen.screens.map { screen in
            let scale = screen.backingScaleFactor
            let width = Int(screen.frame.width * scale), height = Int(screen.frame.height * scale)
            return Display(name: screen.localizedName, pixels: "\(width) × \(height)", refreshRate: screen.maximumFramesPerSecond)
        }
    }

    /// Sortie de `system_profiler -json SPHardwareDataType` → dictionnaire plat de chaînes. Fonction pure.
    static func parseHardware(_ data: Data) -> [String: String]? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let entry = (json["SPHardwareDataType"] as? [[String: Any]])?.first else { return nil }
        return entry.compactMapValues { $0 as? String }
    }

    private static func runSystemProfiler() -> Data? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        task.arguments = ["-json", "SPHardwareDataType"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do { try task.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return task.terminationStatus == 0 ? data : nil
    }

    private static func gpuCoreCount() -> Int? {
        for props in IORegistry.properties(matching: "IOAccelerator") {
            if let count = (props["gpu-core-count"] as? NSNumber)?.intValue, count > 0 { return count }
        }
        return nil
    }
}
