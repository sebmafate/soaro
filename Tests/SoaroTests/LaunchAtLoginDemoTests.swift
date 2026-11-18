import Foundation
import Testing
@testable import Soaro

/// Interrupteur « Open at login » des réglages : en mode démo il ne lit ni ne modifie l'élément de connexion réel.
/// Les actions réelles (`SMAppService`) sont remplacées par des fermetures qui comptent leurs appels ;
/// aucun test n'atteint le vrai service.
private final class Calls: @unchecked Sendable {
    var reads = 0
    var applied: [Bool] = []
    var realState = false
    var failing = false
    struct Refused: Error {}
}

@MainActor
@Suite struct LaunchAtLoginDemoTests {
    private func model(demo: Bool, _ calls: Calls) -> LaunchAtLoginModel {
        LaunchAtLoginModel(
            demo: demo,
            readStatus: { calls.reads += 1; return calls.realState },
            apply: { wanted in
                if calls.failing { throw Calls.Refused() }
                calls.applied.append(wanted)
                calls.realState = wanted
            }
        )
    }

    // MARK: mode démo

    @Test func demoStartsOffWithoutReadingTheRealStatus() {
        let calls = Calls()
        calls.realState = true   // le vrai élément est activé : la démo ne doit pas le montrer
        let login = model(demo: true, calls)

        #expect(login.isEnabled == false)
        #expect(calls.reads == 0)
    }

    @Test func demoTogglingFlipsLocallyAndNeverRegistersNorUnregisters() {
        let calls = Calls()
        let login = model(demo: true, calls)

        #expect(login.set(true))
        #expect(login.isEnabled == true)
        #expect(login.set(false))
        #expect(login.isEnabled == false)
        #expect(login.set(true))
        #expect(login.isEnabled == true)

        #expect(calls.applied.isEmpty)
        #expect(calls.reads == 0)
        #expect(calls.realState == false)
    }

    @Test func demoIgnoresARefusalOfTheRealServiceBecauseItNeverCallsIt() {
        let calls = Calls()
        calls.failing = true
        let login = model(demo: true, calls)

        #expect(login.set(true))
        #expect(login.isEnabled == true)
        #expect(calls.reads == 0)
    }

    // MARK: hors démo : comportement inchangé

    @Test func outsideDemoTheInitialStateIsTheRealStatusReadOnce() {
        let calls = Calls()
        calls.realState = true

        let login = model(demo: false, calls)

        #expect(login.isEnabled == true)
        #expect(calls.reads == 1)
    }

    @Test func outsideDemoEnablingRegistersOnceAndShowsTheRealStatus() {
        let calls = Calls()
        let login = model(demo: false, calls)
        let readsBefore = calls.reads

        #expect(login.set(true))

        #expect(calls.applied == [true])
        #expect(calls.reads == readsBefore + 1)
        #expect(login.isEnabled == true)
    }

    @Test func outsideDemoDisablingUnregistersOnce() {
        let calls = Calls()
        calls.realState = true
        let login = model(demo: false, calls)

        #expect(login.set(false))

        #expect(calls.applied == [false])
        #expect(login.isEnabled == false)
    }

    @Test func outsideDemoARefusalIsReportedAndTheDisplayedStateStaysTheRealOne() {
        let calls = Calls()
        calls.failing = true
        let login = model(demo: false, calls)

        #expect(login.set(true) == false)

        #expect(calls.applied.isEmpty)
        #expect(login.isEnabled == false)
    }

    // MARK: garde sur les sources

    @Test func theSettingsViewNeverTouchesTheLoginItemServiceItself() throws {
        let root = RepositoryRoot.url()
        let view = try String(contentsOf: root.appendingPathComponent("Sources/Soaro/Views/SettingsView.swift"), encoding: .utf8)

        #expect(!view.contains("SMAppService"))
        #expect(view.contains("LaunchAtLoginModel"))
    }
}
