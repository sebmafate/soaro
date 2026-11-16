import Foundation

/// Texte d'une ligne de simulateur (R3, R6) : fonctions PURES (instant et locale explicites), testables sans vue.
/// Vocabulaire : « device », « inactive for N d », « older copy », jamais le mot « runtime ».
/// Les noms d'appareils sont affichés tels quels (jamais des clés de catalogue).
enum SimulatorPresentation {
    // MARK: Système

    /// `com.apple.CoreSimulator.SimRuntime.iOS-26-2` → `iOS 26.2` ; `xrOS` s'affiche `visionOS`.
    /// Un identifiant illisible donne « Unknown system » : jamais l'identifiant brut.
    static func systemLabel(runtimeIdentifier: String) -> String {
        let name = SimulatorScanner.runtimeName(runtimeIdentifier)
        guard name != runtimeIdentifier, let space = name.firstIndex(of: " ") else { return String(localized: "Unknown system") }
        let platform = name[..<space]
        let version = name[name.index(after: space)...]
        return platform == "xrOS" ? "visionOS \(version)" : name
    }

    // MARK: Raison

    /// « Running · quit it first » pour un appareil en cours d'exécution (variante « indisponible » de SL3), `nil` sinon.
    static func unavailableReason(for row: DeviceSuggestions.Row) -> String? {
        row.isRunning ? String(localized: "Running · quit it first") : nil
    }

    /// Ligne de raison d'une ligne sélectionnable, morceaux joints par « · » :
    /// jours (« inactive for N d », « active today », « activity unknown »), puis « older copy of “nom”, … »,
    /// puis « unavailable: system not installed ». Vide pour un appareil en cours d'exécution (sa raison est `unavailableReason`).
    static func reasonLine(for row: DeviceSuggestions.Row, now: Date, locale: Locale) -> String {
        if row.isRunning { return "" }
        var parts: [String] = []
        if let days = row.daysSinceLastUse {
            parts.append(days == 0 ? String(localized: "active today", locale: locale)
                                   : String(localized: "inactive for \(days) d", locale: locale))
        } else {
            parts.append(String(localized: "activity unknown", locale: locale))
        }
        if row.isOlderCopy, let kept = row.keptDevice {
            parts.append(olderCopyPart(kept: kept, now: now, locale: locale))
        }
        if !row.device.device.isAvailable {
            parts.append(String(localized: "unavailable: system not installed", locale: locale))
        }
        return parts.joined(separator: " · ")
    }

    private static func olderCopyPart(kept: SizedSimulator, now: Date, locale: Locale) -> String {
        let name = kept.device.name
        if kept.device.state != "Shutdown" {
            return String(localized: "older copy of “\(name)”, which is running", locale: locale)
        }
        let days = kept.device.lastUsed.map { max(0, Int(now.timeIntervalSince($0) / 86_400)) } ?? 0
        return days == 0 ? String(localized: "older copy of “\(name)”, used today", locale: locale)
                         : String(localized: "older copy of “\(name)”, used \(days) d ago", locale: locale)
    }

    // MARK: Taille et VoiceOver

    /// Taille affichée : « … » tant qu'elle n'est pas mesurée.
    static func sizeText(_ size: UInt64?, locale: Locale) -> String {
        size.map { Format.fileBytes($0, locale: locale) } ?? "…"
    }

    /// Lecture VoiceOver : libellé = nom, système, taille (omise tant qu'elle est inconnue), ligne de raison, joints par « , » ;
    /// valeur = « Selected » / « Not selected », ou « Running · quit it first, not selectable » pour un appareil en cours d'exécution.
    static func accessibility(name: String, row: DeviceSuggestions.Row, size: UInt64?, isOn: Bool,
                              now: Date, locale: Locale) -> SelectionAccessibility.Description {
        SelectionAccessibility.description(name: name, details: accessibilityDetails(row: row, size: size, now: now, locale: locale),
                                           isOn: isOn, unavailableReason: unavailableReason(for: row))
    }

    /// Morceaux lus après le nom : système, taille connue, ligne de raison.
    static func accessibilityDetails(row: DeviceSuggestions.Row, size: UInt64?, now: Date, locale: Locale) -> [String] {
        [systemLabel(runtimeIdentifier: row.device.device.runtimeIdentifier),
         size.map { Format.fileBytes($0, locale: locale) } ?? "",
         reasonLine(for: row, now: now, locale: locale)]
    }
}
