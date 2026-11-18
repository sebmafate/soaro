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

    // MARK: Liste blanche (trois familles, quatre commandes)

    @Test func theAllowlistIsExactlyTheFourCommands() {
        #expect(DockerCommand.allCases.map(\.arguments) == [
            ["system", "df", "--format", "{{json .}}"],
            ["images", "-f", "dangling=true", "--format", "{{json .}}"],
            ["builder", "prune", "-a", "-f"],
            ["image", "prune", "-f"],
        ])
        #expect(DockerCommand.allCases.count == 4)
    }

    @Test func onlyThePrunesAreDestructive() {
        #expect(DockerCommand.usage.isDestructive == false)
        #expect(DockerCommand.untaggedImages.isDestructive == false)
        #expect(DockerCommand.pruneBuildCache.isDestructive)
        #expect(DockerCommand.pruneUntaggedImages.isDestructive)
    }

    @Test func isAllowedAcceptsTheFourAndNothingElse() {
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
