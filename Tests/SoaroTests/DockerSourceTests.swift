import Foundation
import Testing
@testable import Soaro

/// SL13 T8 (R9, R10, ADR 0010, ADR 0009) : contrôles de source sur les fichiers Docker. Un FILET, pas une preuve : il attrape une commande
/// interdite ou un appel hors du point d'entrée unique ; les tests du lanceur factice prouvent, eux, ce qui est lancé.
@Suite struct DockerSourceTests {
    /// Mots interdits, cherchés comme SOUS-CHAÎNES (aucun ne se trouve légitimement dans le code Docker).
    static let forbiddenSubstrings = [
        "system prune", "--volumes", "desktop-reclaim-space", "volume prune", "volume rm", "network prune", "image prune -a",
        "container prune", "docker run", "docker rm", "docker exec", "docker kill", "docker stop", "docker start", "docker pull",
        "docker rmi", "image rm", "reclaim-space", "--privileged", "removeItem(", "trashItem(", "createFile(", "write(to:", "URLSession", "NWConnection",
        "NSWorkspace", "NSAppleScript", "\"/bin/sh\"", "\"/bin/zsh\"", "\"/bin/bash\"", "Process(",
    ]

    /// Arguments de commande interdits, cherchés comme littéraux ENTIERS (« rm » est dans « confirm » et « rmi » dans « terminé » : jamais en sous-chaîne). « volume » et
    /// « network » sont des mots de l'écran (« Volumes », « Containers… ») mais jamais un argument : seul le littéral exact est interdit.
    static let forbiddenArgumentLiterals = [
        "\"rm\"", "\"rmi\"", "\"run\"", "\"exec\"", "\"kill\"", "\"stop\"", "\"start\"", "\"pull\"", "\"push\"", "\"volume\"", "\"network\"",
        "\"container\"", "\"system\" , \"prune\"", "\"-v\"", "\"--volumes\"", "\"desktop\"", "\"compose\"", "\"commit\"", "\"cp\"",
    ]

    @Test func noDockerFileMentionsAForbiddenCommandOrAnAPIThatWritesOrReachesTheNetwork() throws {
        let files = try DockerStringsTests.dockerSourceFiles()
        #expect(files.count >= 8)
        for file in files {
            for word in Self.forbiddenSubstrings {
                #expect(!file.text.contains(word), "\(file.name) contient « \(word) »")
            }
            for literal in Self.forbiddenArgumentLiterals {
                #expect(!file.text.contains(literal), "\(file.name) contient le littéral \(literal)")
            }
        }
    }

    @Test func theTripwireCatchesWhatItIsMeantTo() {
        let bad = ["docker system prune -af", "docker volume prune -f", "args = [\"rm\", id]", "[\"image\", \"prune\", \"-a\", \"-f\"] // image prune -a -f",
                   "let a = \"--volumes\"", "Docker.app desktop-reclaim-space", "try FileManager.default.removeItem(at: url)"]
        for text in bad {
            let hit = Self.forbiddenSubstrings.contains { text.contains($0) } || Self.forbiddenArgumentLiterals.contains { text.contains($0) }
            #expect(hit, "non attrapé : \(text)")
        }
        // Les mots de l'écran passent.
        for text in ["String(localized: \"Volumes\")", "let confirm = true", "\"Local Volumes\"", "volumes: DockerUsageLine"] {
            let hit = Self.forbiddenSubstrings.contains { text.contains($0) } || Self.forbiddenArgumentLiterals.contains { text.contains($0) }
            #expect(!hit, "attrapé à tort : \(text)")
        }
    }

    @Test func theRunnerIsCalledInExactlyOnePlaceAndNowhereElseInTheDockerFiles() throws {
        var total = 0
        for file in try DockerStringsTests.dockerSourceFiles() {
            let count = file.text.components(separatedBy: "runner.run(").count - 1
            total += count
            if file.name != "DockerScanner.swift" { #expect(count == 0, "\(file.name) appelle le lanceur") }
        }
        #expect(total == 1, "un seul appel au lanceur dans tout le code Docker")
    }

    @Test func noDockerFileBuildsARealRunnerOrAShellOrReadsTheEnvironment() throws {
        for file in try DockerStringsTests.dockerSourceFiles() {
            #expect(!file.text.contains("RealCommandRunner("), "\(file.name)")
            #expect(!file.text.contains("ProcessInfo"), "\(file.name) : ni PATH ni variable d'environnement")
            #expect(!file.text.contains("which "), "\(file.name)")
        }
    }

    @Test func theModelTakesItsRunnerConfirmationFreeSpaceAndWaitWithoutADefault() throws {
        let text = try String(contentsOf: RepositoryRoot.url().appendingPathComponent("Sources/Soaro/Cleanup/DockerModel.swift"), encoding: .utf8)
        let start = try #require(text.range(of: "    init(runner: CommandRunner,"))
        let end = try #require(text.range(of: "notify: @escaping (String) -> Void) {", range: start.upperBound..<text.endIndex))
        let signature = String(text[start.lowerBound..<end.upperBound])
        for parameter in ["runner: CommandRunner,", "locate: @escaping () -> String?,", "freeSpace: @escaping @Sendable () -> UInt64?,",
                          "wait: @escaping @Sendable (TimeInterval) async -> Void,", "confirm: @escaping ConfirmHandler,"] {
            #expect(signature.contains(parameter), "\(parameter) doit rester sans valeur par défaut")
        }
        #expect(!signature.contains("runner: CommandRunner ="))
    }

    @Test func theDemoBranchesPrecedeEveryRunnerLocatorAndFreeSpaceUseInTheModel() throws {
        let text = try String(contentsOf: RepositoryRoot.url().appendingPathComponent("Sources/Soaro/Cleanup/DockerModel.swift"), encoding: .utf8)
        // Dans `scan()` et dans `cleanSelected()`, la branche démo est avant la première utilisation du lanceur ou de la porte.
        let scanStart = try #require(text.range(of: "    func scan() {"))
        let scanDemo = try #require(text.range(of: "if demo {", range: scanStart.upperBound..<text.endIndex))
        let scanRunner = try #require(text.range(of: "DockerScanner.list(", range: scanStart.upperBound..<text.endIndex))
        #expect(scanDemo.lowerBound < scanRunner.lowerBound)
        let cleanStart = try #require(text.range(of: "    func cleanSelected() {"))
        let cleanDemo = try #require(text.range(of: "if demo {", range: cleanStart.upperBound..<text.endIndex))
        let cleanGate = try #require(text.range(of: "gate.begin()", range: cleanStart.upperBound..<text.endIndex))
        let cleanFlow = try #require(text.range(of: "DockerCleanupFlow.run(", range: cleanStart.upperBound..<text.endIndex))
        #expect(cleanDemo.lowerBound < cleanGate.lowerBound && cleanGate.lowerBound < cleanFlow.lowerBound)
        // La branche démo de `cleanSelected()` se termine par `return` avant la porte.
        let demoBody = String(text[cleanDemo.lowerBound..<cleanGate.lowerBound])
        #expect(demoBody.contains("return"))
        for forbidden in ["freeSpace", "locate", "runner", "wait("] {
            #expect(!demoBody.contains(forbidden), "la branche démo de cleanSelected() mentionne \(forbidden)")
        }
    }
}
