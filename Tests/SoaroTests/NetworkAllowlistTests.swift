import Foundation
import Testing
@testable import Soaro

/// Garde-fou de la promesse de confidentialité (R9) : aucune donnée ne quitte
/// le Mac par défaut, et le seul code autorisé à ouvrir une connexion réseau
/// applicative est `PublicIPService` (désactivé par défaut).
///
/// Règle : un fichier `.swift` de `Sources/Soaro/` est en infraction si son
/// chemin relatif n'est pas exactement `Sources/Soaro/Samplers/PublicIPService.swift`
/// ET si son texte contient la sous-chaîne `URLSession` ou `NWConnection`.
///
/// Pourquoi une simple recherche de sous-chaîne, sans retirer commentaires ni
/// chaînes : c'est simple, impossible à contourner par accident, et elle
/// attrape aussi `URLSessionConfiguration`, `URLSessionDataTask`, etc.
/// Contrepartie assumée : un commentaire qui cite ces noms hors de la liste
/// blanche fait échouer le test (reformuler le commentaire, ou passer par
/// `PublicIPService`).
///
/// Hors périmètre de cette garde (limites connues) : `Data(contentsOf:)`,
/// `Process`/`curl`, `NWPathMonitor`, Sparkle (mises à jour) et le ping
/// optionnel `/sbin/ping` de `NetworkSampler.ping`.
enum NetworkAllowlist {
    static let allowedPath = "Sources/Soaro/Samplers/PublicIPService.swift"
    static let forbiddenNames = ["URLSession", "NWConnection"]

    struct Violation: Equatable {
        let path: String
        let name: String
    }

    /// Fonction pure : (chemin relatif, contenu) → infractions.
    static func violations(in files: [(path: String, contents: String)]) -> [Violation] {
        var result: [Violation] = []
        for file in files where file.path != allowedPath {
            for name in forbiddenNames where file.contents.contains(name) {
                result.append(Violation(path: file.path, name: name))
            }
        }
        return result
    }

    /// Tous les `.swift` sous `Sources/Soaro/`, chemins relatifs à la racine du dépôt.
    static func sourceFiles(root: URL) throws -> [(path: String, contents: String)] {
        let sources = root.appendingPathComponent("Sources/Soaro")
        guard let enumerator = FileManager.default.enumerator(
            at: sources, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        var files: [(path: String, contents: String)] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let relative = String(url.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count + 1))
            files.append((relative, try String(contentsOf: url, encoding: .utf8)))
        }
        return files.sorted { $0.path < $1.path }
    }
}

@Suite struct NetworkAllowlistTests {
    @Test func realSourceTreeHasNoNetworkAPIOutsideAllowlist() throws {
        let files = try NetworkAllowlist.sourceFiles(root: RepositoryRoot.url())
        let found = NetworkAllowlist.violations(in: files)
        let list = found.map { "  \($0.path) mentionne \($0.name)" }.joined(separator: "\n")
        #expect(found.isEmpty, """
            R9: du code réseau applicatif hors de \(NetworkAllowlist.allowedPath) :
            \(list)
            Reformuler le commentaire, ou faire passer l'appel par PublicIPService.
            """)
    }

    @Test func scanIsNotVacuous() throws {
        let files = try NetworkAllowlist.sourceFiles(root: RepositoryRoot.url())
        #expect(files.count > 0)
        let service = files.first { $0.path == NetworkAllowlist.allowedPath }
        #expect(service != nil, "PublicIPService.swift introuvable : la liste blanche est périmée ou la racine est fausse")
        #expect(service?.contents.contains("URLSession") == true)
    }

    @Test func flagsNetworkAPIsOutsideAllowlist() {
        let samples = [
            "let s = URLSession.shared",
            "let c = URLSessionConfiguration.ephemeral",
            "let n = NWConnection(host: h, port: p, using: .tcp)",
            "// ceci utilise URLSession pour récupérer l'IP",
        ]
        for text in samples {
            let found = NetworkAllowlist.violations(in: [("Sources/Soaro/Other.swift", text)])
            #expect(found.count == 1 && found[0].path == "Sources/Soaro/Other.swift", "non détecté : \(text)")
        }
    }

    @Test func ignoresAllowedAndUnrelatedCode() {
        let files: [(path: String, contents: String)] = [
            ("Sources/Soaro/Updater.swift", "import Sparkle\nlet u = SPUStandardUpdaterController()"),
            ("Sources/Soaro/Samplers/Path.swift", "let m = NWPathMonitor()"),
            ("Sources/Soaro/Unrelated.swift", "let x = 1"),
            (NetworkAllowlist.allowedPath, "let s = URLSession(configuration: .ephemeral)"),
        ]
        #expect(NetworkAllowlist.violations(in: files).isEmpty)
    }
}
