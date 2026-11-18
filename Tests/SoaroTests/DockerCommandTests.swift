import Foundation
import Testing
@testable import Soaro

/// SL13 T1 (R10, ADR 0010, ADR 0009) : où se trouve `docker` (chemins absolus seulement) et la liste blanche des commandes.
@Suite struct DockerCommandTests {
    // MARK: Candidats de `docker`

    @Test func candidatesAreExactlyTheFourAbsolutePathsInOrder() {
        let home = URL(fileURLWithPath: "/Users/test-user")
        #expect(ToolLocator.dockerCandidates(home: home) == [
            "/usr/local/bin/docker",
            "/opt/homebrew/bin/docker",
            "/Applications/Docker.app/Contents/Resources/bin/docker",
            "/Users/test-user/.orbstack/bin/docker",
        ])
    }

    @Test func everyCandidateIsAbsoluteAndCleanAndTheHomeFolderIsNotInterpreted() {
        for home in ["/Users/test-user", "/Users/test-user/", "/Users/with space/é"] {
            let candidates = ToolLocator.dockerCandidates(home: URL(fileURLWithPath: home))
            #expect(candidates.count == 4)
            for path in candidates {
                #expect(path.hasPrefix("/"), "\(path)")
                #expect(!path.contains(".."), "\(path)")
                #expect(!path.contains("//"), "\(path)")
                #expect(!path.contains("$") && !path.contains("~"), "\(path)")
                #expect(URL(fileURLWithPath: path).lastPathComponent == "docker")
            }
        }
    }

    @Test func dockerPathTakesTheFirstCandidateTheLocatorAccepts() {
        let home = URL(fileURLWithPath: "/Users/test-user")
        var asked: [[String]] = []
        let found = ToolLocator.dockerPath(home: home) { candidates in
            asked.append(candidates)
            return candidates[1]
        }
        #expect(found == "/opt/homebrew/bin/docker")
        #expect(asked == [ToolLocator.dockerCandidates(home: home)])
        #expect(ToolLocator.dockerPath(home: home, locate: { _ in nil }) == nil)
    }

    @Test func theRealLocatorFindsAnExecutableAtAnAbsolutePathInASandboxAndNothingElse() throws {
        let box = try Sandbox()
        let tool = try box.file("docker")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        #expect(ToolLocator.firstExecutable(in: [tool.path]) == tool.path)
        // Un chemin relatif (« docker ») n'est jamais cherché dans le PATH.
        #expect(ToolLocator.firstExecutable(in: ["docker"]) == nil)
    }

    // MARK: Liste blanche (quatre familles, six commandes)

    @Test func theAllowlistIsExactlyTheSixCommands() {
        #expect(DockerCommand.allCases.map(\.arguments) == [
            ["system", "df", "--format", "{{json .}}"],
            ["images", "-f", "dangling=true", "--format", "{{json .}}"],
            ["builder", "prune", "-a", "-f"],
            ["image", "prune", "-f"],
            // SL16 : les deux lectures qui disent OÙ le nettoyage tournera.
            ["context", "inspect"],
            ["buildx", "inspect"],
        ])
        #expect(DockerCommand.allCases.count == 6)
    }

    @Test func theTwoMeasuredPrunesAreUnchanged() {
        // SPK-002 a mesuré exactement ces deux commandes : SL16 n'y touche pas.
        #expect(DockerCommand.pruneBuildCache.arguments == ["builder", "prune", "-a", "-f"])
        #expect(DockerCommand.pruneUntaggedImages.arguments == ["image", "prune", "-f"])
    }

    @Test func theEngineReadsAreReadOnlyShortAndBounded() {
        for command in [DockerCommand.currentContext, .currentBuilder] {
            #expect(!command.isDestructive)
            #expect(command.timeLimit == 30)
            #expect(command.outputLimit == 1024 * 1024)
        }
        #expect(DockerCommand.allCases.filter(\.isDestructive) == [.pruneBuildCache, .pruneUntaggedImages])
    }

    /// SL16 : l'environnement donné à `docker` ne contient jamais ce qui désigne un autre moteur ou un autre constructeur.
    @Test func theEnvironmentNamesRemovedFromEveryDockerCallAreTheFiveThatSelectAnEngineOrABuilder() {
        #expect(DockerCommand.removedEnvironment == ["DOCKER_HOST", "DOCKER_CONTEXT", "DOCKER_CERT_PATH", "DOCKER_TLS_VERIFY", "BUILDX_BUILDER"])
    }

    @Test func onlyThePrunesAreDestructive() {
        #expect(DockerCommand.usage.isDestructive == false)
        #expect(DockerCommand.untaggedImages.isDestructive == false)
        #expect(DockerCommand.pruneBuildCache.isDestructive)
        #expect(DockerCommand.pruneUntaggedImages.isDestructive)
    }

    @Test func isAllowedAcceptsTheSixAndNothingElse() {
        for command in DockerCommand.allCases { #expect(DockerCommand.isAllowed(command.arguments)) }
        let refused: [[String]] = [
            [],
            ["volume", "prune", "-f"],
            ["volume", "rm", "x"],
            ["system", "prune", "-f"],
            ["system", "prune", "-a", "-f", "--volumes"],
            ["builder", "prune", "-f"],                       // D1 : exactement `-a -f`
            ["builder", "prune", "-a", "-f", "--volumes"],
            ["image", "prune", "-a", "-f"],                   // D2 : jamais `-a` pour les images
            ["image", "prune", "-f", "--volumes"],
            ["images"],
            ["images", "-f", "dangling=false", "--format", "{{json .}}"],
            ["system", "df", "-v"],
            ["system", "df"],
            ["rm", "x"], ["rmi", "x"], ["run", "x"], ["ps"], ["network", "prune", "-f"],
            ["run", "--privileged", "docker/desktop-reclaim-space"],
            // SL16 : lire est permis dans EXACTEMENT ces deux formes ; changer le contexte ou le constructeur ne l'est jamais.
            ["context"], ["context", "ls"], ["context", "show"], ["context", "inspect", "desktop-linux"], ["context", "inspect", "default"],
            ["context", "use", "desktop-linux"], ["context", "use", "default"], ["context", "create", "x"], ["context", "rm", "x"],
            ["context", "update", "x"], ["context", "export", "x"], ["context", "import", "x"],
            ["buildx"], ["buildx", "ls"], ["buildx", "ls", "--format", "json"], ["buildx", "inspect", "--bootstrap"], ["buildx", "inspect", "other"],
            ["buildx", "use", "default"], ["buildx", "create"], ["buildx", "create", "--use"], ["buildx", "rm", "x"], ["buildx", "prune"],
            ["buildx", "prune", "-a", "-f"], ["buildx", "build", "."], ["buildx", "stop"], ["buildx", "du"],
            ["--context", "x", "system", "df", "--format", "{{json .}}"], ["-H", "tcp://x", "system", "df", "--format", "{{json .}}"],
            ["--host", "ssh://x", "builder", "prune", "-a", "-f"], ["--builder", "x", "builder", "prune", "-a", "-f"],
        ]
        for arguments in refused { #expect(!DockerCommand.isAllowed(arguments), "\(arguments)") }
    }

    @Test func listingsAreShortAndTheirOutputIsBoundedAndPrunesGetRoomToFinish() {
        #expect(DockerCommand.usage.timeLimit == 30)
        #expect(DockerCommand.untaggedImages.timeLimit == 30)
        #expect(DockerCommand.pruneBuildCache.timeLimit == 300)      // SPK-002 : 43 s pour 22 Go
        #expect(DockerCommand.pruneUntaggedImages.timeLimit == 300)
        #expect(DockerCommand.usage.outputLimit == 1024 * 1024)
        #expect(DockerCommand.untaggedImages.outputLimit == 1024 * 1024)
        #expect(DockerCommand.pruneBuildCache.outputLimit == 4 * 1024 * 1024)
        #expect(DockerCommand.pruneUntaggedImages.outputLimit == 4 * 1024 * 1024)
    }
}
