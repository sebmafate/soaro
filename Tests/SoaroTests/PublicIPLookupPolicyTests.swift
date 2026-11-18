import Foundation
import Testing
@testable import Soaro

/// SL19 T4 (décision de l'auteur, ADR 0011) : la recherche d'IP publique, qui ne tournait que Réseau ouvert, tourne AUSSI tant que le drapeau
/// est affiché (réglage activé ET bloc réseau dans la barre de menus). Toute la décision est une fonction pure, à temps injecté.
@Suite struct PublicIPLookupPolicyTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    /// Un cas « tout est dû » : le drapeau est affiché, l'onglet Réseau est fermé, une réponse vieille de 400 s, la dernière tentative il y a 400 s.
    private func inputs(
        settingOn: Bool = true, networkItemShown: Bool = true, networkTabOpen: Bool = false, demo: Bool = false,
        state: PublicIPState = .idle, force: Bool = false, fingerprintChanged: Bool = false,
        lastSuccess: Date?? = nil, lastAttempt: Date? = nil, lastFailure: Date? = nil, now: Date? = nil
    ) -> PublicIPLookupPolicy.Inputs {
        let now = now ?? t0
        return PublicIPLookupPolicy.Inputs(
            settingOn: settingOn, networkItemShown: networkItemShown, networkTabOpen: networkTabOpen, demo: demo, state: state, force: force,
            fingerprintChanged: fingerprintChanged,
            lastSuccess: lastSuccess ?? now.addingTimeInterval(-400),
            lastAttempt: lastAttempt ?? now.addingTimeInterval(-400),
            lastFailure: lastFailure, now: now)
    }

    // MARK: Drapeau affiché, onglet Réseau fermé

    @Test func theFlagTriggersALookupWhenDueWithTheNetworkTabClosed() {
        #expect(PublicIPLookupPolicy.shouldLookUp(inputs()))                                  // 400 s > 300 s
    }

    @Test func notDueBeforeFiveMinutes() {
        for age in [0.0, 60, 299] {
            let i = inputs(lastSuccess: .some(t0.addingTimeInterval(-age)), lastAttempt: t0.addingTimeInterval(-age))
            #expect(!PublicIPLookupPolicy.shouldLookUp(i), "âge \(age) s")
        }
        #expect(PublicIPLookupPolicy.shouldLookUp(inputs(lastSuccess: .some(t0.addingTimeInterval(-301)), lastAttempt: t0.addingTimeInterval(-301))))
    }

    @Test func aFirstLookupIsDueWhenNothingIsKnownYet() {
        #expect(PublicIPLookupPolicy.shouldLookUp(inputs(lastSuccess: .some(nil), lastAttempt: .distantPast)))
    }

    @Test func aChangeOfNetworkOrVPNTriggersAtOnceButNotWithinFiveSecondsOfTheLastAttempt() {
        let fresh = t0.addingTimeInterval(-30)
        #expect(PublicIPLookupPolicy.shouldLookUp(inputs(fingerprintChanged: true, lastSuccess: .some(fresh), lastAttempt: t0.addingTimeInterval(-30))))
        #expect(PublicIPLookupPolicy.shouldLookUp(inputs(fingerprintChanged: true, lastSuccess: .some(fresh), lastAttempt: t0.addingTimeInterval(-5))))
        #expect(!PublicIPLookupPolicy.shouldLookUp(inputs(fingerprintChanged: true, lastSuccess: .some(fresh), lastAttempt: t0.addingTimeInterval(-4.9))))
        // Sans changement, une réponse jeune ne justifie rien.
        #expect(!PublicIPLookupPolicy.shouldLookUp(inputs(fingerprintChanged: false, lastSuccess: .some(fresh), lastAttempt: t0.addingTimeInterval(-30))))
    }

    @Test func aFailureIsNotRetriedBeforeSixtySecondsWithTheTabClosed() {
        // Aucune réponse connue : une nouvelle tentative est « due », mais pas avant 60 s après l'échec.
        for since in [1.0, 30, 59.9] {
            let failed = t0.addingTimeInterval(-since)
            let i = inputs(state: .failed("x"), lastSuccess: .some(nil), lastAttempt: failed, lastFailure: failed)
            #expect(!PublicIPLookupPolicy.shouldLookUp(i), "\(since) s après l'échec")
        }
        let failed = t0.addingTimeInterval(-60)
        #expect(PublicIPLookupPolicy.shouldLookUp(inputs(state: .failed("x"), lastSuccess: .some(nil), lastAttempt: failed, lastFailure: failed)))
    }

    @Test func aChangeAfterAFailureStillWaitsSixtySecondsWithTheTabClosed() {
        // Le raccourci de 5 s du changement de réseau ne contourne pas la pause après échec (une recherche qui échoue en boucle serait pire qu'un drapeau en retard).
        let failed = t0.addingTimeInterval(-10)
        let i = inputs(state: .failed("x"), fingerprintChanged: true, lastSuccess: .some(t0.addingTimeInterval(-100)), lastAttempt: failed, lastFailure: failed)
        #expect(!PublicIPLookupPolicy.shouldLookUp(i))
    }

    @Test func aFailureOlderThanTheLastSuccessIsForgotten() {
        // Un échec ancien (déjà suivi d'une réussite) ne bloque plus rien : AppState remet `lastFailure` à nil à la réussite.
        #expect(PublicIPLookupPolicy.shouldLookUp(inputs(lastFailure: nil)))
    }

    // MARK: Jamais

    @Test func neverWhenTheSettingIsOffWhateverElse() {
        for tab in [true, false] { for force in [true, false] { for changed in [true, false] {
            let i = inputs(settingOn: false, networkTabOpen: tab, force: force, fingerprintChanged: changed, lastSuccess: .some(nil), lastAttempt: .distantPast)
            #expect(!PublicIPLookupPolicy.shouldLookUp(i))
        } } }
    }

    @Test func neverInDemoMode() {
        for tab in [true, false] { for force in [true, false] {
            #expect(!PublicIPLookupPolicy.shouldLookUp(inputs(networkTabOpen: tab, demo: true, force: force, lastSuccess: .some(nil), lastAttempt: .distantPast)))
        } }
    }

    @Test func neverForTheFlagWhenTheNetworkItemIsHiddenAndTheTabClosed() {
        #expect(!PublicIPLookupPolicy.shouldLookUp(inputs(networkItemShown: false, networkTabOpen: false, lastSuccess: .some(nil), lastAttempt: .distantPast)))
        #expect(!PublicIPLookupPolicy.shouldLookUp(inputs(networkItemShown: false, networkTabOpen: false, fingerprintChanged: true, lastSuccess: .some(nil), lastAttempt: .distantPast)))
    }

    @Test func neverASecondLookupWhileOneIsRunning() {
        for tab in [true, false] { for force in [true, false] {
            let i = inputs(networkTabOpen: tab, state: .loading, force: force, lastSuccess: .some(nil), lastAttempt: .distantPast)
            #expect(!PublicIPLookupPolicy.shouldLookUp(i))
        } }
    }

    // MARK: Le chemin de l'onglet Réseau est inchangé

    /// L'ancienne règle de `AppState.refreshPublicIP`, recopiée telle quelle : l'onglet Réseau ouvert doit continuer de s'y conformer.
    private func legacyRule(settingOn: Bool, demo: Bool, loading: Bool, force: Bool, hasInfo: Bool, changed: Bool, age: TimeInterval, sinceAttempt: TimeInterval) -> Bool {
        guard !demo, settingOn, !loading else { return false }
        let needsRefresh = force || !hasInfo || changed || age > 300
        let minimumGap: TimeInterval = force ? 0 : (changed ? 5 : 60)
        return needsRefresh && sinceAttempt >= minimumGap
    }

    @Test func theNetworkTabPathBehavesExactlyAsBefore() {
        var checked = 0
        for settingOn in [true, false] { for demo in [true, false] { for loading in [true, false] { for force in [true, false] {
        for hasInfo in [true, false] { for changed in [true, false] {
        for age in [0.0, 100, 299, 300, 301, 4_000] { for sinceAttempt in [0.0, 4, 5, 6, 59, 60, 61, 5_000] {
        for networkItemShown in [true, false] { for failureAgo in [Double?.none, 1, 30, 100] {
            let expected = legacyRule(settingOn: settingOn, demo: demo, loading: loading, force: force, hasInfo: hasInfo, changed: changed, age: age, sinceAttempt: sinceAttempt)
            let i = PublicIPLookupPolicy.Inputs(
                settingOn: settingOn, networkItemShown: networkItemShown, networkTabOpen: true, demo: demo, state: loading ? .loading : .idle, force: force,
                fingerprintChanged: changed, lastSuccess: hasInfo ? t0.addingTimeInterval(-age) : nil, lastAttempt: t0.addingTimeInterval(-sinceAttempt),
                lastFailure: failureAgo.map { t0.addingTimeInterval(-$0) }, now: t0)
            #expect(PublicIPLookupPolicy.shouldLookUp(i) == expected,
                    "setting \(settingOn) demo \(demo) loading \(loading) force \(force) info \(hasInfo) changed \(changed) age \(age) since \(sinceAttempt) item \(networkItemShown) failure \(String(describing: failureAgo))")
            checked += 1
        } } } } } } } } } }
        #expect(checked == 2 * 2 * 2 * 2 * 2 * 2 * 6 * 8 * 2 * 4)
    }

    @Test func aForcedLookupStillWorksWithTheNetworkItemHiddenAndTheTabClosed() {
        // Le bouton « Actualiser » et l'interrupteur des réglages forcent une recherche, comme avant, quel que soit l'onglet.
        #expect(PublicIPLookupPolicy.shouldLookUp(inputs(networkItemShown: false, networkTabOpen: false, force: true, lastSuccess: .some(nil), lastAttempt: .distantPast)))
        #expect(PublicIPLookupPolicy.shouldLookUp(inputs(networkItemShown: false, networkTabOpen: false, force: true, lastSuccess: .some(t0), lastAttempt: t0)))
    }

    // MARK: Empreinte (déplacée telle quelle dans la fonction pure)

    @Test func theFingerprintIsTheSameStringAsBefore() {
        #expect(PublicIPLookupPolicy.fingerprint(localIP: nil, vpn: nil) == "-|none|-|-")
        #expect(PublicIPLookupPolicy.fingerprint(localIP: "192.0.2.7", vpn: nil) == "192.0.2.7|none|-|-")
        #expect(PublicIPLookupPolicy.fingerprint(localIP: "192.0.2.7", vpn: VPNStatus(mode: .full, name: "WireGuard", interface: "utun4")) == "192.0.2.7|vpn|utun4|WireGuard")
        #expect(PublicIPLookupPolicy.fingerprint(localIP: "192.0.2.7", vpn: VPNStatus(mode: .off, name: nil, interface: nil)) == "192.0.2.7|none|-|-")
    }

    @Test func theConstantsAreTheOnesWrittenInTheADR() {
        #expect(PublicIPLookupPolicy.refreshAge == 300)
        #expect(PublicIPLookupPolicy.changeGap == 5)
        #expect(PublicIPLookupPolicy.steadyGap == 60)
        #expect(PublicIPLookupPolicy.failureBackoff == 60)
        #expect(PublicIPLookupPolicy.flagMaxAge == 3_600)
    }
}

/// Le drapeau lui-même : une réponse trop vieille, ou prise sur un autre réseau, ne s'affiche pas.
@Suite struct MenuBarFlagFreshnessTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func info(age: TimeInterval, code: String? = "FR") -> PublicIPInfo {
        PublicIPInfo(ip: "203.0.113.42", countryCode: code, country: "France", city: nil, provider: nil, fetchedAt: now.addingTimeInterval(-age))
    }

    @Test func aKnownCountryIsKeptUpToOneHourThenDropped() {
        for age in [0.0, 600, 3_599, 3_600] {
            #expect(MenuBarFlag.countryCode(lookupEnabled: true, demo: false, info: info(age: age), matchesNetwork: true, now: now) == "FR", "âge \(age) s")
        }
        #expect(MenuBarFlag.countryCode(lookupEnabled: true, demo: false, info: info(age: 3_601), matchesNetwork: true, now: now) == nil)
        #expect(MenuBarFlag.countryCode(lookupEnabled: true, demo: false, info: info(age: 86_400), matchesNetwork: true, now: now) == nil)
    }

    @Test func aReplyTakenOnAnotherNetworkIsNotShown() {
        #expect(MenuBarFlag.countryCode(lookupEnabled: true, demo: false, info: info(age: 10), matchesNetwork: false, now: now) == nil)
    }

    @Test func aReplyDatedInTheFutureIsNotTrustedEither() {
        #expect(MenuBarFlag.countryCode(lookupEnabled: true, demo: false, info: info(age: -7_200), matchesNetwork: true, now: now) == nil)
    }

    @Test func demoIgnoresAgeAndNetwork() {
        #expect(MenuBarFlag.countryCode(lookupEnabled: false, demo: true, info: info(age: 90_000), matchesNetwork: false, now: now) == "FR")
    }

    @Test func theSettingOffStopsShowingTheFlagAtOnce() {
        #expect(MenuBarFlag.countryCode(lookupEnabled: false, demo: false, info: info(age: 1), matchesNetwork: true, now: now) == nil)
    }
}

/// `AppState` : la même fonction décide pour le drapeau (onglet fermé) et pour l'onglet Réseau. Recherche, réglages et heure sont injectés.
@MainActor @Suite(.serialized) struct PublicIPLookupFlowTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private final class Settings: @unchecked Sendable {
        var publicIP = true
        var networkItem = true
    }

    private final class Fetcher: @unchecked Sendable {
        var calls = 0
        var results: [Result<PublicIPInfo, Error>] = []
        var blocking = false
        private let gate = AsyncStream<Void>.makeStream()
        func fetch() async throws -> PublicIPInfo {
            calls += 1
            if blocking { for await _ in gate.stream { break } }
            return try (results.isEmpty ? .failure(PublicIPError.unreachable) : results.removeFirst()).get()
        }
        /// Libère la recherche bloquée (le signal est mis en mémoire : l'ordre n'a pas d'importance).
        func release() { gate.continuation.yield() }
    }

    private func info(_ code: String, at date: Date) -> PublicIPInfo {
        PublicIPInfo(ip: "203.0.113.42", countryCode: code, country: nil, city: nil, provider: nil, fetchedAt: date)
    }

    private func makeState(_ settings: Settings, _ fetcher: Fetcher, demo: Bool = false, itemShown: Bool = true) -> AppState {
        AppState(history: nil, demo: demo,
                 publicIPFetch: { try await fetcher.fetch() },
                 publicIPSetting: { settings.publicIP },
                 networkItemShown: { _ in settings.networkItem && itemShown })
    }

    @Test func theFlagTriggersALookupWithTheNetworkTabClosed() async {
        let settings = Settings(), fetcher = Fetcher()
        fetcher.results = [.success(info("FR", at: t0))]
        let state = makeState(settings, fetcher)
        #expect(state.activeTabs.isEmpty)
        state.refreshPublicIP(now: t0)
        await state.publicIPLookupTask?.value
        #expect(fetcher.calls == 1)
        #expect(state.publicIP?.countryCode == "FR")
        #expect(state.publicIPState == .idle)
    }

    @Test func notDueBeforeFiveMinutesThenDue() async {
        let settings = Settings(), fetcher = Fetcher()
        fetcher.results = [.success(info("FR", at: t0)), .success(info("DE", at: t0.addingTimeInterval(301)))]
        let state = makeState(settings, fetcher)
        state.refreshPublicIP(now: t0); await state.publicIPLookupTask?.value
        state.refreshPublicIP(now: t0.addingTimeInterval(299)); await state.publicIPLookupTask?.value
        #expect(fetcher.calls == 1)
        state.refreshPublicIP(now: t0.addingTimeInterval(301)); await state.publicIPLookupTask?.value
        #expect(fetcher.calls == 2)
        #expect(state.publicIP?.countryCode == "DE")
    }

    @Test func aFailureIsRetriedNoSoonerThanSixtySecondsAndKeepsTheLastKnownReply() async {
        let settings = Settings(), fetcher = Fetcher()
        fetcher.results = [.success(info("FR", at: t0)), .failure(PublicIPError.unreachable), .success(info("DE", at: t0.addingTimeInterval(1_000)))]
        let state = makeState(settings, fetcher)
        state.refreshPublicIP(now: t0); await state.publicIPLookupTask?.value
        state.refreshPublicIP(now: t0.addingTimeInterval(400)); await state.publicIPLookupTask?.value     // échec
        #expect(fetcher.calls == 2)
        if case .failed = state.publicIPState {} else { Issue.record("l'état devrait être « échec »") }
        #expect(state.publicIP?.countryCode == "FR", "la dernière réponse reste connue")
        state.refreshPublicIP(now: t0.addingTimeInterval(430)); await state.publicIPLookupTask?.value
        #expect(fetcher.calls == 2, "30 s après l'échec : pas de nouvelle tentative")
        state.refreshPublicIP(now: t0.addingTimeInterval(461)); await state.publicIPLookupTask?.value
        #expect(fetcher.calls == 3)
        #expect(state.publicIP?.countryCode == "DE")
    }

    @Test func neverWhenTheSettingIsOffTheNetworkItemHiddenOrInDemo() async {
        let settings = Settings(), fetcher = Fetcher()
        settings.publicIP = false
        let off = makeState(settings, fetcher)
        off.refreshPublicIP(now: t0); await off.publicIPLookupTask?.value
        settings.publicIP = true; settings.networkItem = false
        let hidden = makeState(settings, fetcher)
        hidden.refreshPublicIP(now: t0); await hidden.publicIPLookupTask?.value
        settings.networkItem = true
        let demo = makeState(settings, fetcher, demo: true)
        demo.refreshPublicIP(now: t0); await demo.publicIPLookupTask?.value
        #expect(fetcher.calls == 0)
    }

    @Test func noSecondLookupWhileOneIsRunning() async {
        let settings = Settings(), fetcher = Fetcher()
        fetcher.blocking = true
        fetcher.results = [.success(info("FR", at: t0))]
        let state = makeState(settings, fetcher)
        state.refreshPublicIP(now: t0)
        #expect(state.publicIPState == .loading)
        state.refreshPublicIP(force: true, now: t0.addingTimeInterval(1))
        state.refreshPublicIP(now: t0.addingTimeInterval(2))
        await Task.yield()
        fetcher.release()
        await state.publicIPLookupTask?.value
        #expect(fetcher.calls == 1)
    }

    @Test func aReplyArrivingAfterTheSettingWasTurnedOffIsDiscarded() async {
        let settings = Settings(), fetcher = Fetcher()
        fetcher.blocking = true
        fetcher.results = [.success(info("FR", at: t0))]
        let state = makeState(settings, fetcher)
        state.refreshPublicIP(now: t0)
        await Task.yield()
        settings.publicIP = false
        state.forgetPublicIP()
        fetcher.release()
        await state.publicIPLookupTask?.value
        #expect(state.publicIP == nil, "rien n'est gardé, même en mémoire, une fois le réglage coupé")
        #expect(state.publicIPState == .idle)
    }

    @Test func aForcedLookupStillRunsWithTheNetworkItemHidden() async {
        let settings = Settings(), fetcher = Fetcher()
        settings.networkItem = false
        fetcher.results = [.success(info("FR", at: t0))]
        let state = makeState(settings, fetcher)
        state.refreshPublicIP(force: true, now: t0)
        await state.publicIPLookupTask?.value
        #expect(fetcher.calls == 1)
    }

    @Test func theReplyMatchesTheNetworkItWasTakenOn() async {
        let settings = Settings(), fetcher = Fetcher()
        fetcher.results = [.success(info("FR", at: t0))]
        let state = makeState(settings, fetcher)
        #expect(!state.publicIPMatchesNetwork, "rien de connu")
        state.refreshPublicIP(now: t0); await state.publicIPLookupTask?.value
        #expect(state.publicIPMatchesNetwork)
    }
}

/// Garde de source : un seul point d'appel supplémentaire, dans la mesure périodique ; le service et la session ne bougent pas.
@Suite struct PublicIPLookupSourceTests {
    private func read(_ path: String) throws -> String {
        try String(contentsOf: RepositoryRoot.url().appendingPathComponent(path), encoding: .utf8)
    }

    @Test func theTickHooksTheFlagLookupIntoTheExistingPeriodicMeasure() throws {
        let source = try read("Sources/Soaro/AppState.swift")
        let tick = try #require(source.range(of: "private func tick()"))
        let body = String(source[tick.upperBound...].prefix(4_000))
        #expect(body.contains("refreshPublicIPWhileFlagShown(now: now)"))
        #expect(!source.contains("Timer(timeInterval") || source.components(separatedBy: "Timer(timeInterval").count == 2, "aucun minuteur de plus")
        #expect(!source.contains("DispatchQueue") && !source.contains("Thread("))
    }

    @Test func theServiceAndTheSessionAreUnchanged() throws {
        let service = try read("Sources/Soaro/Samplers/PublicIPService.swift")
        #expect(service.contains("URLSessionConfiguration.ephemeral"))
        #expect(service.contains("config.httpCookieStorage = nil"))
        #expect(service.contains("config.httpShouldSetCookies = false"))
        #expect(service.contains("config.requestCachePolicy = .reloadIgnoringLocalCacheData"))
        #expect(service.contains("https://ipwho.is/") && service.contains("https://ipapi.co/json/"))
    }

    @Test func thePolicyFileReferencesNoNetworkAPI() throws {
        let source = try read("Sources/Soaro/Samplers/PublicIPLookupPolicy.swift")
        for word in ["URLSession", "NWConnection", "Data(contentsOf", "Process(", "UserDefaults", "FileManager", "write("] {
            #expect(!source.contains(word), "PublicIPLookupPolicy.swift mentionne \(word)")
        }
    }

    @Test func theOldSettingsSentenceIsGoneEverywhere() throws {
        for path in ["Sources/Soaro/Views/SettingsView.swift", "Sources/Soaro/Resources/Localizable.xcstrings"] {
            let source = try read(path)
            #expect(!source.contains("At most one request every 5 minutes, only while the Network tab is open"), "\(path) garde l'ancienne phrase")
        }
    }

    @Test func theNewSettingsSentenceIsTheCatalogKeyInNineLanguages() throws {
        let key = "Off by default: asks a third-party service (ipwho.is, or ipapi.co as a backup), which then sees your public IP. It asks while the Network tab is open and while the country flag is shown in the menu bar: about every 5 minutes, and again when your network or VPN changes. Nothing is stored. VPN detection is entirely local."
        let view = try read("Sources/Soaro/Views/SettingsView.swift")
        #expect(view.contains("Text(\"\(key)\")"))
        let strings = try DockerStringsTests.catalogStrings()
        let entry = strings[key] as? [String: Any]
        #expect(entry != nil, "clé absente du catalogue")
        let localizations = entry?["localizations"] as? [String: Any] ?? [:]
        for language in TranslationCatalog.requiredTranslations {
            let unit = (localizations[language] as? [String: Any])?["stringUnit"] as? [String: Any]
            let value = unit?["value"] as? String ?? ""
            #expect(!value.isEmpty, "\(language)")
            #expect(unit?["state"] as? String == "translated", "\(language)")
            #expect(TranslationCatalog.placeholderProblems(source: key, translation: value).isEmpty, "\(language)")
            if language != "en" { #expect(value != key, "\(language) : pas traduit") }
        }
    }

    @Test func theADRExistsAndIsInBothIndexes() throws {
        let adr = try read("docs/adr/0011-public-ip-lookup-also-runs-while-its-flag-is-shown.md")
        #expect(adr.contains("accepted"))
        #expect(adr.contains("2026-11-18"))
        #expect(adr.contains("0007"))
        #expect(try read("docs/adr/README.md").contains("0011-public-ip-lookup-also-runs-while-its-flag-is-shown.md"))
        #expect(try read("ARCHITECTURE.md").contains("0011-public-ip-lookup-also-runs-while-its-flag-is-shown.md"))
    }
}
