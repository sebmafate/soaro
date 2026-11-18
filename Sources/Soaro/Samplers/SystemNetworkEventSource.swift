import AppKit
import Foundation
import SystemConfiguration

/// La vraie source d'événements : le magasin dynamique de SystemConfiguration (les mêmes clés que celles que lit l'empreinte) et le réveil.
///
/// Pourquoi SystemConfiguration plutôt qu'un moniteur de chemin du framework Network : il notifie exactement les clés lues
/// (interface principale, passerelle, DNS, services), y compris un saut de serveur VPN qui ne change que le DNS ou la passerelle du tunnel,
/// ce que le chemin ne signale pas ; il ne demande aucun droit pour une app non sandboxée (ADR 0002) ; il est déjà lié au projet ;
/// et il se branche sur la boucle principale, sans file ni fil de plus. Il n'envoie aucun trafic.
@MainActor final class SystemNetworkEventSource: NetworkEventSource {
    static let keys = ["State:/Network/Global/IPv4", "State:/Network/Global/IPv6", "State:/Network/Global/DNS"]
    static let patterns = ["State:/Network/Service/[^/]+/IPv4"]

    /// Le rappel C passe par une boîte retenue par le contexte du magasin ; la boîte ne retient que le rappel de la source.
    private final class Box: @unchecked Sendable {
        let deliver: @MainActor (NetworkChangeReason) -> Void
        init(_ deliver: @escaping @MainActor (NetworkChangeReason) -> Void) { self.deliver = deliver }
    }

    private let keys: [String]
    private let patterns: [String]
    /// Les clés sont celles de l'empreinte ; un test peut en donner d'autres pour vérifier la livraison réelle sans toucher aux vraies clés.
    init(keys: [String] = SystemNetworkEventSource.keys, patterns: [String] = SystemNetworkEventSource.patterns) {
        self.keys = keys
        self.patterns = patterns
    }

    private var store: SCDynamicStore?
    private var runLoopSource: CFRunLoopSource?
    private var wakeObserver: NSObjectProtocol?

    func start(_ onEvent: @escaping @MainActor (NetworkChangeReason) -> Void) -> Bool {
        stop()
        let box = Box(onEvent)
        var context = SCDynamicStoreContext(
            version: 0, info: Unmanaged.passUnretained(box).toOpaque(),
            retain: { info in _ = Unmanaged<Box>.fromOpaque(info).retain(); return UnsafeRawPointer(info) },
            release: { info in Unmanaged<Box>.fromOpaque(info).release() },
            copyDescription: nil)
        // Le magasin retient la boîte lui-même (rappels `retain` et `release` du contexte) et la rend quand il disparaît.
        let callback: SCDynamicStoreCallBack = { _, _, info in
            guard let info else { return }
            let box = Unmanaged<Box>.fromOpaque(info).takeUnretainedValue()
            Task { @MainActor in box.deliver(.configuration) }
        }
        guard let store = SCDynamicStoreCreate(nil, "Soaro network events" as CFString, callback, &context),
              SCDynamicStoreSetNotificationKeys(store, keys as CFArray, patterns as CFArray),
              let source = SCDynamicStoreCreateRunLoopSource(nil, store, 0) else { return false }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.store = store
        self.runLoopSource = source
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in box.deliver(.wake) }
        }
        return true
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            CFRunLoopSourceInvalidate(runLoopSource)
        }
        runLoopSource = nil
        store = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
    }

    deinit {
        // Si la source disparaît sans `stop`, on retire quand même ce qui touche la boucle et le centre de notifications.
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            CFRunLoopSourceInvalidate(runLoopSource)
        }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }
}
