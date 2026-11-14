import Foundation
import IOKit

/// Lecture des propriétés du registre IOKit.
enum IORegistry {
    static func properties(matching className: String) -> [[String: Any]] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var result: [[String: Any]] = []
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = props?.takeRetainedValue() as? [String: Any] {
                result.append(dict)
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
        return result
    }
}

private func number(_ value: Any?) -> NSNumber? { value as? NSNumber }
private func intValue(_ value: Any?) -> Int? { number(value)?.intValue }
/// Les valeurs signées (ampérage) sont parfois exposées en non signé : on reconstitue le signe.
private func signedValue(_ value: Any?) -> Int64? { number(value).map { Int64(truncatingIfNeeded: $0.uint64Value) } }

// MARK: - GPU

enum GPUSampler {
    static func sample() -> GPUStats? {
        var best: GPUStats?
        for props in IORegistry.properties(matching: "IOAccelerator") {
            guard let stats = props["PerformanceStatistics"] as? [String: Any] else { continue }
            let utilization = Double(intValue(stats["Device Utilization %"]) ?? 0) / 100
            let memory = UInt64(max(0, intValue(stats["In use system memory"]) ?? 0))
            let candidate = GPUStats(utilization: min(1, max(0, utilization)), memoryUsed: memory)
            if best == nil || candidate.utilization > best!.utilization { best = candidate }
        }
        return best
    }
}

// MARK: - Batterie

enum BatterySampler {
    static func sample() -> BatteryStats? {
        guard let props = IORegistry.properties(matching: "AppleSmartBattery").first else { return nil }
        return parse(props)
    }

    /// Fonction pure (testable) : propriétés `AppleSmartBattery` → statistiques.
    static func parse(_ props: [String: Any]) -> BatteryStats? {
        guard (number(props["BatteryInstalled"])?.boolValue ?? true) else { return nil }
        guard let current = intValue(props["CurrentCapacity"]),
              let max = intValue(props["MaxCapacity"]), max > 0 else { return nil }

        let data = props["BatteryData"] as? [String: Any] ?? [:]
        let percent = Swift.min(100, Double(current) / Double(max) * 100)
        let pluggedIn = number(props["ExternalConnected"])?.boolValue ?? false
        let charging = number(props["IsCharging"])?.boolValue ?? false
        let full = number(props["FullyCharged"])?.boolValue ?? false

        // Durée restante (65535 = « en cours de calcul »)
        func valid(_ v: Int?) -> Int? { (v != nil && v! > 0 && v! < 65_535) ? v : nil }
        let minutes: Int? = charging
            ? valid(intValue(props["AvgTimeToFull"]))
            : (pluggedIn ? nil : (valid(intValue(props["TimeRemaining"])) ?? valid(intValue(props["AvgTimeToEmpty"]))))

        // Santé : capacité nominale actuelle / capacité d'origine
        let design = intValue(data["DesignCapacity"]) ?? intValue(props["DesignCapacity"])
        let nominal = intValue(data["NominalChargeCapacity"])
            ?? intValue(props["NominalChargeCapacity"])
            ?? intValue(props["AppleRawMaxCapacity"])
        var health: Double?
        if let design, design > 0, let nominal, nominal > 0 {
            health = Swift.min(1, Double(nominal) / Double(design))
        }

        // Température en centièmes de °C
        var temperature: Double?
        if let t = intValue(props["Temperature"]), t > 0 { temperature = Double(t) / 100 }

        // Puissance de la batterie : mV × mA
        var batteryPower: Double?
        if let mv = intValue(props["Voltage"]), let ma = signedValue(props["InstantAmperage"] ?? props["Amperage"]) {
            batteryPower = Double(mv) * Double(ma) / 1_000_000
        }

        var systemPower: Double?
        if let telemetry = props["PowerTelemetryData"] as? [String: Any], let load = intValue(telemetry["SystemLoad"]), load > 0 {
            systemPower = Double(load) / 1000
        }

        let adapter = (props["AdapterDetails"] as? [String: Any]).flatMap { intValue($0["Watts"]) }

        return BatteryStats(
            percent: percent,
            isCharging: charging,
            isPluggedIn: pluggedIn,
            isFullyCharged: full,
            minutesRemaining: minutes,
            cycleCount: intValue(props["CycleCount"]) ?? 0,
            health: health,
            designCapacity: design,
            maxCapacity: nominal,
            temperature: temperature,
            batteryPower: batteryPower,
            systemPower: systemPower,
            adapterWatts: pluggedIn ? adapter : nil
        )
    }
}

// MARK: - Entrées/sorties disque

final class DiskIOSampler {
    private var previous: (date: Date, read: UInt64, write: UInt64)?

    func sample() -> DiskIOStats? {
        var read: UInt64 = 0
        var write: UInt64 = 0
        var found = false
        for props in IORegistry.properties(matching: "IOBlockStorageDriver") {
            guard let stats = props["Statistics"] as? [String: Any] else { continue }
            found = true
            read += number(stats["Bytes (Read)"])?.uint64Value ?? 0
            write += number(stats["Bytes (Write)"])?.uint64Value ?? 0
        }
        guard found else { return nil }

        let now = Date()
        defer { previous = (now, read, write) }
        guard let prev = previous, read >= prev.read, write >= prev.write else {
            return DiskIOStats(readRate: 0, writeRate: 0)
        }
        let dt = now.timeIntervalSince(prev.date)
        guard dt > 0 else { return DiskIOStats(readRate: 0, writeRate: 0) }
        return DiskIOStats(readRate: Double(read - prev.read) / dt, writeRate: Double(write - prev.write) / dt)
    }

    /// État SMART du disque interne (« Verified » sur un SSD sain). Appelle `diskutil` : à ne pas faire souvent.
    static func smartStatus() -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        task.arguments = ["info", "disk0"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do { try task.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") where line.contains("SMART Status") {
            return line.split(separator: ":", maxSplits: 1).last.map { $0.trimmingCharacters(in: .whitespaces) }
        }
        return nil
    }
}
