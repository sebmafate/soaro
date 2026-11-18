import Foundation
import Testing
@testable import Soaro

/// SL25 (ADR 0012, étend 0011) : l'IP publique peut changer dans plus de situations que celles que le drapeau voyait ; on les détecte
/// (signaux locaux, événements, réveil) et on ne cherche qu'alors, plus une seule recherche de confirmation. Aucun trafic de plus à l'arrêt.

// MARK: - La politique pure : confirmation, stabilisation, motif

@Suite struct PublicIPConfirmationPolicyTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    /// Réponse fraîche (rien n'est dû par l'âge), dernière tentative il y a `sinceAttempt` s : seul le champ testé peut déclencher.
    private func inputs(
        settingOn: Bool = true, networkItemShown: Bool = true, networkTabOpen: Bool = false, demo: Bool = false,
        state: PublicIPState = .idle, force: Bool = false, fingerprintChanged: Bool = false,
        sinceAttempt: TimeInterval = 10, confirmationAge: TimeInterval? = 10, lastFailureAgo: TimeInterval? = nil
    ) -> PublicIPLookupPolicy.Inputs {
        PublicIPLookupPolicy.Inputs(
            settingOn: settingOn, networkItemShown: networkItemShown, networkTabOpen: networkTabOpen, demo: demo, state: state, force: force,
            fingerprintChanged: fingerprintChanged, lastSuccess: t0.addingTimeInterval(-sinceAttempt),
            lastAttempt: t0.addingTimeInterval(-sinceAttempt), lastFailure: lastFailureAgo.map { t0.addingTimeInterval(-$0) },
            lastChangeTriggeredLookup: confirmationAge.map { t0.addingTimeInterval(-$0) }, now: t0)
    }

    @Test func theConstantsAreTheOnesOfTheADR() {
        #expect(PublicIPLookupPolicy.settleDelay == 10)
        #expect(PublicIPLookupPolicy.quietPeriod == 3)
        // Les règles d'origine ne bougent pas.
        #expect(PublicIPLookupPolicy.refreshAge == 300)
        #expect(PublicIPLookupPolicy.changeGap == 5)
        #expect(PublicIPLookupPolicy.steadyGap == 60)
        #expect(PublicIPLookupPolicy.failureBackoff == 60)
        #expect(PublicIPLookupPolicy.flagMaxAge == 3_600)
    }

    @Test func aConfirmationIsDueOnceTheSettleDelayHasPassed() {
        #expect(!PublicIPLookupPolicy.shouldLookUp(inputs(sinceAttempt: 9.9, confirmationAge: 9.9)))
        #expect(PublicIPLookupPolicy.shouldLookUp(inputs(sinceAttempt: 10, confirmationAge: 10)))
        #expect(PublicIPLookupPolicy.shouldLookUp(inputs(sinceAttempt: 30, confirmationAge: 30)))
    }

    @Test func withoutAChangeTriggeredLookupNothingIsDueBeforeFiveMinutes() {
        for age in [0.0, 10, 30, 299] {
            #expect(!PublicIPLookupPolicy.shouldLookUp(inputs(sinceAttempt: age, confirmationAge: nil)), "âge \(age) s")
        }
    }

    @Test func theConfirmationIsOnlyEverOneRequestBecauseTheMarkIsConsumed() {
        // AppState efface la marque au départ de la confirmation : sans marque, plus rien n'est dû (voir aussi les tests d'AppState).
        #expect(PublicIPLookupPolicy.shouldLookUp(inputs(confirmationAge: 12)))
        #expect(!PublicIPLookupPolicy.shouldLookUp(inputs(confirmationAge: nil)))
    }

    @Test func neverConfirmedInDemoWithTheSettingOffOrWithNothingToShowItFor() {
        #expect(!PublicIPLookupPolicy.shouldLookUp(inputs(demo: true)))
        #expect(!PublicIPLookupPolicy.shouldLookUp(inputs(settingOn: false)))
        #expect(!PublicIPLookupPolicy.shouldLookUp(inputs(networkItemShown: false, networkTabOpen: false)))
        #expect(!PublicIPLookupPolicy.shouldLookUp(inputs(state: .loading)))
    }

    @Test func theConfirmationRespectsTheFailureBackoffWithTheFlagAndWithTheTab() {
        for tab in [false, true] {
            #expect(!PublicIPLookupPolicy.shouldLookUp(inputs(networkItemShown: !tab, networkTabOpen: tab, lastFailureAgo: 30)), "onglet \(tab)")
            #expect(!PublicIPLookupPolicy.shouldLookUp(inputs(networkItemShown: !tab, networkTabOpen: tab, lastFailureAgo: 59.9)), "onglet \(tab)")
            #expect(PublicIPLookupPolicy.shouldLookUp(inputs(networkItemShown: !tab, networkTabOpen: tab, lastFailureAgo: 60)), "onglet \(tab)")
        }
    }

    @Test func aConfirmationDoesNotBypassTheChangeGapOfFiveSeconds() {
        // La dernière tentative date de 3 s seulement (cas artificiel : la marque est plus ancienne que la tentative).
        #expect(!PublicIPLookupPolicy.shouldLookUp(inputs(sinceAttempt: 3, confirmationAge: 12)))
    }

    @Test func theConfirmationInputOnlyEverAddsLookupsNeverRemovesOne() {
        // Preuve que l'onglet Réseau garde ses règles : la nouvelle entrée, absente, redonne exactement l'ancien résultat, et présente,
        // elle ne retire jamais une recherche que l'ancienne règle accordait.
        var checked = 0
        for settingOn in [true, false] { for demo in [true, false] { for loading in [true, false] { for force in [true, false] {
        for changed in [true, false] { for tab in [true, false] { for item in [true, false] {
        for age in [0.0, 100, 301, 4_000] { for sinceAttempt in [0.0, 4, 5, 6, 59, 60, 61] { for failureAgo in [Double?.none, 1, 30, 100] {
        for confirmation in [Double?.none, 3, 10, 50] {
            func make(_ c: Double?) -> PublicIPLookupPolicy.Inputs {
                PublicIPLookupPolicy.Inputs(
                    settingOn: settingOn, networkItemShown: item, networkTabOpen: tab, demo: demo, state: loading ? .loading : .idle, force: force,
                    fingerprintChanged: changed, lastSuccess: t0.addingTimeInterval(-age), lastAttempt: t0.addingTimeInterval(-sinceAttempt),
                    lastFailure: failureAgo.map { t0.addingTimeInterval(-$0) }, lastChangeTriggeredLookup: c.map { t0.addingTimeInterval(-$0) }, now: t0)
            }
            let without = PublicIPLookupPolicy.shouldLookUp(make(nil))
            let with = PublicIPLookupPolicy.shouldLookUp(make(confirmation))
            if confirmation == nil { #expect(with == without) }
            if without { #expect(with, "une recherche accordée a été retirée par la marque de confirmation") }
            checked += 1
        } } } } } } } } } } }
        #expect(checked == 2 * 2 * 2 * 2 * 2 * 2 * 2 * 4 * 7 * 4 * 4)
    }

    // MARK: Quand surveiller

    @Test func theMonitorIsWantedExactlyWhenALookupCouldBeAskedFor() {
        for setting in [true, false] { for demo in [true, false] { for item in [true, false] { for tab in [true, false] {
            let wanted = PublicIPLookupPolicy.monitorWanted(settingOn: setting, demo: demo, networkItemShown: item, networkTabOpen: tab)
            // Tout est dû, rien n'est forcé : la politique dit oui exactement quand la surveillance a un sens.
            let due = PublicIPLookupPolicy.Inputs(
                settingOn: setting, networkItemShown: item, networkTabOpen: tab, demo: demo, state: .idle, force: false, fingerprintChanged: true,
                lastSuccess: nil, lastAttempt: .distantPast, lastFailure: nil, now: t0)
            #expect(wanted == PublicIPLookupPolicy.shouldLookUp(due), "réglage \(setting) démo \(demo) bloc \(item) onglet \(tab)")
        } } } }
    }


    @Test func theFirstLookupWaitsForAPendingDetectionOnlyOnTheFlagPathAndOnlyUpToTheCap() {
        func w(_ had: Bool, _ pending: Bool, _ tab: Bool, _ force: Bool, _ since: Date?, _ now: Date) -> Bool {
            PublicIPLookupPolicy.mustWaitForFirstFingerprint(hadBaseline: had, vpnDetectionPending: pending, tabOpen: tab, force: force, waitingSince: since, now: now)
        }
        #expect(PublicIPLookupPolicy.firstLookupWaitCap == 10)
        #expect(w(false, true, false, false, nil, t0), "la première attente commence")
        #expect(w(false, true, false, false, t0.addingTimeInterval(-9.9), t0))
        #expect(!w(false, true, false, false, t0.addingTimeInterval(-10), t0), "le plafond est atteint : on cherche")
        #expect(!w(true, true, false, false, nil, t0), "une base existe déjà")
        #expect(!w(false, false, false, false, nil, t0), "aucune détection en cours : rien à attendre")
        #expect(!w(false, true, true, false, nil, t0), "l'onglet Réseau cherche tout de suite")
        #expect(!w(false, true, false, true, nil, t0), "un appel forcé aussi")
    }

    // MARK: Changement détecté

    @Test func aChangeIsDetectedOnceTheFingerprintHasSettledOrAtOnceForTheTabAndTheFirstLookup() {
        let f = PublicIPLookupPolicy.fingerprintChanged
        #expect(!f("a", "a", true, false, false), "rien n'a changé")
        #expect(!f("b", "a", false, false, false), "pas encore stable : on attend la fin de la rafale")
        #expect(f("b", "a", true, false, false))
        #expect(f("b", "a", false, false, true), "l'onglet Réseau garde sa règle : tout de suite")
        #expect(f("b", "", false, false, false), "première recherche : rien à stabiliser")
        #expect(f("a", "a", false, true, false), "un réveil force")
        #expect(f("a", "a", true, true, true))
    }

    @Test func aFingerprintMustStayTheSameForTheQuietPeriodToBeSettled() {
        var settler = FingerprintSettler()
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        let r1 = settler.observe("a", now: t); #expect(!r1)                         // première observation
        let r2 = settler.observe("a", now: t.addingTimeInterval(3)); #expect(r2)
        let r3 = settler.observe("b", now: t.addingTimeInterval(4)); #expect(!r3)   // change : on repart
        let r4 = settler.observe("b", now: t.addingTimeInterval(6.9)); #expect(!r4)
        let r5 = settler.observe("b", now: t.addingTimeInterval(7)); #expect(r5)
        let r6 = settler.observe("a", now: t.addingTimeInterval(7.5)); #expect(!r6) // une rafale qui revient en arrière repart aussi
        let r7 = settler.observe("c", now: t.addingTimeInterval(9)); #expect(!r7)
        let r8 = settler.observe("c", now: t.addingTimeInterval(11.9)); #expect(!r8)
        let r9 = settler.observe("c", now: t.addingTimeInterval(12)); #expect(r9)
    }

    @Test func theMonitorsQuietPeriodCountsAsSettled() {
        var settler = FingerprintSettler()
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        _ = settler.observe("a", now: t)
        _ = settler.observe("b", now: t.addingTimeInterval(1))
        settler.accept("b")
        let r10 = settler.observe("b", now: t.addingTimeInterval(1.1)); #expect(r10)
        let r11 = settler.observe("c", now: t.addingTimeInterval(1.2)); #expect(!r11, "accepter ne vaut que pour l'empreinte acceptée")
    }

    // MARK: Motif (journal)

    @Test func theReasonNamesWhyALookupRuns() {
        func reason(force: Bool = false, changed: Bool = false, wake: Bool = false, had: Bool = true, noReply: Bool = false, confirmation: Bool = false) -> PublicIPLookupPolicy.LookupReason {
            let i = PublicIPLookupPolicy.Inputs(
                settingOn: true, networkItemShown: true, networkTabOpen: false, demo: false, state: .idle, force: force, fingerprintChanged: changed,
                lastSuccess: noReply ? nil : t0.addingTimeInterval(-(confirmation ? 12 : 400)), lastAttempt: t0.addingTimeInterval(-400), lastFailure: nil,
                lastChangeTriggeredLookup: confirmation ? t0.addingTimeInterval(-12) : nil, now: t0)
            return PublicIPLookupPolicy.reason(i, wake: wake, hadFingerprint: had)
        }
        #expect(reason(force: true, changed: true) == .forced)
        #expect(reason(changed: true, wake: true) == .wake)
        #expect(reason(wake: true) == .wake)
        #expect(reason(changed: true) == .networkChange)
        #expect(reason(changed: true, had: false) == .first)
        #expect(reason(noReply: true) == .first)
        #expect(reason(confirmation: true) == .confirmation)
        #expect(reason(changed: true, confirmation: true) == .networkChange)
        #expect(reason() == .periodic)
        #expect(PublicIPLookupPolicy.LookupReason.wake.isChangeTriggered)
        #expect(PublicIPLookupPolicy.LookupReason.networkChange.isChangeTriggered)
        for other in [PublicIPLookupPolicy.LookupReason.forced, .first, .periodic, .confirmation] { #expect(!other.isChangeTriggered, "\(other)") }
    }
}

// MARK: - Le moniteur : une rafale d'événements, un seul déclenchement

@MainActor final class FakeNetworkSource: NetworkEventSource {
    var startCount = 0
    var stopCount = 0
    var canStart = true
    private(set) var handler: (@MainActor (NetworkChangeReason) -> Void)?
    var isActive: Bool { handler != nil }
    func start(_ onEvent: @escaping @MainActor (NetworkChangeReason) -> Void) -> Bool {
        startCount += 1
        guard canStart else { return false }
        handler = onEvent
        return true
    }
    func stop() { stopCount += 1; handler = nil }
    func emit(_ reason: NetworkChangeReason = .configuration) { handler?(reason) }
}

@MainActor final class FakeScheduler: DebounceScheduler {
    final class Job { let delay: TimeInterval; let work: @MainActor () -> Void; var cancelled = false; var fired = false
        init(_ d: TimeInterval, _ w: @escaping @MainActor () -> Void) { delay = d; work = w } }
    private(set) var jobs: [Job] = []
    var active: [Job] { jobs.filter { !$0.cancelled && !$0.fired } }
    func schedule(after delay: TimeInterval, _ work: @escaping @MainActor () -> Void) -> () -> Void {
        let job = Job(delay, work)
        jobs.append(job)
        return { job.cancelled = true }
    }
    /// Laisse passer le délai : exécute le travail encore actif (au plus un).
    func fire() { for job in active { job.fired = true; job.work() } }
}

@MainActor @Suite struct NetworkChangeMonitorTests {
    private func make(_ source: FakeNetworkSource, _ scheduler: FakeScheduler, settled: @escaping @MainActor (NetworkChangeReason) -> Void) -> NetworkChangeMonitor {
        NetworkChangeMonitor(source: source, scheduler: scheduler, onSettled: settled)
    }

    @Test func aBurstOfEventsGivesOneTriggerAfterTheQuietPeriod() {
        let source = FakeNetworkSource(), scheduler = FakeScheduler()
        var triggers: [NetworkChangeReason] = []
        let monitor = make(source, scheduler) { triggers.append($0) }
        #expect(monitor.start())
        for _ in 0..<7 { source.emit() }
        #expect(triggers.isEmpty, "rien tant que la rafale dure")
        #expect(scheduler.active.count == 1, "un seul minuteur actif : chaque événement repart de zéro")
        #expect(scheduler.jobs.count == 7)
        #expect(scheduler.active[0].delay == 3)
        scheduler.fire()
        #expect(triggers == [.configuration])
        scheduler.fire()
        #expect(triggers == [.configuration], "pas de second déclenchement")
    }

    @Test func eachEventRestartsTheQuietPeriod() {
        let source = FakeNetworkSource(), scheduler = FakeScheduler()
        var triggers = 0
        let monitor = make(source, scheduler) { _ in triggers += 1 }
        monitor.start()
        source.emit(); let first = scheduler.active[0]
        source.emit()
        #expect(first.cancelled, "le premier minuteur est annulé par l'événement suivant")
        #expect(triggers == 0)
        scheduler.fire()
        #expect(triggers == 1)
    }

    @Test func twoSeparateBurstsGiveTwoTriggers() {
        let source = FakeNetworkSource(), scheduler = FakeScheduler()
        var triggers = 0
        let monitor = make(source, scheduler) { _ in triggers += 1 }
        monitor.start()
        source.emit(); source.emit(); scheduler.fire()
        source.emit(); scheduler.fire()
        #expect(triggers == 2)
    }

    @Test func aWakeInTheBurstIsReportedAsAWakeWhateverTheOrder() {
        for order in [[NetworkChangeReason.wake, .configuration], [.configuration, .wake], [.configuration, .wake, .configuration]] {
            let source = FakeNetworkSource(), scheduler = FakeScheduler()
            var triggers: [NetworkChangeReason] = []
            let monitor = make(source, scheduler) { triggers.append($0) }
            monitor.start()
            for reason in order { source.emit(reason) }
            scheduler.fire()
            #expect(triggers == [.wake], "\(order)")
        }
    }

    @Test func aWakeAloneIsDebouncedLikeTheOthers() {
        let source = FakeNetworkSource(), scheduler = FakeScheduler()
        var triggers: [NetworkChangeReason] = []
        let monitor = make(source, scheduler) { triggers.append($0) }
        monitor.start()
        source.emit(.wake)
        #expect(triggers.isEmpty)
        #expect(scheduler.active.count == 1)
        scheduler.fire()
        #expect(triggers == [.wake])
    }

    @Test func stoppingCancelsThePendingTriggerAndIgnoresLaterEvents() {
        let source = FakeNetworkSource(), scheduler = FakeScheduler()
        var triggers = 0
        let monitor = make(source, scheduler) { _ in triggers += 1 }
        monitor.start()
        source.emit()
        monitor.stop()
        #expect(scheduler.active.isEmpty, "le minuteur en attente est annulé")
        #expect(source.stopCount == 1 && !source.isActive)
        #expect(!monitor.isRunning)
        source.emit()                                   // plus personne n'écoute
        scheduler.fire()
        #expect(triggers == 0)
    }

    @Test func aTriggerThatFiresAfterStopDoesNothing() {
        // Un minuteur déjà parti (annulation tardive) ne doit pas appeler le rappel d'un moniteur arrêté.
        let source = FakeNetworkSource(), scheduler = FakeScheduler()
        var triggers = 0
        let monitor = make(source, scheduler) { _ in triggers += 1 }
        monitor.start()
        source.emit()
        let job = scheduler.active[0]
        monitor.stop()
        job.work()
        #expect(triggers == 0)
    }

    @Test func startingTwiceDoesNotSubscribeTwiceAndAFailedStartIsReported() {
        let source = FakeNetworkSource(), scheduler = FakeScheduler()
        let monitor = make(source, scheduler) { _ in }
        #expect(monitor.start() && monitor.start())
        #expect(source.startCount == 1)
        monitor.stop()
        source.canStart = false
        #expect(!monitor.start())
        #expect(!monitor.isRunning)
    }

    @Test func theMonitorIsNotRetainedByItsSourceNorTheOtherWayRound() {
        let source = FakeNetworkSource(), scheduler = FakeScheduler()
        weak var weakMonitor: NetworkChangeMonitor?
        var triggers = 0
        do {
            let monitor = make(source, scheduler) { _ in triggers += 1 }
            monitor.start()
            weakMonitor = monitor
            source.emit()
        }
        #expect(weakMonitor == nil, "la source et le minuteur ne retiennent pas le moniteur")
        scheduler.fire()
        #expect(triggers == 0)
    }

    @Test func theMonitorNeverTouchesTheLookupOrTheNetwork() throws {
        for path in ["Sources/Soaro/Samplers/NetworkChangeMonitor.swift", "Sources/Soaro/Samplers/SystemNetworkEventSource.swift"] {
            let source = try String(contentsOf: RepositoryRoot.url().appendingPathComponent(path), encoding: .utf8)
            for word in ["PublicIPService", "refreshPublicIP", "publicIPFetch", "fetch(", "URLSession", "NWConnection", "NWPathMonitor", "Data(contentsOf", "Process(", "AppState"] {
                #expect(!source.contains(word), "\(path) mentionne \(word)")
            }
        }
    }

    @Test func theSystemSourceWatchesTheKeysOfTheFingerprintAndTheWake() throws {
        let source = try String(contentsOf: RepositoryRoot.url().appendingPathComponent("Sources/Soaro/Samplers/SystemNetworkEventSource.swift"), encoding: .utf8)
        for needle in ["State:/Network/Global/IPv4", "State:/Network/Global/IPv6", "State:/Network/Global/DNS", "State:/Network/Service/[^/]+/IPv4",
                       "SCDynamicStoreSetNotificationKeys", "CFRunLoopAddSource", "NSWorkspace.didWakeNotification"] {
            #expect(source.contains(needle), "absent : \(needle)")
        }
    }

    @Test func theRealSourceStartsAndStopsOnTheMainRunLoopWithoutAnyPermission() {
        let source = SystemNetworkEventSource()
        #expect(source.start { _ in })
        source.stop()
        #expect(source.start { _ in })
        source.stop()
        source.stop()                       // arrêter deux fois est sans effet
    }
}

// MARK: - AppState : la surveillance suit la condition du drapeau, les déclencheurs passent par la même décision

@MainActor @Suite(.serialized) struct PublicIPChangeFlowTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private final class Box<Value>: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: Value
        init(_ value: Value) { stored = value }
        var value: Value { get { lock.withLock { stored } } set { lock.withLock { stored = newValue } } }
    }

    private final class Fetcher: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        private var queue: [String] = []
        var calls: Int { lock.withLock { count } }
        func enqueue(_ codes: [String]) { lock.withLock { queue = codes } }
        func fetch(at date: Date) async throws -> PublicIPInfo {
            let code: String? = lock.withLock { count += 1; return queue.isEmpty ? nil : queue.removeFirst() }
            guard let code else { throw PublicIPError.unreachable }
            return PublicIPInfo(ip: "203.0.113.42", countryCode: code, country: nil, city: nil, provider: nil, fetchedAt: date)
        }
    }

    /// Tout ce qui est remplaçable, réuni : la source d'événements, le minuteur, les signaux, l'heure, le VPN et le journal.
    @MainActor private final class Rig {
        let settings = Box(true), item = Box(true)
        let signals = Box(NetworkSignals.empty)
        let clock = Box(Date(timeIntervalSince1970: 1_800_000_000))
        let log = Box<[String]>([])
        let fetcher = Fetcher()
        let source = FakeNetworkSource()
        let scheduler = FakeScheduler()
        var sourcesMade = 0
        var vpnCalls = Box(0)
        /// Ce que la détection du VPN rend, et un verrou pour la bloquer (une détection qui ne revient pas).
        let vpnStatus = Box(VPNStatus(mode: .off, name: nil, interface: nil))
        let vpnGate = Box<DispatchSemaphore?>(nil)
        var state: AppState!

        init(demo: Bool = false) {
            let settings = settings, item = item, fetcher = fetcher, clock = clock, signals = signals, log = log, vpnCalls = vpnCalls
            let vpnStatus = vpnStatus, vpnGate = vpnGate
            let watching = NetworkWatching(
                makeSource: { [unowned self] in self.sourcesMade += 1; return self.source },
                scheduler: scheduler,
                readSignals: { signals.value },
                detectVPN: { _ in vpnCalls.value += 1; vpnGate.value?.wait(); return vpnStatus.value },
                clock: { clock.value },
                log: { line in log.value.append(line) })
            state = AppState(history: nil, demo: demo,
                             publicIPFetch: { try await fetcher.fetch(at: clock.value) },
                             publicIPSetting: { settings.value },
                             networkItemShown: { _ in item.value },
                             networkWatching: watching)
        }

        var lookups: Int { fetcher.calls }
        var reasons: [String] { log.value.compactMap { $0.hasPrefix("lookup: ") ? String($0.dropFirst("lookup: ".count)) : nil } }

        /// Un tour de la mesure de 3 s, à l'heure `t`, avec attente de tout ce qu'elle lance.
        func tick(at t: Date) async {
            clock.value = t
            state.refreshPublicIPWhileFlagShown(now: t)
            await state.vpnRefreshTask?.value
            await state.publicIPLookupTask?.value
        }

        /// Un événement (ou une rafale), le délai de calme, puis tout ce que le déclenchement lance.
        func event(_ reason: NetworkChangeReason = .configuration, count: Int = 1, at t: Date) async {
            clock.value = t
            for _ in 0..<count { source.emit(reason) }
            scheduler.fire()
            await state.vpnRefreshTask?.value
            await state.publicIPLookupTask?.value
        }
    }

    private func wifi(_ address: String = "192.0.2.24", mac: String = "aa:bb:cc:00:11:22") -> NetworkSignals {
        NetworkSignals(primaryInterface: "en0", primaryRouter: "192.0.2.1", primaryInterface6: nil, primaryRouter6: nil,
                       services: [.init(interface: "en0", addresses: [address], router: "192.0.2.1",
                                        networkSignature: "IPv4.Router=192.0.2.1;IPv4.RouterHardwareAddress=\(mac)")],
                       dnsServers: ["192.0.2.1"], dnsDomain: nil, dnsSearchDomains: [], tunnels: [])
    }

    /// Premier tour : la première recherche a lieu (rien n'est connu), sans confirmation.
    private func started(_ rig: Rig, codes: [String]) async {
        rig.fetcher.enqueue(codes)
        rig.signals.value = wifi()
        await rig.tick(at: t0)
    }

    // MARK: Création et arrêt du moniteur

    @Test func theMonitorExistsOnlyWhileTheFlagOrTheTabNeedsIt() async {
        let rig = Rig()
        await started(rig, codes: ["FR"])
        #expect(rig.sourcesMade == 1 && rig.source.isActive, "créé : réglage activé, bloc réseau affiché")
        #expect(rig.state.isNetworkMonitorRunning)

        rig.item.value = false
        await rig.tick(at: t0.addingTimeInterval(3))
        #expect(!rig.source.isActive && rig.source.stopCount == 1, "bloc masqué : arrêté")
        #expect(!rig.state.isNetworkMonitorRunning)

        rig.item.value = true
        await rig.tick(at: t0.addingTimeInterval(6))
        #expect(rig.sourcesMade == 2 && rig.source.isActive, "de nouveau affiché : recréé")

        rig.settings.value = false
        await rig.tick(at: t0.addingTimeInterval(9))
        #expect(!rig.source.isActive && !rig.state.isNetworkMonitorRunning, "réglage coupé : arrêté")
    }

    @Test func turningTheSettingOffStopsTheMonitorAtOnce() async {
        let rig = Rig()
        await started(rig, codes: ["FR"])
        rig.settings.value = false
        rig.state.forgetPublicIP()                       // ce que fait l'interrupteur des réglages
        #expect(!rig.source.isActive, "sans attendre la mesure suivante")
        #expect(!rig.state.isNetworkMonitorRunning)
        rig.source.emit()                                // un événement tardif n'a plus d'écoute
        rig.scheduler.fire()
        #expect(rig.lookups == 1)
    }

    @Test func noMonitorWithTheSettingOffTheItemHiddenOrInDemo() async {
        let off = Rig(); off.settings.value = false
        await off.tick(at: t0)
        let hidden = Rig(); hidden.item.value = false
        await hidden.tick(at: t0)
        let demo = Rig(demo: true)
        await demo.tick(at: t0)
        demo.state.refreshPublicIP(force: true, now: t0)
        for rig in [off, hidden, demo] {
            #expect(rig.sourcesMade == 0 && !rig.source.isActive && !rig.state.isNetworkMonitorRunning)
        }
        #expect(demo.lookups == 0)
    }

    @Test func aSourceThatCannotStartLeavesNoMonitorAndTheTickStillWorks() async {
        let rig = Rig()
        rig.source.canStart = false
        await started(rig, codes: ["FR", "DE"])
        #expect(!rig.state.isNetworkMonitorRunning)
        #expect(rig.lookups == 1, "la détection par la mesure de 3 s reste le filet de sécurité")
        rig.signals.value = wifi("192.0.2.77")
        await rig.tick(at: t0.addingTimeInterval(10))     // observé, pas encore stable
        #expect(rig.lookups == 1)
        await rig.tick(at: t0.addingTimeInterval(13))
        #expect(rig.lookups == 2)
    }

    @Test func theMonitorDoesNotRetainAppState() async {
        let source = FakeNetworkSource(), scheduler = FakeScheduler()
        weak var weakState: AppState?
        do {
            let watching = NetworkWatching(makeSource: { source }, scheduler: scheduler, readSignals: { .empty },
                                           detectVPN: { _ in VPNStatus(mode: .off, name: nil, interface: nil) }, clock: { Date() }, log: { _ in })
            let state = AppState(history: nil, demo: false,
                                 publicIPFetch: { throw PublicIPError.unreachable }, publicIPSetting: { true }, networkItemShown: { _ in true },
                                 networkWatching: watching)
            state.refreshPublicIPWhileFlagShown(now: Date())
            #expect(state.isNetworkMonitorRunning && source.isActive)
            source.emit()                                // un minuteur est en attente avec le rappel du moniteur
            weakState = state
            state.publicIPLookupTask?.cancel()
        }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(weakState == nil, "ni la source, ni le minuteur, ni le moniteur ne retiennent AppState")
        scheduler.fire()                                 // le rappel d'un état disparu ne fait rien
    }

    // MARK: Un changement détecté : une recherche, puis une confirmation

    @Test func aStartupLookupIsNotFollowedByAConfirmation() async {
        let rig = Rig()
        await started(rig, codes: ["FR", "DE"])
        for s in stride(from: 3.0, through: 60, by: 3) { await rig.tick(at: t0.addingTimeInterval(s)) }
        #expect(rig.lookups == 1)
        #expect(rig.reasons == ["first"])
    }

    @Test func aChangeOfNetworkGivesOneLookupAfterTheQuietPeriodThenOneConfirmationThenNothing() async {
        let rig = Rig()
        await started(rig, codes: ["FR", "DE", "DE", "XX"])
        // Autre réseau local : même plage 192.0.2.x, même routeur, mais un autre routeur matériel (autre MAC).
        rig.signals.value = wifi(mac: "dd:ee:ff:33:44:55")
        await rig.event(at: t0.addingTimeInterval(20))
        #expect(rig.lookups == 2)
        #expect(rig.state.publicIP?.countryCode == "DE")
        // Entre-temps, rien avant 10 s.
        await rig.tick(at: t0.addingTimeInterval(23))
        await rig.tick(at: t0.addingTimeInterval(27))
        #expect(rig.lookups == 2)
        await rig.tick(at: t0.addingTimeInterval(30))         // 10 s après la recherche déclenchée
        #expect(rig.lookups == 3)
        #expect(rig.reasons == ["first", "network-change", "confirmation"])
        // Et c'est tout : jamais de seconde confirmation.
        for s in stride(from: 33.0, through: 320, by: 3) { await rig.tick(at: t0.addingTimeInterval(s)) }
        #expect(rig.lookups == 3, "ni seconde confirmation ni requête avant les 5 minutes")
        #expect(rig.reasons.filter { $0 == "confirmation" }.count == 1)
    }

    @Test func theSecondAnswerReplacesTheFirstWhenItDiffersAndWhenItIsTheSameNothingMoreHappens() async {
        let rig = Rig()
        await started(rig, codes: ["FR", "DE", "CH"])         // le premier avis venait encore de l'ancienne route
        rig.signals.value = wifi("192.0.2.80")
        await rig.event(at: t0.addingTimeInterval(20))
        #expect(rig.state.publicIP?.countryCode == "DE")
        await rig.tick(at: t0.addingTimeInterval(31))
        #expect(rig.state.publicIP?.countryCode == "CH", "la nouvelle réponse est gardée")
        #expect(rig.state.publicIPMatchesNetwork)
        let after = rig.lookups
        for s in stride(from: 34.0, through: 200, by: 3) { await rig.tick(at: t0.addingTimeInterval(s)) }
        #expect(rig.lookups == after, "pas de troisième avis")
    }

    @Test func aBurstOfEventsGivesASingleLookup() async {
        let rig = Rig()
        await started(rig, codes: ["FR", "DE", "DE"])
        rig.signals.value = wifi("192.0.2.81")
        await rig.event(count: 12, at: t0.addingTimeInterval(20))
        #expect(rig.lookups == 2)
        #expect(rig.reasons == ["first", "network-change"])
    }

    @Test func theFlagIsHiddenAtTheChangeAndComesBackWithTheNewReply() async {
        let rig = Rig()
        await started(rig, codes: ["FR", "DE"])
        #expect(rig.state.publicIPMatchesNetwork)
        rig.signals.value = wifi(mac: "dd:ee:ff:33:44:55")
        #expect(!rig.state.publicIPMatchesNetwork, "l'empreinte étendue sert aussi à la règle « même connexion »")
        await rig.event(at: t0.addingTimeInterval(20))
        #expect(rig.state.publicIPMatchesNetwork)
    }

    @Test func aChangeSeenByTheTickAloneWaitsForTheQuietPeriod() async {
        let rig = Rig()
        await started(rig, codes: ["FR", "DE", "DE"])
        rig.signals.value = wifi("192.0.2.82")
        await rig.tick(at: t0.addingTimeInterval(21))
        #expect(rig.lookups == 1, "vu pour la première fois : pas encore stable")
        await rig.tick(at: t0.addingTimeInterval(23.9))
        #expect(rig.lookups == 1)
        await rig.tick(at: t0.addingTimeInterval(24))
        #expect(rig.lookups == 2)
    }

    @Test func aWakeLooksUpEvenWhenTheFingerprintIsTheSameThenConfirmsOnce() async {
        let rig = Rig()
        await started(rig, codes: ["FR", "FR", "FR"])
        await rig.event(.wake, at: t0.addingTimeInterval(100))
        #expect(rig.lookups == 2)
        await rig.tick(at: t0.addingTimeInterval(111))
        #expect(rig.lookups == 3)
        #expect(rig.reasons == ["first", "wake", "confirmation"])
    }

    @Test func aConfigurationEventWithTheSameFingerprintAsksForNothing() async {
        // Un renouvellement de bail, une notification sans effet : aucun trafic.
        let rig = Rig()
        await started(rig, codes: ["FR", "DE"])
        for k in 1...10 { await rig.event(count: 5, at: t0.addingTimeInterval(Double(k) * 10)) }
        #expect(rig.lookups == 1)
    }

    @Test func nothingChangesNothingIsAskedBetweenTheFiveMinuteChecks() async {
        let rig = Rig()
        await started(rig, codes: ["FR", "FR"])
        for s in stride(from: 3.0, through: 299, by: 3) { await rig.tick(at: t0.addingTimeInterval(s)) }
        #expect(rig.lookups == 1, "pas une seule requête de plus pendant 5 minutes sans changement")
        await rig.tick(at: t0.addingTimeInterval(302))
        #expect(rig.lookups == 2)
        #expect(rig.reasons == ["first", "periodic"])
    }

    @Test func aFailedChangeLookupIsNotConfirmed() async {
        let rig = Rig()
        await started(rig, codes: ["FR"])                      // la file est vide ensuite : la recherche suivante échoue
        rig.signals.value = wifi("192.0.2.83")
        await rig.event(at: t0.addingTimeInterval(20))
        #expect(rig.lookups == 2)
        for s in stride(from: 23.0, through: 140, by: 3) { await rig.tick(at: t0.addingTimeInterval(s)) }
        #expect(rig.lookups == 2, "pas de confirmation après un échec, ni de nouvelle tentative (la réponse de 20 s est encore jeune)")
        #expect(!rig.reasons.contains("confirmation"))
    }

    @Test func theConfirmationIsCancelledWhenTheSettingIsTurnedOffOrTheItemHidden() async {
        for hideInstead in [false, true] {
            let rig = Rig()
            await started(rig, codes: ["FR", "DE", "DE", "DE"])
            rig.signals.value = wifi("192.0.2.84")
            await rig.event(at: t0.addingTimeInterval(20))
            #expect(rig.lookups == 2)
            if hideInstead { rig.item.value = false } else { rig.settings.value = false; rig.state.forgetPublicIP() }
            await rig.tick(at: t0.addingTimeInterval(24))
            await rig.tick(at: t0.addingTimeInterval(40))
            #expect(rig.lookups == 2, "rien tant que la condition ne tient pas (\(hideInstead ? "bloc masqué" : "réglage coupé"))")
            // Rétablie : l'ancienne confirmation n'est pas rejouée.
            rig.item.value = true; rig.settings.value = true
            await rig.tick(at: t0.addingTimeInterval(43))
            await rig.tick(at: t0.addingTimeInterval(46))
            #expect(!rig.reasons.contains("confirmation"), "la confirmation annulée ne revient pas")
        }
    }

    @Test func theTabOpenPathStillComparesTheFingerprintAtOnce() {
        // L'onglet Réseau garde sa règle : tout de suite (la preuve complète est la grille de PublicIPLookupPolicyTests).
        #expect(PublicIPLookupPolicy.fingerprintChanged("b", "a", false, false, true))
    }


    // MARK: Le démarrage : une seule recherche, la base est complétée sans recherche (SL25, défaut trouvé sur le journal réel du Mac de l'auteur)

    private let vpnOn = VPNStatus(mode: .full, name: "WireGuard", interface: "utun4")

    /// Le défaut : la première recherche partait avant la fin de la détection du VPN (`vpn` encore nil) ; la mesure suivante voyait une autre
    /// empreinte, la prenait pour un vrai changement (recherche « network-change » 6 s après) puis armait une confirmation 10 s plus tard.
    @Test func aLaunchWithAnUnchangedNetworkGivesExactlyOneLookupAndNoConfirmation() async {
        let rig = Rig()
        rig.vpnStatus.value = vpnOn                                  // le Mac de l'auteur : un VPN est actif au démarrage
        rig.fetcher.enqueue(["FR", "FR", "FR", "FR"])
        // Mesure 1 : le premier relevé, rien de lu (pas de signaux), la détection du VPN part.
        rig.signals.value = .empty
        rig.clock.value = t0
        rig.state.refreshPublicIPWhileFlagShown(now: t0)
        #expect(rig.state.publicIPState == .idle, "la première recherche attend la fin de la détection du VPN")
        await rig.state.vpnRefreshTask?.value
        await rig.state.publicIPLookupTask?.value
        // Mesure 2 : les signaux arrivent ; mesure 3 : tout est là.
        rig.signals.value = wifi()
        await rig.tick(at: t0.addingTimeInterval(3))
        await rig.tick(at: t0.addingTimeInterval(6))
        for s in stride(from: 9.0, through: 299, by: 3) { await rig.tick(at: t0.addingTimeInterval(s)) }
        #expect(rig.lookups == 1, "exactement une requête dans les 300 premières secondes")
        #expect(rig.reasons == ["first"])
        #expect(rig.state.publicIPMatchesNetwork, "la réponse de la première recherche vaut pour l'empreinte complète")
    }

    @Test func theFirstLookupWaitsForTheVPNDetectionThenRecordsTheCompleteFingerprint() async {
        let rig = Rig()
        rig.vpnStatus.value = vpnOn
        rig.fetcher.enqueue(["FR", "FR"])
        rig.signals.value = wifi()
        rig.clock.value = t0
        rig.state.refreshPublicIPWhileFlagShown(now: t0)
        #expect(rig.state.publicIPState == .idle, "pas encore : la détection n'est pas revenue")
        await rig.state.vpnRefreshTask?.value
        await rig.state.publicIPLookupTask?.value
        #expect(rig.lookups == 1)
        #expect(rig.state.vpn?.isActive == true, "l'empreinte de la recherche portait déjà le VPN")
        #expect(rig.state.publicIPMatchesNetwork)
        for s in stride(from: 3.0, through: 120, by: 3) { await rig.tick(at: t0.addingTimeInterval(s)) }
        #expect(rig.lookups == 1)
    }

    @Test func aBaselineTakenIncompleteBecomesTheCompleteOneWithoutALookupOrAConfirmation() async {
        // Une recherche partie sans détection en cours (appel direct, comme l'onglet Réseau ou un test) : l'empreinte est incomplète (vpn nil).
        let rig = Rig()
        rig.vpnStatus.value = vpnOn
        rig.fetcher.enqueue(["FR", "FR", "FR"])
        rig.signals.value = wifi()
        rig.state.refreshPublicIP(now: t0)
        await rig.state.publicIPLookupTask?.value
        #expect(rig.lookups == 1)
        #expect(!rig.state.publicIPMatchesNetwork || rig.state.vpn == nil)
        for s in stride(from: 3.0, through: 299, by: 3) { await rig.tick(at: t0.addingTimeInterval(s)) }
        #expect(rig.lookups == 1, "passer d'incomplet à complet n'est pas un changement")
        #expect(rig.reasons == ["first"])
        #expect(rig.state.publicIPMatchesNetwork, "la réponse est rattachée à l'empreinte complète : le drapeau reste affiché")
        #expect(rig.log.value.contains { $0.hasPrefix("baseline:") }, "le journal montre l'étape")
    }

    @Test func aRealChangeAfterTheLaunchBaselineGivesOneLookupAndExactlyOneConfirmation() async {
        let changes: [(String, NetworkSignals)] = [
            ("signature du routeur", wifi(mac: "dd:ee:ff:33:44:55")),
            ("DNS", { var s = wifi(); s.dnsServers = ["198.51.100.1"]; return s }()),
            ("un tunnel apparaît", { var s = wifi(); s.tunnels = [.init(name: "utun7", address: "198.51.100.9")]; return s }()),
        ]
        for (label, changed) in changes {
            let rig = Rig()
            rig.vpnStatus.value = vpnOn
            rig.fetcher.enqueue(["FR", "DE", "DE", "DE"])
            rig.signals.value = wifi()
            await rig.tick(at: t0)
            for s in stride(from: 3.0, through: 60, by: 3) { await rig.tick(at: t0.addingTimeInterval(s)) }
            #expect(rig.lookups == 1, "\(label) : une seule recherche avant le changement")
            rig.signals.value = changed
            await rig.event(at: t0.addingTimeInterval(70))
            for s in stride(from: 73.0, through: 120, by: 3) { await rig.tick(at: t0.addingTimeInterval(s)) }
            #expect(rig.reasons == ["first", "network-change", "confirmation"], "\(label)")
        }
    }

    @Test func aWakeAfterTheLaunchGivesALookupAndAConfirmation() async {
        let rig = Rig()
        rig.vpnStatus.value = vpnOn
        rig.fetcher.enqueue(["FR", "FR", "FR"])
        rig.signals.value = wifi()
        await rig.tick(at: t0)
        await rig.event(.wake, at: t0.addingTimeInterval(100))
        await rig.tick(at: t0.addingTimeInterval(111))
        for s in stride(from: 114.0, through: 200, by: 3) { await rig.tick(at: t0.addingTimeInterval(s)) }
        #expect(rig.reasons == ["first", "wake", "confirmation"])
    }

    @Test func aDetectionThatNeverReturnsDoesNotMakeTheFirstLookupWaitForeverNorLoop() async {
        let rig = Rig()
        let gate = DispatchSemaphore(value: 0)
        rig.vpnGate.value = gate
        rig.fetcher.enqueue([])                                  // aucune réponse : la recherche échoue
        rig.signals.value = wifi()
        rig.clock.value = t0
        rig.state.refreshPublicIPWhileFlagShown(now: t0)
        for s in [3.0, 6, 9, 9.9] {
            rig.clock.value = t0.addingTimeInterval(s)
            rig.state.refreshPublicIPWhileFlagShown(now: t0.addingTimeInterval(s))
        }
        await Task.yield()
        #expect(rig.lookups == 0, "avant le plafond de 10 s, la première recherche attend")
        rig.clock.value = t0.addingTimeInterval(10)
        rig.state.refreshPublicIPWhileFlagShown(now: t0.addingTimeInterval(10))
        await rig.state.publicIPLookupTask?.value
        #expect(rig.lookups == 1, "au plafond, on cherche avec ce qu'on a")
        // La recherche a échoué : la pause de 60 s s'applique, et on ne boucle pas.
        for s in stride(from: 13.0, through: 69, by: 3) {
            rig.clock.value = t0.addingTimeInterval(s)
            rig.state.refreshPublicIPWhileFlagShown(now: t0.addingTimeInterval(s))
            await rig.state.publicIPLookupTask?.value
        }
        #expect(rig.lookups == 1, "pas de nouvelle tentative dans les 60 s qui suivent l'échec")
        gate.signal()                                            // la détection finit par revenir : rien ne s'emballe
        for _ in 0..<10 { gate.signal() }
        await rig.state.vpnRefreshTask?.value
    }

    @Test func anOfflineMacLooksUpAtMostOncePerMinuteAndNeverWaitsForever() async {
        let rig = Rig()
        rig.signals.value = .empty
        rig.fetcher.enqueue([])
        for s in stride(from: 0.0, through: 305, by: 3) { await rig.tick(at: t0.addingTimeInterval(s)) }
        #expect(rig.lookups >= 1, "il cherche quand même")
        #expect(rig.lookups <= 6, "au plus une recherche par minute : \(rig.lookups)")
    }

    @Test func theTabAndTheForcedLookupNeverWaitForTheDetection() async {
        let rig = Rig()
        rig.vpnGate.value = DispatchSemaphore(value: 0)
        rig.fetcher.enqueue(["FR"])
        rig.signals.value = wifi()
        rig.clock.value = t0
        rig.state.refreshPublicIPWhileFlagShown(now: t0)               // une détection est en cours et bloquée
        #expect(rig.state.publicIPState == .idle)
        rig.state.refreshPublicIP(force: true, now: t0.addingTimeInterval(1))
        #expect(rig.state.publicIPState == .loading, "l'interrupteur des réglages et « Actualiser » cherchent tout de suite")
        await rig.state.publicIPLookupTask?.value
        rig.vpnGate.value?.signal()
    }

    // MARK: Journal

    @Test func theDebugLogListsEachLookupWithItsReasonAndNeverTheAddressOrTheCountry() async {
        let rig = Rig()
        await started(rig, codes: ["FR", "DE", "DE"])
        rig.signals.value = wifi("192.0.2.85")
        await rig.event(at: t0.addingTimeInterval(20))
        await rig.tick(at: t0.addingTimeInterval(31))
        #expect(rig.reasons == ["first", "network-change", "confirmation"])
        #expect(rig.log.value.contains { $0.hasPrefix("network event") }, "les événements aussi")
        for line in rig.log.value {
            #expect(!line.contains("203.0.113") && !line.contains("FR") && !line.contains("DE"), "\(line)")
        }
    }

    @Test func theDebugLogGoesToStandardErrorOnlyWithTheDebugVariable() throws {
        let source = try String(contentsOf: RepositoryRoot.url().appendingPathComponent("Sources/Soaro/Samplers/NetworkWatching.swift"), encoding: .utf8)
        let range = try #require(source.range(of: "static func debugLog"))
        let body = String(source[range.lowerBound...].prefix(500))
        #expect(body.contains("SOARO_DEBUG") && body.contains("standardError"))
    }
}

// MARK: - Gardes de source et documents

@Suite struct PublicIPChangeSourceTests {
    private func read(_ path: String) throws -> String {
        try String(contentsOf: RepositoryRoot.url().appendingPathComponent(path), encoding: .utf8)
    }

    @Test func theNewCodeReferencesNoURLSessionNorNWConnection() throws {
        for path in ["Sources/Soaro/Samplers/NetworkSignals.swift", "Sources/Soaro/Samplers/NetworkChangeMonitor.swift",
                     "Sources/Soaro/Samplers/SystemNetworkEventSource.swift", "Sources/Soaro/Samplers/PublicIPLookupPolicy.swift"] {
            let source = try read(path)
            #expect(!source.contains("URLSession") && !source.contains("NWConnection"), Comment(rawValue: path))
        }
    }

    @Test func theServiceIsStillCalledFromAppStateOnlyThroughTheOneDecision() throws {
        let source = try read("Sources/Soaro/AppState.swift")
        #expect(source.components(separatedBy: "PublicIPService.fetch").count == 2, "un seul appel au service, valeur par défaut de la graine de test")
        #expect(source.components(separatedBy: "try await fetch()").count == 2, "un seul point de départ de recherche")
        #expect(!source.contains("DispatchQueue") && !source.contains("Thread("))
        #expect(source.components(separatedBy: "Timer(timeInterval").count == 2, "aucun minuteur de plus dans AppState")
    }

    @Test func theNetworkTabAndTheSettingsStillCallTheSameFunctionAsBefore() throws {
        #expect(try read("Sources/Soaro/Views/NetworkTab.swift").contains("state.refreshPublicIP(force: true)"))
        #expect(try read("Sources/Soaro/Views/SettingsView.swift").contains("state.refreshPublicIP(force: true)"))
    }

    @Test func theSettingsSentenceStillTellsTheTruth() throws {
        let key = "about every 5 minutes, and again when your network or VPN changes"
        #expect(try read("Sources/Soaro/Views/SettingsView.swift").contains(key))
    }

    @Test func theADRExistsAndIsInBothIndexesAndExtendsWithoutSuperseding() throws {
        let file = "0012-public-ip-lookup-triggers-and-confirmation.md"
        let adr = try read("docs/adr/\(file)")
        #expect(adr.contains("accepted") && adr.contains("2026-11-18"))
        #expect(adr.contains("0011") && adr.contains("0007"))
        #expect(adr.contains("Extends [0011]") && adr.contains("does not supersede"))
        #expect(try read("docs/adr/README.md").contains(file))
        #expect(try read("ARCHITECTURE.md").contains(file))
        // Les ADR acceptés 0007 et 0011 ne sont pas modifiés par ce découpage : ils ne parlent pas de 0012.
        #expect(!(try read("docs/adr/0011-public-ip-lookup-also-runs-while-its-flag-is-shown.md")).contains("0012"))
        #expect(!(try read("docs/adr/0007-privacy-by-default.md")).contains("0012"))
    }
}
