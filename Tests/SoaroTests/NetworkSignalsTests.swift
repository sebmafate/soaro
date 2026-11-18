import Foundation
import Testing
@testable import Soaro

/// SL25 T1 : l'empreinte de la connexion s'enrichit de signaux locaux, lus sans aucune requête (SystemConfiguration, `getifaddrs`).
/// Une différence entre deux empreintes est ce qui déclenche une recherche : chaque signal utile doit donc la changer, et le bruit
/// (force du signal Wi-Fi, compteurs d'octets, renouvellement de bail) ne doit jamais la changer.
@Suite struct NetworkSignalsTests {
    // Des adresses de documentation (RFC 5737) et des noms inventés : rien ne vient d'une vraie machine.
    private func base() -> NetworkSignals {
        NetworkSignals(
            primaryInterface: "en0", primaryRouter: "192.0.2.1", primaryInterface6: nil, primaryRouter6: nil,
            services: [.init(interface: "en0", addresses: ["192.0.2.24"], router: "192.0.2.1",
                             networkSignature: "IPv4.Router=192.0.2.1;IPv4.RouterHardwareAddress=aa:bb:cc:00:11:22")],
            dnsServers: ["192.0.2.1"], dnsDomain: "home", dnsSearchDomains: ["home"],
            tunnels: [])
    }

    private func fp(_ s: NetworkSignals, localIP: String? = "192.0.2.24", vpn: VPNStatus? = nil) -> String {
        PublicIPLookupPolicy.fingerprint(localIP: localIP, vpn: vpn, signals: s)
    }

    // MARK: Compatibilité

    @Test func noSignalsLeaveTheFingerprintExactlyAsBefore() {
        let vpn = VPNStatus(mode: .full, name: "WireGuard", interface: "utun4")
        #expect(PublicIPLookupPolicy.fingerprint(localIP: "192.0.2.7", vpn: vpn, signals: .empty) == "192.0.2.7|vpn|utun4|WireGuard")
        #expect(PublicIPLookupPolicy.fingerprint(localIP: "192.0.2.7", vpn: vpn) == "192.0.2.7|vpn|utun4|WireGuard")
        #expect(PublicIPLookupPolicy.fingerprint(localIP: nil, vpn: nil, signals: .empty) == "-|none|-|-")
        #expect(NetworkSignals.empty.isEmpty)
        #expect(!base().isEmpty)
    }

    @Test func theSameSignalsGiveTheSameFingerprint() {
        #expect(fp(base()) == fp(base()))
    }

    // MARK: Chaque signal utile change l'empreinte

    @Test func eachSignalChangesTheFingerprint() {
        let reference = fp(base())
        let changes: [(String, (inout NetworkSignals) -> Void)] = [
            ("interface principale (Wi-Fi vers Ethernet)", { $0.primaryInterface = "en5" }),
            ("plus d'interface principale", { $0.primaryInterface = nil }),
            ("passerelle par défaut", { $0.primaryRouter = "192.0.2.254" }),
            ("interface principale IPv6", { $0.primaryInterface6 = "en0" }),
            ("passerelle IPv6", { $0.primaryRouter6 = "fe80::1" }),
            ("service : interface", { $0.services[0].interface = "en1" }),
            ("service : adresse", { $0.services[0].addresses = ["192.0.2.25"] }),
            ("service : routeur", { $0.services[0].router = "192.0.2.2" }),
            ("service : signature du réseau (MAC du routeur : deux réseaux en 192.0.2.x)",
             { $0.services[0].networkSignature = "IPv4.Router=192.0.2.1;IPv4.RouterHardwareAddress=dd:ee:ff:33:44:55" }),
            ("service : signature absente", { $0.services[0].networkSignature = nil }),
            ("un service de plus", { $0.services.append(.init(interface: "utun4", addresses: ["198.51.100.2"], router: "198.51.100.2", networkSignature: nil)) }),
            ("serveur DNS (saut de serveur VPN)", { $0.dnsServers = ["198.51.100.1"] }),
            ("un serveur DNS de plus", { $0.dnsServers.append("198.51.100.1") }),
            ("domaine DNS", { $0.dnsDomain = "corp.example" }),
            ("domaines de recherche", { $0.dnsSearchDomains = ["home", "corp.example"] }),
            ("un tunnel apparaît", { $0.tunnels = [.init(name: "utun4", address: "198.51.100.2")] }),
        ]
        for (label, change) in changes {
            var signals = base()
            change(&signals)
            #expect(fp(signals) != reference, "sans effet sur l'empreinte : \(label)")
        }
    }

    @Test func aTunnelThatKeepsItsInterfaceButChangesItsAddressChangesTheFingerprint() {
        var a = base(), b = base()
        a.tunnels = [.init(name: "utun4", address: "198.51.100.2")]
        b.tunnels = [.init(name: "utun4", address: "198.51.100.9")]
        #expect(fp(a) != fp(b))
        b.tunnels = [.init(name: "utun5", address: "198.51.100.2")]
        #expect(fp(a) != fp(b))
    }

    @Test func theLegacyPartsStillChangeTheFingerprint() {
        let s = base()
        #expect(fp(s, localIP: "192.0.2.24") != fp(s, localIP: "192.0.2.99"))
        #expect(fp(s) != fp(s, vpn: VPNStatus(mode: .full, name: "WireGuard", interface: "utun4")))
    }

    // MARK: Le bruit ne change rien

    @Test func theBuilderKeepsOnlyTheSignalsAndIgnoresTheNoise() {
        let global4: [String: Any] = ["PrimaryInterface": "en0", "PrimaryService": "UUID-A", "Router": "192.0.2.1"]
        let dns: [String: Any] = [
            "ServerAddresses": ["192.0.2.1"], "DomainName": "home", "SearchDomains": ["home"],
            "SearchOrder": 104_200, "__CONFIGURATION_ID__": "Supplemental: UUID-A 0", "__FLAGS__": 16_386, "__IF_INDEX__": 30, "__ORDER__": 0,
        ]
        let service: [String: Any] = [
            "InterfaceName": "en0", "Addresses": ["192.0.2.24"], "Router": "192.0.2.1",
            "NetworkSignature": "IPv4.Router=192.0.2.1;IPv4.RouterHardwareAddress=aa:bb:cc:00:11:22",
            "SubnetMasks": ["255.255.255.0"], "ConfirmedInterfaceName": "en0",
            "ARPResolvedHardwareAddress": "aa:bb:cc:00:11:22", "ARPResolvedIPAddress": "192.0.2.1",
            "AdditionalRoutes": [["DestinationAddress": "192.0.2.24", "SubnetMask": "255.255.255.255"]],
            "NetworkSignatureHash": Data([1, 2, 3]),
        ]
        let quiet = NetworkSignals.make(global4: global4, global6: nil, dns: dns, services: [service], tunnels: [])
        #expect(quiet == base())

        // Même chose avec du bruit qui change : un autre renouvellement de bail, un autre ordre interne, d'autres routes additionnelles.
        var noisyDNS = dns
        noisyDNS["__CONFIGURATION_ID__"] = "Supplemental: UUID-B 7"
        noisyDNS["__IF_INDEX__"] = 31
        var noisyService = service
        noisyService["AdditionalRoutes"] = []
        noisyService["NetworkSignatureHash"] = Data([9, 9, 9])
        noisyService["SubnetMasks"] = ["255.255.0.0"]
        var noisyGlobal = global4
        noisyGlobal["PrimaryService"] = "UUID-B"
        let noisy = NetworkSignals.make(global4: noisyGlobal, global6: nil, dns: noisyDNS, services: [noisyService], tunnels: [])
        #expect(fp(noisy) == fp(quiet))
    }

    @Test func theOrderOfServicesAndTunnelsDoesNotMatter() {
        let wifi: [String: Any] = ["InterfaceName": "en0", "Addresses": ["192.0.2.24"], "Router": "192.0.2.1"]
        let vpn: [String: Any] = ["InterfaceName": "utun4", "Addresses": ["198.51.100.2"], "Router": "198.51.100.2"]
        let t1 = NetworkSignals.Tunnel(name: "utun4", address: "198.51.100.2"), t2 = NetworkSignals.Tunnel(name: "utun6", address: "203.0.113.5")
        let a = NetworkSignals.make(global4: nil, global6: nil, dns: nil, services: [wifi, vpn], tunnels: [t1, t2])
        let b = NetworkSignals.make(global4: nil, global6: nil, dns: nil, services: [vpn, wifi], tunnels: [t2, t1])
        #expect(a == b)
        #expect(fp(a) == fp(b))
    }

    @Test func noMeasureThatMovesAllTheTimeCanReachTheFingerprint() throws {
        // Une garde de source : ni la force du signal Wi-Fi, ni le bruit, ni les compteurs d'octets, ni le BSSID (il change quand on
        // passe d'une borne à l'autre du même réseau, sans que l'IP publique bouge) ne sont lus par le fichier des signaux.
        let source = try String(contentsOf: RepositoryRoot.url().appendingPathComponent("Sources/Soaro/Samplers/NetworkSignals.swift"), encoding: .utf8)
        for word in ["rssi", "noise", "ifi_ibytes", "ifi_obytes", "downRate", "upRate", "txRate", "BSSID", "bssid"] {
            #expect(!source.contains(word), "NetworkSignals.swift mentionne \(word)")
        }
        let policy = try String(contentsOf: RepositoryRoot.url().appendingPathComponent("Sources/Soaro/Samplers/PublicIPLookupPolicy.swift"), encoding: .utf8)
        for word in ["rssi", "downRate", "upRate", "txRate"] {
            #expect(!policy.contains(word), "PublicIPLookupPolicy.swift mentionne \(word)")
        }
    }

    // MARK: Forme réelle des dictionnaires

    @Test func theBuilderReadsTheShapeMacOSPublishes() {
        // Forme relevée sur un Mac le 2026-11-18 (VPN actif : l'interface principale est le tunnel, le Wi-Fi reste sous-jacent), valeurs inventées.
        let global4: [String: Any] = ["PrimaryInterface": "utun4", "PrimaryService": "UUID-VPN", "Router": "198.51.100.2"]
        let dns: [String: Any] = ["ServerAddresses": ["198.51.100.1"], "SearchOrder": 104_200, "__CONFIGURATION_ID__": "Supplemental: UUID-VPN 0"]
        let wifi: [String: Any] = [
            "InterfaceName": "en0", "Addresses": ["192.0.2.137"], "Router": "192.0.2.254",
            "NetworkSignature": "IPv4.Router=192.0.2.254;IPv4.RouterHardwareAddress=aa:bb:cc:00:11:22",
            "ARPResolvedHardwareAddress": "aa:bb:cc:00:11:22",
        ]
        let vpn: [String: Any] = ["InterfaceName": "utun4", "Addresses": ["198.51.100.2"], "Router": "198.51.100.2", "ServerAddress": "127.0.0.1"]
        let s = NetworkSignals.make(global4: global4, global6: nil, dns: dns, services: [vpn, wifi],
                                    tunnels: [.init(name: "utun4", address: "198.51.100.2")])
        #expect(s.primaryInterface == "utun4")
        #expect(s.primaryRouter == "198.51.100.2")
        #expect(s.primaryInterface6 == nil)
        #expect(s.dnsServers == ["198.51.100.1"])
        #expect(s.dnsDomain == nil)
        #expect(s.dnsSearchDomains.isEmpty)
        #expect(s.services.map(\.interface) == ["en0", "utun4"], "triés par interface")
        #expect(s.services[0].networkSignature == "IPv4.Router=192.0.2.254;IPv4.RouterHardwareAddress=aa:bb:cc:00:11:22")
        #expect(s.services[1].networkSignature == nil)
        #expect(s.tunnels == [.init(name: "utun4", address: "198.51.100.2")])
    }

    @Test func missingOrMalformedDictionariesGiveEmptySignals() {
        #expect(NetworkSignals.make(global4: nil, global6: nil, dns: nil, services: [], tunnels: []) == .empty)
        let odd: [String: Any] = ["PrimaryInterface": 42, "Router": ["x"], "ServerAddresses": "not an array", "Addresses": 7]
        #expect(NetworkSignals.make(global4: odd, global6: odd, dns: odd, services: [odd], tunnels: []).primaryInterface == nil)
        // Un service sans nom d'interface est ignoré : il ne dit rien d'utile.
        #expect(NetworkSignals.make(global4: nil, global6: nil, dns: nil, services: [odd], tunnels: []).services.isEmpty)
    }

    // MARK: Lecture réelle (sans réseau, sans autorisation)

    @Test func theRealReaderRunsAndReturnsOnlyWhatItShouldWithoutAnyPermission() {
        let s = NetworkSignalsReader.read()
        for tunnel in s.tunnels { #expect(VPNDetector.isTunnel(tunnel.name), "\(tunnel.name) n'est pas un tunnel") }
        if let primary = s.primaryInterface { #expect(!primary.isEmpty) }
        #expect(s.services.map(\.interface) == s.services.map(\.interface).sorted(), "triés")
        // Le fichier ne demande aucune autorisation : ni CoreWLAN, ni CoreLocation.
    }

    @Test func theReaderAsksForNoPermissionAndOpensNoConnection() throws {
        let source = try String(contentsOf: RepositoryRoot.url().appendingPathComponent("Sources/Soaro/Samplers/NetworkSignals.swift"), encoding: .utf8)
        for word in ["CoreWLAN", "CoreLocation", "CLLocationManager", "URLSession", "NWConnection", "NWPathMonitor", "Process(", "UserDefaults", "FileManager"] {
            #expect(!source.contains(word), "NetworkSignals.swift mentionne \(word)")
        }
        #expect(source.contains("SCDynamicStoreCopyMultiple"))
    }
}
