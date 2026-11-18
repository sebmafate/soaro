import Foundation

/// Une taille telle que Docker l'écrit : décimale (1 Ko = 1000 octets), « 22.46GB », « 114.7kB », « 0B ».
enum DockerSize {
    private static let units: [String: Double] = [
        "B": 1, "kB": 1e3, "KB": 1e3, "MB": 1e6, "GB": 1e9, "TB": 1e12, "PB": 1e15,
    ]

    /// Octets, ou `nil` quand le texte n'est pas une taille (jamais une valeur devinée). Un pourcentage qui suit (« 580.7MB (28%) »)
    /// est ignoré : seule la première partie compte.
    static func parse(_ text: String) -> UInt64? {
        let first = text.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
        guard first.range(of: #"^[0-9]+(\.[0-9]+)?(B|kB|KB|MB|GB|TB|PB)$"#, options: .regularExpression) != nil,
              let split = first.firstIndex(where: { $0.isLetter }),
              let number = Double(first[..<split]),
              let unit = units[String(first[split...])] else { return nil }
        let bytes = (number * unit).rounded()
        guard bytes.isFinite, bytes >= 0, bytes < 1.8e19 else { return nil }
        return UInt64(bytes)
    }
}

/// Une ligne de `docker system df` : chaque champ est `nil` quand Docker ne l'a pas donné ou qu'il est illisible.
struct DockerUsageLine: Equatable {
    /// `TotalCount`.
    let total: Int?
    /// `Active` : ce qu'un conteneur utilise.
    let active: Int?
    /// `Size` (octets décimaux, ceux de Docker).
    let size: UInt64?
    /// `Reclaimable`, sans le pourcentage.
    let reclaimable: UInt64?
}

/// Ce que `docker system df` dit de l'usage : une ligne par type, `nil` quand la ligne manque (inconnue, jamais zéro).
struct DockerUsage: Equatable {
    let images: DockerUsageLine?
    let containers: DockerUsageLine?
    let volumes: DockerUsageLine?
    let buildCache: DockerUsageLine?
}

/// Une image sans étiquette (« dangling ») de `docker images -f dangling=true`.
struct DockerUntaggedImage: Equatable {
    /// Identifiant court ou long, sans `sha256:`. Sert d'identité seulement : il n'entre jamais dans une commande.
    let id: String
    /// `Size` (octets décimaux), `nil` si absente ou illisible.
    let size: UInt64?
    /// `Containers` : nombre de conteneurs (arrêtés ou non) qui l'utilisent ; `nil` quand Docker ne le dit pas (`N/A`).
    let containerCount: Int?

    /// Seule une image dont Docker dit qu'AUCUN conteneur ne l'utilise est dans la liste à nettoyer (R10). « Je ne sais pas » vaut « utilisée ».
    var isRemovable: Bool { containerCount == 0 }
}

/// Lecture défensive de la sortie de `docker` (R6, ADR 0005) : ni plantage, ni chiffre faux. Un champ absent, mal formé ou inconnu devient
/// `nil` ; un champ ou un type inconnu est ignoré.
enum DockerReport {
    // MARK: `docker system df --format '{{json .}}'`

    /// - Returns: `nil` si aucune ligne reconnue (sortie vide, texte d'erreur, autre outil) ; sinon l'usage, avec `nil` pour tout ce qui manque.
    ///   Pour un type donné la première ligne gagne.
    static func parseUsage(_ data: Data) -> DockerUsage? {
        guard let objects = jsonObjects(in: data) else { return nil }
        var images: DockerUsageLine?, containers: DockerUsageLine?, volumes: DockerUsageLine?, cache: DockerUsageLine?
        var recognised = false
        for object in objects {
            guard let type = object["Type"] as? String else { continue }
            let line = DockerUsageLine(total: count(object["TotalCount"]), active: count(object["Active"]),
                                       size: size(object["Size"]), reclaimable: size(object["Reclaimable"]))
            switch type {
            case "Images": if images == nil { images = line }; recognised = true
            case "Containers": if containers == nil { containers = line }; recognised = true
            case "Local Volumes": if volumes == nil { volumes = line }; recognised = true
            case "Build Cache": if cache == nil { cache = line }; recognised = true
            default: continue
            }
        }
        guard recognised else { return nil }
        return DockerUsage(images: images, containers: containers, volumes: volumes, buildCache: cache)
    }

    // MARK: `docker images -f dangling=true --format '{{json .}}'`

    /// - Returns: la liste (vide : aucune image sans étiquette), sans doublon, dans l'ordre de Docker ; `nil` quand la sortie n'est pas
    ///   une liste d'images (aucune ligne n'a de clé `ID`). Une entrée sans identifiant valide est ignorée.
    static func parseUntaggedImages(_ data: Data) -> [DockerUntaggedImage]? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [] }
        guard let objects = jsonObjects(in: data) else { return nil }
        var result: [DockerUntaggedImage] = []
        var seen = Set<String>()
        var recognised = false
        for object in objects where object["ID"] != nil {
            recognised = true
            guard let raw = object["ID"] as? String else { continue }
            let id = raw.hasPrefix("sha256:") ? String(raw.dropFirst(7)) : raw
            guard id.range(of: "^[0-9a-f]{12,64}$", options: .regularExpression) != nil, seen.insert(id).inserted else { continue }
            result.append(DockerUntaggedImage(id: id, size: size(object["Size"]), containerCount: count(object["Containers"])))
        }
        return recognised ? result : nil
    }

    // MARK: Sortie d'un nettoyage

    /// Le chiffre de Docker : la dernière ligne « Total: 22.46GB » (cache de build) ou « Total reclaimed space: 397MB » (images).
    /// `nil` quand elle manque ou n'est pas lisible (jamais un chiffre deviné).
    static func parsePruneTotal(_ data: Data) -> UInt64? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        for line in text.split(whereSeparator: { $0.isNewline }).reversed() {
            for prefix in ["Total reclaimed space:", "Total:"] where line.hasPrefix(prefix) {
                return DockerSize.parse(line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces))
            }
        }
        return nil
    }

    // MARK: Aides

    /// Les objets JSON de la sortie : une ligne par objet (`--format '{{json .}}'`), ou un seul tableau. Les lignes illisibles sont ignorées.
    /// `nil` si le texte n'est pas de l'UTF-8 ; une liste vide si rien n'est exploitable.
    private static func jsonObjects(in data: Data) -> [[String: Any]]? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("["), let array = (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) as? [Any] {
            return array.compactMap { $0 as? [String: Any] }
        }
        return text.split(whereSeparator: { $0.isNewline }).compactMap { line in
            (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any]
        }
    }

    private static func size(_ value: Any?) -> UInt64? {
        (value as? String).flatMap(DockerSize.parse)
    }

    /// Un nombre entier, positif ou nul : une chaîne (« 4 ») ou un nombre JSON. Tout le reste est inconnu.
    private static func count(_ value: Any?) -> Int? {
        if let text = value as? String {
            guard text.range(of: "^[0-9]{1,9}$", options: .regularExpression) != nil else { return nil }
            return Int(text)
        }
        if let number = value as? Int, number >= 0 { return number }
        return nil
    }
}
