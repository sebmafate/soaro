import Foundation

/// Images système du SDK Android pour l'outil « Simulators and emulators » (R19, SL12a). Ce fichier LIT seulement (ADR 0009) :
/// il ne supprime, ne déplace ni n'écrit rien, ne lance aucun outil (aucun lanceur de commandes) et n'utilise pas le réseau.
/// Une source test interdit tout code de suppression dans les fichiers `AndroidSystemImage*.swift`.

/// La clé d'une image système : `android-<N>[.<M>]/<variante>/<ABI>`. Deux clés qui ne diffèrent que par la casse sont égales
/// (APFS ignore la casse : un faux « utilisée » reste du côté sûr).
struct AndroidSystemImageKey: Hashable {
    /// `"36"` ou `"36.1"`.
    let version: String
    let variant: String
    let abi: String

    /// Le chemin relatif `android-<N>[.<M>]/<variante>/<ABI>`.
    var path: String { "android-\(version)/\(variant)/\(abi)" }

    static func == (a: AndroidSystemImageKey, b: AndroidSystemImageKey) -> Bool { a.path.lowercased() == b.path.lowercased() }

    func hash(into hasher: inout Hasher) { hasher.combine(path.lowercased()) }
}

enum AndroidSystemImageScanner {
    /// Le premier segment d'une image : `android-<N>` ou `android-<N>.<M>` ; renvoie la version, sinon `nil`
    /// (`android-Baklava` n'est pas une image publiée : écartée).
    static func version(ofFolderName name: String) -> String? {
        guard name.range(of: "^android-[0-9]+(\\.[0-9]+)?$", options: .regularExpression) != nil else { return nil }
        return String(name.dropFirst("android-".count))
    }

    /// La clé d'image d'un `image.sysdir.1`. Même règle de segments que `AndroidEmulatorScanner.systemVersion` : couper sur `/`,
    /// ignorer les parties vides, trouver le premier `system-images`, prendre les trois segments suivants. La variante et l'ABI
    /// doivent être des noms valides (`isValidAVDName`). Tout autre cas, ou une valeur absente, donne `nil`.
    static func imageKey(imageSysdir: String?) -> AndroidSystemImageKey? {
        guard let imageSysdir else { return nil }
        let parts = imageSysdir.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard let index = parts.firstIndex(of: "system-images"), index + 3 < parts.count,
              let version = version(ofFolderName: parts[index + 1]) else { return nil }
        let variant = parts[index + 2]
        let abi = parts[index + 3]
        guard AndroidEmulatorScanner.isValidAVDName(variant), AndroidEmulatorScanner.isValidAVDName(abi) else { return nil }
        return AndroidSystemImageKey(version: version, variant: variant, abi: abi)
    }
}
