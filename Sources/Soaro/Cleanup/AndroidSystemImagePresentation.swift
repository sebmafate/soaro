import Foundation

/// Texte d'une ligne d'image système Android (R19, R12) : fonctions PURES (locale explicite), testables sans vue.
/// Vocabulaire : « system image » et « device », jamais « runtime », jamais le sigle des appareils virtuels dans l'interface.
/// La variante et l'ABI sont des données, affichées telles quelles (jamais des clés de catalogue).
enum AndroidSystemImagePresentation {
    /// Titre de la section (clé de catalogue).
    static var sectionTitle: String { String(localized: "Android system images") }

    /// Message de la section quand la lecture a échoué.
    static var couldNotReadMessage: String { String(localized: "Could not read the Android system images.") }

    /// Pied de la section : seulement quand au moins une ligne est « cannot tell ».
    static var incompleteFooter: String {
        String(localized: "Some virtual devices could not be read or are kept in another folder, so Soaro cannot tell whether these images are in use.")
    }

    /// `API 36` : le même libellé que les lignes d'émulateurs.
    static func title(image: AndroidSystemImage, locale: Locale) -> String {
        AndroidEmulatorPresentation.systemLabel(version: image.key.version, locale: locale)
    }

    /// `<variante> · <ABI>`, tels qu'ils sont écrits sur le disque.
    static func detail(image: AndroidSystemImage) -> String { "\(image.key.variant) · \(image.key.abi)" }

    /// « used by <noms affichés> », « not used by any listed device » ou « cannot tell whether a device uses it ».
    /// Les noms sont joints par « , », tels quels (jamais interprétés comme un format).
    static func usageLine(image: AndroidSystemImage, locale: Locale) -> String {
        switch image.usage {
        case .usedBy(let devices):
            let names = devices.map(\.displayName).joined(separator: ", ")
            return String(localized: "used by \(names)", locale: locale)
        case .notUsed:
            return String(localized: "not used by any listed device", locale: locale)
        case .cannotTell:
            return String(localized: "cannot tell whether a device uses it", locale: locale)
        }
    }

    /// Lecture VoiceOver, un seul élément par ligne : titre, variante, ABI, taille (omise tant qu'elle est inconnue) et ligne d'usage,
    /// joints par « , ». Pas de valeur « Selected » ni « Not selected » : la ligne n'est pas sélectionnable.
    static func accessibilityLabel(image: AndroidSystemImage, size: UInt64?, locale: Locale) -> String {
        [title(image: image, locale: locale), image.key.variant, image.key.abi,
         size.map { Format.fileBytes($0, locale: locale) } ?? "", usageLine(image: image, locale: locale)]
            .filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
