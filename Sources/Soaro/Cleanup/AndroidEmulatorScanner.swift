import Foundation

/// Appareils virtuels Android (AVD) pour l'outil « Simulators and emulators » (R16, R18). LECTURE SEULE (ADR 0009) :
/// rien n'est supprimé, déplacé ni écrit sous `~/.android` ou dans le SDK ; aucun outil du SDK n'est lancé.
/// Cette première partie : fonctions PURES de lecture des fichiers d'un AVD (aucun accès au disque).
enum AndroidEmulatorScanner {
    // MARK: Nom

    /// Un nom d'AVD est valide s'il tient dans `[A-Za-z0-9._-]`, a au moins un caractère et n'est ni `.` ni `..`.
    /// C'est la SEULE chose qui est ensuite jointe à un chemin ou comparée à une ligne de processus.
    static func isValidAVDName(_ name: String) -> Bool {
        guard !name.isEmpty, name != ".", name != ".." else { return false }
        return name.utf8.allSatisfy { byte in
            switch byte {
            case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "0")...UInt8(ascii: "9"),
                 UInt8(ascii: "."), UInt8(ascii: "_"), UInt8(ascii: "-"): true
            default: false
            }
        }
    }

    // MARK: Fichiers INI

    /// Lit un fichier `clé=valeur` (`<nom>.ini`, `config.ini`) : coupe à la PREMIÈRE `=`, clés et valeurs sans blancs autour ;
    /// lignes vides, lignes commençant par `#` ou `;`, lignes sans `=` ignorées ; pour une clé répétée la première gagne.
    /// - Returns: `nil` si le contenu n'est pas de l'UTF-8 valide.
    static func parseINI(_ data: Data) -> [String: String]? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        var values: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix(";") { continue }
            guard let equals = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[..<equals].trimmingCharacters(in: .whitespaces)
            let value = trimmed[trimmed.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if key.isEmpty || values[key] != nil { continue }
            values[key] = value
        }
        return values
    }

    // MARK: Système et nom affiché

    /// `system-images/android-36/google_apis_playstore/arm64-v8a/` donne `"36"` ; `android-36.1` donne `"36.1"`.
    /// Le segment qui suit `system-images` doit avoir la forme `android-<N>` ou `android-<N>.<M>` ; tout autre cas
    /// (`android-Baklava`, clé absente) donne `nil`, affiché « Unknown system ».
    static func systemVersion(imageSysdir: String?) -> String? {
        guard let imageSysdir else { return nil }
        let parts = imageSysdir.split(separator: "/", omittingEmptySubsequences: true)
        guard let index = parts.firstIndex(of: "system-images"), index + 1 < parts.count else { return nil }
        let segment = String(parts[index + 1])
        guard segment.range(of: "^android-[0-9]+(\\.[0-9]+)?$", options: .regularExpression) != nil else { return nil }
        return String(segment.dropFirst("android-".count))
    }

    /// `avd.ini.displayname` de `config.ini` quand il existe et n'est pas vide, sinon le nom de l'AVD.
    static func displayName(config: [String: String], avdName: String) -> String {
        let name = config["avd.ini.displayname"]?.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? avdName : name
    }
}
