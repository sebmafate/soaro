import Foundation
import Testing
@testable import Soaro

@Suite struct FlagTests {
    @Test func buildsRegionalIndicatorFlags() {
        #expect(PublicIPService.flagEmoji("FR") == "🇫🇷")
        #expect(PublicIPService.flagEmoji("ch") == "🇨🇭")
        #expect(PublicIPService.flagEmoji("US") == "🇺🇸")
    }

    @Test func rejectsAnythingThatIsNotATwoLetterCode() {
        #expect(PublicIPService.flagEmoji(nil) == nil)
        #expect(PublicIPService.flagEmoji("") == nil)
        #expect(PublicIPService.flagEmoji("FRA") == nil)
        #expect(PublicIPService.flagEmoji("1F") == nil)
        #expect(PublicIPService.flagEmoji("é!") == nil)
    }
}

@Suite struct PublicIPParsingTests {
    private func data(_ json: String) -> Data { Data(json.utf8) }

    @Test func parsesIpwhoIs() throws {
        let info = try #require(PublicIPService.parse(data("""
        {"ip":"146.70.194.122","success":true,"type":"IPv4","country":"France","country_code":"FR",
         "city":"Paris","connection":{"asn":9009,"org":"M247 LTD Paris Infrastructure","isp":"M247 Europe SRL"}}
        """)))
        #expect(info.ip == "146.70.194.122")
        #expect(info.countryCode == "FR" && info.country == "France" && info.city == "Paris")
        #expect(info.provider == "M247 Europe SRL")
        #expect(info.flag == "🇫🇷")
    }

    @Test func parsesIpapiCo() throws {
        let info = try #require(PublicIPService.parse(data("""
        {"ip":"2a02:8428::1","country":"FR","country_name":"France","country_code":"FR","city":"Paris","org":"Free SAS"}
        """)))
        #expect(info.ip == "2a02:8428::1")
        #expect(info.country == "France")                      // pas le code « FR »
        #expect(info.provider == "Free SAS")
    }

    @Test func rejectsFailuresAndGarbage() {
        #expect(PublicIPService.parse(data(#"{"success":false,"message":"rate limited"}"#)) == nil)
        #expect(PublicIPService.parse(data(#"{"error":true,"reason":"RateLimited"}"#)) == nil)
        #expect(PublicIPService.parse(data("<html>blocked</html>")) == nil)
        #expect(PublicIPService.parse(data(#"{"country_code":"FR"}"#)) == nil)         // pas d'IP
    }

    @Test func neverDisplaysANonIPValue() {
        // Un service compromis ne doit pas pouvoir injecter du texte à la place de l'adresse.
        #expect(PublicIPService.parse(data(#"{"ip":"Cliquez ici : http://evil.example","country_code":"FR"}"#)) == nil)
        #expect(PublicIPService.parse(data(#"{"ip":"999.1.1.1","country_code":"FR"}"#)) == nil)
        #expect(PublicIPService.isValidIP("192.168.1.1"))
        #expect(PublicIPService.isValidIP("::1"))
    }

    @Test func toleratesMissingOptionalFields() throws {
        let info = try #require(PublicIPService.parse(data(#"{"ip":"1.2.3.4","country_code":"zz9","city":""}"#)))
        #expect(info.countryCode == nil && info.flag == nil && info.city == nil && info.provider == nil)
    }
}

@Suite struct VPNDetectorTests {
    /// Sortie réelle de `scutil --nc list` (ProtonVPN connecté).
    private let scutil = """
    Available network connection services in the current set (*=enabled):
    * (Connected)      61FB4D37-0DE5-41F6-AC9F-849FB0ADC4D3 VPN (ch.protonvpn.mac) "ProtonVPN"                      [VPN:ch.protonvpn.mac]
    """

    @Test func parsesRealRouteAndScutilOutput() {
        let route = """
           route to: default
        destination: default
               mask: default
          interface: utun4
              flags: <UP,DONE,CLONING,STATIC,GLOBAL>
        """
        #expect(VPNDetector.parseDefaultInterface(route) == "utun4")
        #expect(VPNDetector.parseConnectedServices(scutil) == ["ProtonVPN"])
        #expect(VPNDetector.parseDefaultInterface("garbage") == nil)
    }

    @Test func disconnectedServicesAreIgnored() {
        let out = #"* (Disconnected)  AAAA VPN (com.x) "Work VPN"  [VPN:com.x]"#
        #expect(VPNDetector.parseConnectedServices(out).isEmpty)
    }

    @Test func fullTunnelWhenDefaultRouteIsATunnel() {
        let status = VPNDetector.analyze(defaultInterface: "utun4", connectedServices: ["ProtonVPN"], tunnelsWithAddress: ["utun4"], processNames: [])
        #expect(status == VPNStatus(mode: .full, name: "ProtonVPN", interface: "utun4"))
        #expect(status.isActive)
    }

    @Test func fullTunnelNamedFromRunningProcessWhenNotDeclaredInSystem() {
        let status = VPNDetector.analyze(defaultInterface: "utun3", connectedServices: [], tunnelsWithAddress: ["utun3"], processNames: ["Finder", "WireGuard-Extension"])
        #expect(status.mode == .full && status.name == "WireGuard")
    }

    @Test func unknownTunnelOnDefaultRouteIsStillFull() {
        let status = VPNDetector.analyze(defaultInterface: "utun9", connectedServices: [], tunnelsWithAddress: [], processNames: [])
        #expect(status.mode == .full && status.name == nil)
    }

    @Test func partialTunnelWhenDefaultRouteStaysOnWiFi() {
        let status = VPNDetector.analyze(defaultInterface: "en0", connectedServices: [], tunnelsWithAddress: ["utun5"], processNames: ["tailscaled"])
        #expect(status.mode == .partial && status.name == "Tailscale" && status.interface == "utun5")
    }

    @Test func appleSystemTunnelsDoNotTriggerFalsePositive() {
        // utun avec adresse mais aucun VPN connu en cours : pas de VPN.
        let status = VPNDetector.analyze(defaultInterface: "en0", connectedServices: [], tunnelsWithAddress: ["utun2"], processNames: ["Finder", "Safari"])
        #expect(status.mode == .off && !status.isActive)
    }

    @Test func noVPNOnPlainWiFi() {
        #expect(VPNDetector.analyze(defaultInterface: "en0", connectedServices: [], tunnelsWithAddress: [], processNames: []).mode == .off)
        #expect(VPNDetector.analyze(defaultInterface: nil, connectedServices: [], tunnelsWithAddress: [], processNames: []).mode == .off)
    }

    @Test func tunnelInterfaceDetection() {
        for name in ["utun0", "ipsec0", "ppp0", "tun0", "tap1"] { #expect(VPNDetector.isTunnel(name), "\(name)") }
        for name in ["en0", "lo0", "bridge0", "awdl0", "llw0"] { #expect(!VPNDetector.isTunnel(name), "\(name)") }
    }
}
