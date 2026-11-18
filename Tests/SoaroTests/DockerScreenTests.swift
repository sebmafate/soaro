import Foundation
import Testing
@testable import Soaro

/// SL13 T7 (S4, J6, R10) : la route, la disposition de l'écran (pure) et les contrôles de source de la vue. Aucun écran n'est lancé.
@Suite struct DockerScreenTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOf: RepositoryRoot.url().appendingPathComponent(path), encoding: .utf8)
    }

    // MARK: Route et rangée de la liste

    @Test func theDockerRouteHasItsTitleSubtitleAndIcon() {
        #expect(CleanupRoute.docker.rawValue == "docker")
        #expect(CleanupRoute.docker.title == "Docker")
        #expect(CleanupRoute.docker.subtitle == "Build cache and untagged images")
        #expect(CleanupRoute.docker.systemImage == "square.stack.3d.up")
        #expect(CleanupRoute.docker.id == "docker")
    }

    @Test func toolsListPutsDockerAfterSimulatorsAndBeforeUninstallOnlyWhenShown() {
        #expect(CleanupRoute.toolRoutes(showSimulators: true, showDocker: true)
                == [.largeFiles, .devProjects, .simulators, .docker, .uninstaller, .startup])
        #expect(CleanupRoute.toolRoutes(showSimulators: false, showDocker: true) == [.largeFiles, .devProjects, .docker, .uninstaller, .startup])
        #expect(CleanupRoute.toolRoutes(showSimulators: true, showDocker: false) == [.largeFiles, .devProjects, .simulators, .uninstaller, .startup])
        #expect(CleanupRoute.toolRoutes(showSimulators: false, showDocker: false) == [.largeFiles, .devProjects, .uninstaller, .startup])
        // Les appels existants (sans Docker) ne changent pas.
        #expect(CleanupRoute.toolRoutes(showSimulators: true) == [.largeFiles, .devProjects, .simulators, .uninstaller, .startup])
    }

    @Test func theRowShowsOnlyWhenDockerWasFoundOrInDemoMode() {
        #expect(DockerScreen.showsToolsRow(dockerPath: "/usr/local/bin/docker", demo: false))
        #expect(!DockerScreen.showsToolsRow(dockerPath: nil, demo: false), "docker introuvable (ou détection pas finie) : la rangée n'apparaît pas")
        #expect(DockerScreen.showsToolsRow(dockerPath: nil, demo: true))
    }

    // MARK: Disposition

    @Test func eachPhaseHasOneLayout() {
        #expect(DockerScreen.layout(phase: .notScanned) == .spinner)
        #expect(DockerScreen.layout(phase: .listing) == .spinner)
        #expect(DockerScreen.layout(phase: .hidden) == .hint(warning: false))
        #expect(DockerScreen.layout(phase: .failed(.notRunning)) == .hint(warning: true))
        #expect(DockerScreen.layout(phase: .failed(.notAnswering)) == .hint(warning: true))
        #expect(DockerScreen.layout(phase: .failed(.couldNotRead)) == .hint(warning: true))
        #expect(DockerScreen.layout(phase: .listed) == .list)
    }

    @Test func theActionBarShowsOnlyForAListWithSomethingToClean() {
        #expect(DockerScreen.showsActionBar(layout: .list, hasCleanables: true))
        #expect(!DockerScreen.showsActionBar(layout: .list, hasCleanables: false))
        #expect(!DockerScreen.showsActionBar(layout: .spinner, hasCleanables: true))
        #expect(!DockerScreen.showsActionBar(layout: .hint(warning: true), hasCleanables: true))
    }

    // MARK: Contrôles de source de la vue

    @Test func theViewUsesTheSharedComponentsAndTheSupportingTextToken() throws {
        let text = try source("Sources/Soaro/Views/DockerView.swift")
        for forbidden in [".secondary", ".tertiary", ".quaternary", ".font(.system", "keyboardShortcut", "defaultAction",
                          "withAnimation", ".animation(", ".transition(", "onSubmit", "onKeyPress", "Process", "URLSession",
                          "LocalizedStringKey", "revealInFinder"] {
            #expect(!text.contains(forbidden), "\(forbidden) ne doit pas apparaître dans DockerView.swift")
        }
        #expect(text.contains("supportingText"))
        #expect(text.contains("SelectionRow(") && text.contains("ActionBar("))
        #expect(text.contains("destructive: true") && text.contains("model.cleanSelected()"))
        #expect(text.contains("SectionHeader(") && text.contains("selectAll: selectAll"))
        #expect(text.contains("model.toggleAll()") && text.contains("model.canSelectAll"))
        #expect(text.contains("DockerScreen.layout("))
    }

    @Test func onlyScanAgainIsAButtonSoTheReadOnlyLinesHaveNoControl() throws {
        let text = try source("Sources/Soaro/Views/DockerView.swift")
        #expect(text.components(separatedBy: "Button(").count - 1 == 1, "« Scan again » seulement ; la barre d'action et les cases viennent de composants partagés")
        #expect(!text.contains("Toggle("))
        #expect(!text.contains("Image(systemName: \"circle\")"), "pas de case sur une ligne en lecture seule")
    }

    @Test func theViewStartsTheScanOnAppearAndHasNoDockerStartButton() throws {
        let text = try source("Sources/Soaro/Views/DockerView.swift")
        #expect(text.contains(".onAppear { if model.phase == .notScanned { model.scan() } }"))
        for word in ["Start Docker", "open -a", "launch"] { #expect(!text.contains(word), Comment(rawValue: word)) }
    }

    @Test func theCleanupTabBuildsTheModelWithTheRealRunnerAndWiresBackAndNotifications() throws {
        let text = try source("Sources/Soaro/Views/CleanupTab.swift")
        #expect(text.contains("DockerModel(runner: RealCommandRunner()"))
        #expect(text.contains("confirm: SystemConfirmation.ask"))
        #expect(text.contains("docker.setNotify(notify)"))
        #expect(text.contains("docker.cancel()"))
        #expect(text.contains("case .docker: DockerView(model: docker)"))
        #expect(text.contains("ToolLocator.dockerPath("))
    }
}
