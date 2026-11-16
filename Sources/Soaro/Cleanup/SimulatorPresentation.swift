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

    /// NB : `SimulatorReport` (anglais brut de `--scan`) a son propre texte « older copy of … » : les deux partent du même
    /// `row.keptDevice` (un test les garde d'accord, `theScanReportAndTheScreenNameTheSameKeptDevice`).
    ///
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
        let days = kept.device.lastUsed.map { DeviceSuggestions.wholeDays(from: $0, to: now) } ?? 0
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

    // MARK: Bandeau et pied de page

    /// Bandeau affiché quand des lignes sont listées mais qu'aucune n'est pré-sélectionnée.
    static func nothingToSuggest(limitDays: Int, locale: Locale = .current) -> String {
        String(localized: "Nothing to suggest at \(limitDays) days. Pick devices yourself, or lower the limit.", locale: locale)
    }

    /// Pied de page : appareils trop petits, comptés mais non listés. `nil` s'il n'y en a aucun.
    /// (Pas de forme plurielle : le catalogue les refuse ; « 1 small devices » est accepté, voir le brief de SL8.)
    static func smallDevicesFooter(count: Int, size: UInt64, locale: Locale) -> String? {
        guard count > 0 else { return nil }
        return String(localized: "\(count) small devices (\(Format.fileBytes(size, locale: locale))) not shown.", locale: locale)
    }

    /// Explication des règles de pré-sélection et de la suppression, avec la limite courante.
    static func explanationFooter(limitDays: Int, locale: Locale = .current) -> String {
        String(localized: "Devices inactive for more than \(limitDays) days, and older copies of the same model, are pre-selected. A removed device takes its apps, data and snapshots with it; create a new one from Xcode or Android Studio.", locale: locale)
    }

    // MARK: En-tête

    /// « Devices: N · X » : appareils listés et somme de leurs tailles mesurées.
    static func headerSummary(count: Int, size: UInt64, locale: Locale = .current) -> String {
        String(localized: "Devices: \(count) · \(Format.fileBytes(size, locale: locale))", locale: locale)
    }
}
