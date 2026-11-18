import Foundation

/// Le moteur Docker sur lequel le nettoyage tournerait : le contexte COURANT de la CLI et sa prise locale (SL16, R9, R10).
/// Soaro ne nettoie que Docker sur CE Mac : une prise `unix://`. Jamais `tcp://`, `ssh://`, `npipe` ni un contexte illisible.
struct DockerEngine: Equatable {
    /// Nom du contexte (« desktop-linux », « default », « orbstack »…).
    let contextName: String
    /// Chemin ABSOLU de la prise, tel que Docker l'écrit après `unix://`.
    let socketPath: String
}

/// Ce que dit la vérification du moteur et du constructeur, avant le listage et juste avant chaque nettoyage.
enum DockerEngineCheck: Equatable {
    /// Contexte local ET constructeur local (pilote `docker`) : on peut lister, puis nettoyer.
    case local(DockerEngine)
    /// Contexte ou constructeur non local, ou réponse vide, illisible, tronquée, en échec : rien ne tourne (échec fermé).
    case notLocal
    /// Contexte local, mais le moteur ne répond pas (arrêté) : « Docker is not running ».
    case notRunning
    /// `docker` n'a pas répondu dans le délai.
    case timedOut
}

/// L'état du constructeur buildx courant.
enum DockerBuilderState: Equatable {
    /// Pilote `docker` (le constructeur du moteur local), points d'accès des nœuds locaux.
    case local
    /// Un autre pilote (`docker-container`, `kubernetes`, `remote`…), un point d'accès distant, ou une réponse qu'on ne sait pas lire.
    case notLocal
    /// Pilote vide avec une erreur : le moteur du contexte (déjà reconnu local) ne répond pas.
    case unreachable
}

/// Lecture DÉFENSIVE de `docker context inspect` et de `docker buildx inspect` (fonctions pures). Tout ce qui n'est pas clairement local est refusé.
enum DockerEngineReport {
    /// Le contexte courant, ou `nil` si ce n'est pas CLAIREMENT un moteur local : sortie illisible, vide, plusieurs contextes, pas de nom, pas de
    /// point d'accès `docker`, point d'accès autre que `unix:///chemin-absolu`, caractère de contrôle.
    static func parseContext(_ data: Data) -> DockerEngine? {
        guard let json = try? JSONSerialization.jsonObject(with: data), let contexts = json as? [Any], contexts.count == 1,
              let context = contexts[0] as? [String: Any],
              let name = context["Name"] as? String, !name.isEmpty, !hasControlCharacter(name),
              let endpoints = context["Endpoints"] as? [String: Any],
              let docker = endpoints["docker"] as? [String: Any],
              let host = docker["Host"] as? String, !hasControlCharacter(host) else { return nil }
        let prefix = "unix://"
        guard host.hasPrefix(prefix) else { return nil }
        let path = String(host.dropFirst(prefix.count))
        // Un chemin absolu qui désigne autre chose que la racine : « unix:// », « unix:/// » et « unix://relatif » sont refusés.
        guard path.hasPrefix("/"), path.count > 1 else { return nil }
        return DockerEngine(contextName: name, socketPath: path)
    }

    /// Le constructeur courant d'après `docker buildx inspect` (texte : `Name:`, `Driver:`, `Error:` en tête, puis les nœuds avec `Endpoint:`).
    /// - `Driver: docker` : local, À CONDITION que chaque `Endpoint:` de nœud soit le nom du contexte courant ou une prise `unix://`
    ///   (un constructeur au pilote `docker` créé vers une autre machine, ou le constructeur d'un autre contexte, est refusé). Un nœud sans
    ///   ligne `Endpoint:` n'est pas refusé : la règle du pilote suffit.
    /// - `Driver:` vide avec une ligne `Error:` non vide : le moteur ne répond pas (`.unreachable`).
    /// - Tout le reste (autre pilote, pas d'en-tête `Name:`, pilote absent, texte illisible) : `.notLocal`.
    static func parseBuilder(_ data: Data, contextName: String) -> DockerBuilderState {
        guard let text = String(data: data, encoding: .utf8) else { return .notLocal }
        let lines = text.components(separatedBy: .newlines)
        // L'en-tête : jusqu'à la première ligne vide ou jusqu'à « Nodes: ».
        var header: [String: String] = [:]
        var index = 0
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line == "Nodes:" { break }
            if let (key, value) = keyValue(line), header[key] == nil { header[key] = value }
            index += 1
        }
        guard let name = header["Name"], !name.isEmpty, let driver = header["Driver"] else { return .notLocal }
        if driver.isEmpty { return (header["Error"] ?? "").isEmpty ? .notLocal : .unreachable }
        guard driver == "docker" else { return .notLocal }
        // Les points d'accès des nœuds (après l'en-tête).
        for line in lines[index...] {
            guard let (key, value) = keyValue(line.trimmingCharacters(in: .whitespaces)), key == "Endpoint" else { continue }
            guard value == contextName || isLocalSocket(value) else { return .notLocal }
        }
        return .local
    }

    private static func keyValue(_ line: String) -> (String, String)? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let key = line[..<colon].trimmingCharacters(in: .whitespaces)
        let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        return key.isEmpty ? nil : (key, value)
    }

    private static func isLocalSocket(_ endpoint: String) -> Bool {
        endpoint.hasPrefix("unix:///") && endpoint.count > "unix:///".count && !hasControlCharacter(endpoint)
    }

    private static func hasControlCharacter(_ text: String) -> Bool {
        text.unicodeScalars.contains { $0.properties.generalCategory == .control }
    }
}
