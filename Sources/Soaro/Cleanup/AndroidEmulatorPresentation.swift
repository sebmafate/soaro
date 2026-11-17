import Foundation

/// Texte d'une ligne d'émulateur Android (R16, R12) : fonctions PURES (locale explicite), testables sans vue.
/// Vocabulaire : « device », « inactive for N d », jamais le mot « runtime ».
/// Les noms d'appareils sont affichés tels quels (jamais des clés de catalogue).
enum AndroidEmulatorPresentation {
    /// Titre de la section (clé de catalogue).
    static var sectionTitle: String { String(localized: "Android emulators") }

    /// Message de la section quand la lecture a échoué (AVD illisibles ou liste des processus indisponible).
    static var couldNotReadMessage: String { String(localized: "Could not read the Android emulators.") }

    /// `"36"` donne `API 36` ; sans version lisible : « Unknown system ».
    static func systemLabel(version: String?, locale: Locale) -> String {
        guard let version else { return String(localized: "Unknown system", locale: locale) }
        return String(localized: "API \(version)", locale: locale)
    }

    /// « Running · quit it first » pour un appareil en cours d'exécution, `nil` sinon.
    static func unavailableReason(for row: DeviceSuggestions.AndroidRow) -> String? {
        row.isRunning ? String(localized: "Running · quit it first") : nil
    }

    /// « inactive for N d », « active today » ou « activity unknown » ; vide pour un appareil en cours d'exécution
    /// (sa raison est `unavailableReason`).
    static func reasonLine(for row: DeviceSuggestions.AndroidRow, locale: Locale) -> String {
        if row.isRunning { return "" }
        guard let days = row.daysSinceLastUse else { return String(localized: "activity unknown", locale: locale) }
        return days == 0 ? String(localized: "active today", locale: locale) : String(localized: "inactive for \(days) d", locale: locale)
    }

    /// Morceaux lus après le nom : système, taille connue, ligne de raison.
    static func accessibilityDetails(row: DeviceSuggestions.AndroidRow, size: UInt64?, locale: Locale) -> [String] {
        [systemLabel(version: row.device.device.systemVersion, locale: locale),
         size.map { Format.fileBytes($0, locale: locale) } ?? "",
         reasonLine(for: row, locale: locale)]
    }

    /// Lecture VoiceOver, comme pour iOS : libellé = nom affiché, système, taille (omise tant qu'elle est inconnue), raison ;
    /// valeur = « Selected » / « Not selected », ou « Running · quit it first, not selectable ».
    static func accessibility(row: DeviceSuggestions.AndroidRow, size: UInt64?, isOn: Bool, locale: Locale) -> SelectionAccessibility.Description {
        SelectionAccessibility.description(name: row.device.device.displayName,
                                           details: accessibilityDetails(row: row, size: size, locale: locale),
                                           isOn: isOn, unavailableReason: unavailableReason(for: row))
    }
}
