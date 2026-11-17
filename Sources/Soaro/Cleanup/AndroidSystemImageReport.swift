import Foundation

/// Mise en forme de la section « Android system images » de `Soaro --scan`.
/// Fonction PURE (résultat du scan et locale explicites), texte anglais brut comme les autres sections de `--scan` :
/// volontairement ni `String(localized:)` ni clé de catalogue. Aucun chemin ni valeur d'environnement n'est jamais affiché.
enum AndroidSystemImageReport {
    static func lines(scan: AndroidSystemImageScan, locale: Locale) -> [String] {
        let listing = scan.listing
        var out = ["== Android system images"]
        switch listing.status {
        case .sdkNotFound:
            out.append("Android SDK not found")
            return out
        case .sdkOutsideHome:
            out.append("system images not read: the SDK is outside the home folder")
        case .unreadable:
            out.append("could not read the Android system images")
        case .ok:
            if listing.images.isEmpty { out.append("no system image") }
        }

        for image in listing.images {
            let size = scan.sizes[image.key].map { Format.fileBytes($0, locale: locale) } ?? "?"
            out.append([size, image.key.path, "API \(image.key.version)", usageText(image.usage)].joined(separator: "  "))
        }
        if listing.status == .ok {
            out.append(contentsOf: listing.incompleteness.reasons.map(note))
            if listing.skippedCount > 0 {
                let n = listing.skippedCount
                out.append("\(n) \(n == 1 ? "folder" : "folders") skipped (not an android-<N> image, outside the home or no package file)")
            }
            if !listing.images.isEmpty { out.append("note: read-only; Soaro does not remove system images") }
        }
        if let sdk = listing.sdk { out.append("SDK source: \(sdk.source.rawValue)") }
        return out
    }

    /// Les noms d'AVD (comme la section des émulateurs), jamais les noms affichés.
    private static func usageText(_ usage: AndroidSystemImage.Usage) -> String {
        switch usage {
        case .usedBy(let devices): "used by " + devices.map(\.name).joined(separator: ", ")
        case .notUsed: "not used by any listed AVD"
        case .cannotTell: "cannot tell (see the notes)"
        }
    }

    private static func note(_ reason: AndroidSystemImageIncompleteness.Reason) -> String {
        switch reason {
        case .customLocation(let variables):
            "note: \(variables.joined(separator: ", ")) \(variables.count == 1 ? "is" : "are") set: virtual devices there are not read, so an image may be in use"
        case .avdFolderUnreadable:
            "note: the AVD folder could not be read"
        case .skippedRegistrations(let n):
            "note: \(n) \(n == 1 ? "registration" : "registrations") could not be read"
        case .unknownImage(let n):
            "note: \(n) \(n == 1 ? "AVD has" : "AVDs have") no readable system image"
        }
    }
}
