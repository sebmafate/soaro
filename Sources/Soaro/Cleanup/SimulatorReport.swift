import Foundation

/// Mise en forme de la section « iOS Simulators » de `Soaro --scan`.
/// Fonction PURE (résultat du scan, suggestions, locale et limite explicites) : testable sans toucher à la sortie standard.
/// Texte anglais brut, comme les autres sections de `--scan` : volontairement ni `String(localized:)` ni clé de catalogue.
/// L'UDID est affiché (sortie locale, pour comparer avec `simctl`) ; aucun chemin n'est jamais affiché.
enum SimulatorReport {
    static func lines(scan: SimulatorScan, suggestions: DeviceSuggestions.Result, locale: Locale, limitDays: Int) -> [String] {
        var out = ["== iOS Simulators"]

        switch scan.status {
        case .toolNotFound:
            out.append("xcrun not found")
            return out
        case .commandFailed(let code):
            out.append(code.map { "command failed (exit code \($0))" } ?? "command failed")
            return out
        case .timedOut:
            out.append("did not answer within \(Int(SimulatorScanner.listTimeLimit)) s")
            return out
        case .outputNotReadable:
            out.append("output not readable")
            return out
        case .ok:
            break
        }

        let total = scan.devices.reduce(UInt64(0)) { $0 + $1.size }
        let threshold = Format.fileBytes(DeviceSuggestions.smallDeviceThreshold, locale: locale)
        out.append("\(scan.devices.count) \(scan.devices.count == 1 ? "device" : "devices"), \(Format.fileBytes(total, locale: locale)) allocated"
                   + " · inactive limit \(limitDays) d · devices under \(threshold) are counted, not listed")

        for row in suggestions.rows {
            let device = row.device.device
            var parts = [Format.fileBytes(row.device.size, locale: locale),
                         "\(device.name) (\(device.runtimeName))",
                         device.udid,
                         row.daysSinceLastUse.map { "last used \($0) d" } ?? "last used unknown"]
            if row.isPreSelected {
                var reasons: [String] = []
                if row.isInactive, let days = row.daysSinceLastUse { reasons.append("inactive for \(days) d") }
                if row.isOlderCopy { reasons.append("older copy") }
                parts.append("pre-selected (\(reasons.joined(separator: ", ")))")
            }
            if row.isRunning { parts.append("running") }
            if !device.isAvailable { parts.append("unavailable") }
            out.append(parts.joined(separator: "  "))
        }

        if suggestions.hiddenSmallCount > 0 {
            let n = suggestions.hiddenSmallCount
            out.append("\(n) small \(n == 1 ? "device" : "devices") (\(Format.fileBytes(suggestions.hiddenSmallSize, locale: locale))) not listed")
        }
        out.append("Pre-selected: \(suggestions.preSelectedCount) · \(Format.fileBytes(suggestions.preSelectedSize, locale: locale))")
        return out
    }
}
