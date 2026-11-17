import Foundation

/// Mise en forme de la section « Android emulators » de `Soaro --scan`.
/// Fonction PURE (résultat du scan, suggestions, locale et fuseau explicites), texte anglais brut comme les autres sections de
/// `--scan` : volontairement ni `String(localized:)` ni clé de catalogue. Aucun chemin n'est jamais affiché.
enum AndroidEmulatorReport {
    static func lines(scan: AndroidScan, suggestions: DeviceSuggestions.AndroidResult, locale: Locale,
                      timeZone: TimeZone = .current) -> [String] {
        var out = ["== Android emulators"]
        switch scan.status {
        case .sdkNotFound:
            out.append("Android SDK not found")
            return out
        case .couldNotRead:
            out.append("could not read the Android emulators")
            return out
        case .ok:
            if scan.devices.isEmpty {
                out.append("no Android virtual device")
                return out
            }
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        func day(_ date: Date) -> String {
            let c = calendar.dateComponents([.year, .month, .day], from: date)
            return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        }

        for row in suggestions.rows {
            let device = row.device.device
            let system = device.systemVersion.map { "API \($0)" } ?? "unknown system"
            var parts = [Format.fileBytes(row.device.size, locale: locale),
                         device.name,
                         "\(device.displayName) (\(system))"]
            if let date = device.lastUsed, let days = row.daysSinceLastUse {
                parts.append("last used \(day(date)) (\(days) d, from \(device.lastUsedSource ?? "?"))")
            } else {
                parts.append("last used unknown")
            }
            if row.isRunning { parts.append("running") }
            if row.isPreSelected { parts.append("pre-selected: inactive") }
            out.append(parts.joined(separator: "  "))
        }

        if suggestions.hiddenSmallCount > 0 {
            let n = suggestions.hiddenSmallCount
            out.append("\(n) small \(n == 1 ? "device" : "devices") (\(Format.fileBytes(suggestions.hiddenSmallSize, locale: locale))) not listed")
        }
        if let sdk = scan.sdk { out.append("SDK source: \(sdk.source.rawValue)") }
        return out
    }
}
