import Foundation

/// Tout ce que `AppState` utilise pour suivre les changements de réseau, avec le comportement réel par défaut (SL25).
/// Les tests remplacent chaque élément : la source d'événements, le minuteur, les signaux, la détection du VPN, l'heure et le journal.
struct NetworkWatching {
    var makeSource: @MainActor () -> NetworkEventSource = { SystemNetworkEventSource() }
    var scheduler: DebounceScheduler = TaskDebounceScheduler()
    var readSignals: () -> NetworkSignals = { NetworkSignalsReader.read() }
    var detectVPN: @Sendable ([String]) -> VPNStatus = { VPNDetector.detect(processNames: $0) }
    var clock: () -> Date = { Date() }
    var log: (String) -> Void = NetworkWatching.debugLog

    /// Une ligne sur la sortie d'erreur, seulement avec `SOARO_DEBUG` : l'heure et le motif, jamais l'adresse ni le pays.
    static func debugLog(_ line: String) {
        guard ProcessInfo.processInfo.environment["SOARO_DEBUG"] != nil else { return }
        let stamp = ISO8601DateFormatter().string(from: Date())
        FileHandle.standardError.write(Data("[soaro] \(stamp) public IP \(line)\n".utf8))
    }
}
