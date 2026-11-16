import Foundation

/// Racine du dépôt, retrouvée depuis l'emplacement de ce fichier de test
/// (`Tests/SoaroTests/RepositoryRoot.swift`). Échoue bruyamment si la
/// structure n'est pas celle attendue, pour qu'aucun test de dépôt ne
/// passe « dans le vide ».
enum RepositoryRoot {
    static func url(file: String = #filePath) -> URL {
        URL(fileURLWithPath: file)
            .deletingLastPathComponent()   // SoaroTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // racine
    }

    static func exists(_ relativePath: String, file: String = #filePath) -> Bool {
        FileManager.default.fileExists(atPath: url(file: file).appendingPathComponent(relativePath).path)
    }
}
