import Darwin
import Foundation
import SystemConfiguration

/// Les signaux locaux qui disent « la connexion a changé, donc l'IP publique a peut-être changé » (SL25, ADR 0012).
///
/// Une valeur pure et comparable, construite par une fonction pure (`make`) à partir de dictionnaires : une différence entre deux valeurs
/// est ce qui déclenche une recherche. Tout est lu en local (magasin dynamique de SystemConfiguration, `getifaddrs`) : aucune requête,
/// aucune autorisation, aucune fenêtre de permission. On n'y met que ce qui décrit **où l'on est connecté**, jamais ce qui bouge tout le
/// temps (force du signal, compteurs d'octets, renouvellement de bail, bornes d'un même réseau).
struct NetworkSignals: Equatable, Sendable {
    /// Un service réseau de macOS (Wi-Fi, Ethernet, VPN) avec son état IPv4.
    struct Service: Equatable, Sendable {
        var interface: String
        var addresses: [String]
        var router: String?
        /// `NetworkSignature` : macOS y écrit lui-même le routeur et l'adresse matérielle du routeur (« IPv4.Router=…;IPv4.RouterHardwareAddress=… »).
        /// C'est ce qui distingue deux réseaux domestiques en 192.168.1.x qui ont la même adresse locale et le même routeur, sans lire le SSID.
        var networkSignature: String?
    }

    /// Une interface de tunnel (utun, ipsec, ppp, tun, tap) active, avec son adresse IPv4.
    struct Tunnel: Equatable, Sendable {
        var name: String
        var address: String
    }

    var primaryInterface: String?
    var primaryRouter: String?
    var primaryInterface6: String?
    var primaryRouter6: String?
    var services: [Service] = []
    var dnsServers: [String] = []
    var dnsDomain: String?
    var dnsSearchDomains: [String] = []
    var tunnels: [Tunnel] = []

    static let empty = NetworkSignals()
    var isEmpty: Bool { self == .empty }

    /// La partie de l'empreinte qui vient de ces signaux. Vide si aucun signal : l'empreinte reste alors exactement celle d'avant.
    var fingerprintPart: String {
        if isEmpty { return "" }
        let services = services.map { s in
            [s.interface, s.addresses.joined(separator: ","), s.router ?? "-", s.networkSignature ?? "-"].joined(separator: "/")
        }.joined(separator: ";")
        let tunnels = tunnels.map { "\($0.name)/\($0.address)" }.joined(separator: ";")
        let parts = [
            "if=\(primaryInterface ?? "-")", "gw=\(primaryRouter ?? "-")", "if6=\(primaryInterface6 ?? "-")", "gw6=\(primaryRouter6 ?? "-")",
            "svc=\(services)", "dns=\(dnsServers.joined(separator: ","))", "dom=\(dnsDomain ?? "-")", "sd=\(dnsSearchDomains.joined(separator: ","))",
            "tun=\(tunnels)",
        ]
        return "|net:" + parts.joined(separator: "|")
    }

    // MARK: Construction (fonction pure)

    private static func string(_ value: Any?) -> String? {
        guard let text = value as? String, !text.isEmpty else { return nil }
        return text
    }

    private static func strings(_ value: Any?) -> [String] {
        (value as? [Any])?.compactMap { $0 as? String }.filter { !$0.isEmpty } ?? []
    }

    /// `global4` / `global6` : `State:/Network/Global/IPv4` et `IPv6` ; `dns` : `State:/Network/Global/DNS` ;
    /// `services` : un dictionnaire par `State:/Network/Service/<id>/IPv4`. Seules les clés utiles sont lues, le reste est du bruit.
    static func make(global4: [String: Any]?, global6: [String: Any]?, dns: [String: Any]?,
                     services: [[String: Any]], tunnels: [Tunnel]) -> NetworkSignals {
        var result = NetworkSignals()
        result.primaryInterface = string(global4?["PrimaryInterface"])
        result.primaryRouter = string(global4?["Router"])
        result.primaryInterface6 = string(global6?["PrimaryInterface"])
        result.primaryRouter6 = string(global6?["Router"])
        result.dnsServers = strings(dns?["ServerAddresses"])
        result.dnsDomain = string(dns?["DomainName"])
        result.dnsSearchDomains = strings(dns?["SearchDomains"])
        result.services = services.compactMap { dictionary in
            guard let interface = string(dictionary["InterfaceName"]) else { return nil }
            return Service(interface: interface, addresses: strings(dictionary["Addresses"]).sorted(),
                           router: string(dictionary["Router"]), networkSignature: string(dictionary["NetworkSignature"]))
        }.sorted { ($0.interface, $0.addresses.joined(), $0.router ?? "") < ($1.interface, $1.addresses.joined(), $1.router ?? "") }
        result.tunnels = tunnels.sorted { ($0.name, $0.address) < ($1.name, $1.address) }
        return result
    }
}

/// Lecture des signaux sur le Mac : SystemConfiguration (lecture seule) et `getifaddrs`. Aucune requête réseau, aucune autorisation.
enum NetworkSignalsReader {
    static func read() -> NetworkSignals {
        var global4: [String: Any]?, global6: [String: Any]?, dns: [String: Any]?
        var services: [[String: Any]] = []
        if let store = SCDynamicStoreCreate(nil, "Soaro" as CFString, nil, nil),
           let values = SCDynamicStoreCopyMultiple(store, ["State:/Network/Global/IPv4", "State:/Network/Global/IPv6", "State:/Network/Global/DNS"] as CFArray,
                                                   ["State:/Network/Service/[^/]+/IPv4"] as CFArray) as? [String: Any] {
            global4 = values["State:/Network/Global/IPv4"] as? [String: Any]
            global6 = values["State:/Network/Global/IPv6"] as? [String: Any]
            dns = values["State:/Network/Global/DNS"] as? [String: Any]
            services = values.compactMap { key, value in key.hasPrefix("State:/Network/Service/") ? value as? [String: Any] : nil }
        }
        return NetworkSignals.make(global4: global4, global6: global6, dns: dns, services: services, tunnels: tunnelsWithIPv4())
    }

    /// Interfaces de tunnel actives qui portent une adresse IPv4. Seulement l'IPv4 : les tunnels « système » d'Apple n'ont que de l'IPv6
    /// et ne doivent pas faire bouger l'empreinte.
    static func tunnelsWithIPv4() -> [NetworkSignals.Tunnel] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return [] }
        defer { freeifaddrs(head) }
        var tunnels: [NetworkSignals.Tunnel] = []
        var cursor = head
        while let ptr = cursor {
            defer { cursor = ptr.pointee.ifa_next }
            let name = String(cString: ptr.pointee.ifa_name)
            guard VPNDetector.isTunnel(name), let addr = ptr.pointee.ifa_addr,
                  Int32(addr.pointee.sa_family) == AF_INET, ptr.pointee.ifa_flags & UInt32(IFF_UP) != 0,
                  let address = NetworkSampler.ipv4String(addr) else { continue }
            tunnels.append(.init(name: name, address: address))
        }
        return tunnels
    }
}
