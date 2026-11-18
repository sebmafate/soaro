import Foundation
import Testing
@testable import Soaro

/// SL13 T8 et SL16 T5 (R9, R10, ADR 0010, ADR 0009) : contrôles de source sur les fichiers Docker. Un FILET, pas une preuve : il attrape une commande
/// interdite ou un appel hors du point d'entrée unique ; les tests du lanceur factice prouvent, eux, ce qui est lancé.
@Suite struct DockerSourceTests {
    /// Mots interdits, cherchés comme SOUS-CHAÎNES (aucun ne se trouve légitimement dans le code Docker).
    static let forbiddenSubstrings = [
        "system prune", "--volumes", "desktop-reclaim-space", "volume prune", "volume rm", "network prune", "image prune -a",
        "container prune", "docker run", "docker rm", "docker exec", "docker kill", "docker stop", "docker start", "docker pull",
        "docker rmi", "image rm", "reclaim-space", "--privileged", "removeItem(", "trashItem(", "createFile(", "write(to:", "URLSession", "NWConnection",
        "NSWorkspace", "NSAppleScript", "\"/bin/sh\"", "\"/bin/zsh\"", "\"/bin/bash\"", "Process(",
        // SL16 : jamais changer le contexte ou le constructeur, ni démarrer quoi que ce soit ; lire est permis dans deux formes exactes (voir `contextAndBuildxMisuse`).
        "context use", "context create", "context rm", "context update", "context import", "buildx use", "buildx create", "buildx rm", "buildx prune",
        "buildx stop", "buildx ls", "--bootstrap", "--context", "--builder", "--host",
    ]

    /// Arguments de commande interdits, cherchés comme littéraux ENTIERS (« rm » est dans « confirm » et « rmi » dans « terminé » : jamais en sous-chaîne). « volume » et
    /// « network » sont des mots de l'écran (« Volumes », « Containers… ») mais jamais un argument : seul le littéral exact est interdit.
    static let forbiddenArgumentLiterals = [
        "\"rm\"", "\"rmi\"", "\"run\"", "\"exec\"", "\"kill\"", "\"stop\"", "\"start\"", "\"pull\"", "\"push\"", "\"volume\"", "\"network\"",
        "\"container\"", "\"system\" , \"prune\"", "\"-v\"", "\"--volumes\"", "\"desktop\"", "\"compose\"", "\"commit\"", "\"cp\"",
        // SL16 : les verbes qui changent le contexte ou le constructeur, et les options qui désignent un autre moteur.
        "\"use\"", "\"create\"", "\"update\"", "\"import\"", "\"export\"", "\"ls\"", "\"show\"", "\"--bootstrap\"", "\"--context\"", "\"--builder\"",
        "\"--host\"", "\"-H\"", "\"-c\"",
    ]

    /// SL16 : « context » et « buildx » ne peuvent paraître, comme littéraux d'argument, que dans les deux formes permises : `["context", "inspect"]` et
    /// `["buildx", "inspect"]`, c'est-à-dire suivis tout de suite de `, "inspect"]`. Rend les occurrences en défaut.
    static func contextAndBuildxMisuse(in text: String) -> [String] {
        var bad: [String] = []
        for word in ["\"context\"", "\"buildx\""] {
            var search = text.startIndex..<text.endIndex
            while let hit = text.range(of: word, range: search) {
                let rest = text[hit.upperBound...]
                if !rest.hasPrefix(", \"inspect\"]") { bad.append(word + String(rest.prefix(24))) }
                search = hit.upperBound..<text.endIndex
            }
        }
        return bad
    }

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

    @Test func contextAndBuildxAppearOnlyInTheTwoReadOnlyForms() throws {
        var seen = 0
        for file in try DockerStringsTests.dockerSourceFiles() {
            #expect(Self.contextAndBuildxMisuse(in: file.text).isEmpty, "\(file.name) : \(Self.contextAndBuildxMisuse(in: file.text))")
            if file.text.contains("\"context\"") || file.text.contains("\"buildx\"") {
                #expect(file.name == "DockerCommands.swift", "\(file.name) construit une commande hors de la liste blanche")
                seen += 1
            }
        }
        #expect(seen == 1)
        let commands = try #require(try DockerStringsTests.dockerSourceFiles().first { $0.name == "DockerCommands.swift" }).text
        #expect(commands.contains("[\"context\", \"inspect\"]") && commands.contains("[\"buildx\", \"inspect\"]"))
    }

    @Test func theTripwireAlsoCatchesAChangeOfContextOrBuilder() {
        for bad in ["[\"context\", \"use\", name]", "[\"buildx\", \"use\", name]", "args = [\"buildx\", \"create\"]", "[\"buildx\", \"rm\", n]",
                    "[\"context\", \"ls\"]", "[\"buildx\", \"inspect\", \"--bootstrap\"]"] {
            #expect(!Self.contextAndBuildxMisuse(in: bad).isEmpty, "non attrapé : \(bad)")
        }
        #expect(Self.contextAndBuildxMisuse(in: "case .currentContext: [\"context\", \"inspect\"]\ncase .currentBuilder: [\"buildx\", \"inspect\"]").isEmpty)
        for text in ["docker context use x", "docker buildx use x", "docker buildx create --use", "docker buildx rm x", "[\"--context\", c]", "\"use\"", "\"create\""] {
            let hit = Self.forbiddenSubstrings.contains { text.contains($0) } || Self.forbiddenArgumentLiterals.contains { text.contains($0) }
            #expect(hit, "non attrapé : \(text)")
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

    /// SL16 : l'unique appel au lanceur retire toujours les variables d'environnement ; le moteur est lu AVANT le listage et AVANT chaque nettoyage.
    @Test func theOnlyRunnerCallRemovesTheEnvironmentAndTheEngineIsCheckedBeforeListingAndBeforePruning() throws {
        let text = try #require(try DockerStringsTests.dockerSourceFiles().first { $0.name == "DockerScanner.swift" }).text
        let call = try #require(text.range(of: "runner.run("))
        let callText = String(text[call.lowerBound...].prefix(260))
        #expect(callText.contains("removingEnvironment: DockerCommand.removedEnvironment"))
        let list = try #require(text.range(of: "static func list("))
        let check = try #require(text.range(of: "checkEngine(runner: runner", range: list.upperBound..<text.endIndex))
        let usage = try #require(text.range(of: "readOutput(of: .usage", range: list.upperBound..<text.endIndex))
        #expect(check.lowerBound < usage.lowerBound)
        let prune = try #require(text.range(of: "static func prune("))
        let pruneCheck = try #require(text.range(of: "checkEngine(runner: runner", range: prune.upperBound..<text.endIndex))
        let pruneRun = try #require(text.range(of: "execute(prune.command", range: prune.upperBound..<text.endIndex))
        #expect(pruneCheck.lowerBound < pruneRun.lowerBound)
        #expect(text.contains("expectedEngine: DockerEngine)"), "le moteur confirmé est un paramètre sans valeur par défaut")
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
