import Foundation
import Testing
@testable import Soaro

/// Contrat avec `xcrun simctl list devices -j`.
///
/// Le fixture ci-dessous est ANONYMISÉ À LA MAIN à partir d'un enregistrement réel (lecture seule, hors dépôt, supprimé) :
/// les clés, la structure et le format exact des dates sont ceux du vrai outil ; les identifiants, noms et chemins sont inventés
/// (`/Users/test`, UDID fabriqués `00000000-0000-4000-8000-00000000000N`).
/// Le vrai enregistrement ne contenait que des appareils `Shutdown` et disponibles : l'appareil `Booted`, l'appareil indisponible
/// (clé `availabilityError`) et l'environnement non iOS ont été ajoutés à la main d'après le format connu de simctl.
/// Instant de référence des dates du fixture : 2026-11-16T12:00:00Z.
enum SimulatorFixture {
    static let now = ISO8601DateFormatter().date(from: "2026-11-16T12:00:00Z")!

    static let json = """
    {
      "devices" : {
        "com.apple.CoreSimulator.SimRuntime.iOS-18-1" : [

        ],
        "com.apple.CoreSimulator.SimRuntime.iOS-26-2" : [
          {
            "dataPath" : "/Users/test/Library/Developer/CoreSimulator/Devices/00000000-0000-4000-8000-000000000001/data",
            "dataPathSize" : 1900000001,
            "logPath" : "/Users/test/Library/Logs/CoreSimulator/00000000-0000-4000-8000-000000000001",
            "udid" : "00000000-0000-4000-8000-000000000001",
            "lastUsedAt" : "2026-11-16T09:00:00Z",
            "isAvailable" : true,
            "deviceTypeIdentifier" : "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro",
            "state" : "Booted",
            "name" : "iPhone 17 Pro"
          },
          {
            "dataPath" : "/Users/test/Library/Developer/CoreSimulator/Devices/00000000-0000-4000-8000-000000000002/data",
            "dataPathSize" : 842000001,
            "logPath" : "/Users/test/Library/Logs/CoreSimulator/00000000-0000-4000-8000-000000000002",
            "udid" : "00000000-0000-4000-8000-000000000002",
            "lastUsedAt" : "2026-10-01T08:30:15Z",
            "isAvailable" : true,
            "deviceTypeIdentifier" : "com.apple.CoreSimulator.SimDeviceType.iPad-Air-11-inch-M3",
            "state" : "Shutdown",
            "name" : "iPad Air 11-inch"
          },
          {
            "dataPath" : "/Users/test/Library/Developer/CoreSimulator/Devices/00000000-0000-4000-8000-000000000003/data",
            "dataPathSize" : 18000001,
            "logPath" : "/Users/test/Library/Logs/CoreSimulator/00000000-0000-4000-8000-000000000003",
            "udid" : "00000000-0000-4000-8000-000000000003",
            "isAvailable" : true,
            "deviceTypeIdentifier" : "com.apple.CoreSimulator.SimDeviceType.iPhone-17",
            "state" : "Shutdown",
            "name" : "iPhone 17"
          },
          {
            "dataPath" : "/Users/test/Library/Developer/CoreSimulator/Devices/00000000-0000-4000-8000-000000000004/data",
            "dataPathSize" : 5000001,
            "logPath" : "/Users/test/Library/Logs/CoreSimulator/00000000-0000-4000-8000-000000000004",
            "udid" : "00000000-0000-4000-8000-000000000004",
            "lastUsedAt" : "2026-06-20T17:45:00Z",
            "isAvailable" : false,
            "availabilityError" : "runtime profile not found",
            "deviceTypeIdentifier" : "com.apple.CoreSimulator.SimDeviceType.iPhone-16",
            "state" : "Shutdown",
            "name" : "iPhone 16"
          }
        ],
        "com.apple.CoreSimulator.SimRuntime.iOS-18-0" : [
          {
            "dataPath" : "/Users/test/Library/Developer/CoreSimulator/Devices/00000000-0000-4000-8000-000000000005/data",
            "dataPathSize" : 3200000001,
            "logPath" : "/Users/test/Library/Logs/CoreSimulator/00000000-0000-4000-8000-000000000005",
            "udid" : "00000000-0000-4000-8000-000000000005",
            "lastUsedAt" : "2026-08-10T10:00:00Z",
            "isAvailable" : true,
            "deviceTypeIdentifier" : "com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro",
            "state" : "Shutdown",
            "name" : "iPhone 16 Pro"
          },
          {
            "dataPath" : "/Users/test/Library/Developer/CoreSimulator/Devices/00000000-0000-4000-8000-000000000006/data",
            "dataPathSize" : 2100000001,
            "logPath" : "/Users/test/Library/Logs/CoreSimulator/00000000-0000-4000-8000-000000000006",
            "udid" : "00000000-0000-4000-8000-000000000006",
            "lastUsedAt" : "2026-11-02T14:20:00Z",
            "isAvailable" : true,
            "deviceTypeIdentifier" : "com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro",
            "state" : "Shutdown",
            "name" : "iPhone 16 Pro"
          }
        ],
        "com.apple.CoreSimulator.SimRuntime.watchOS-26-0" : [
          {
            "dataPath" : "/Users/test/Library/Developer/CoreSimulator/Devices/00000000-0000-4000-8000-000000000007/data",
            "dataPathSize" : 104000001,
            "logPath" : "/Users/test/Library/Logs/CoreSimulator/00000000-0000-4000-8000-000000000007",
            "udid" : "00000000-0000-4000-8000-000000000007",
            "lastUsedAt" : "2026-07-04T06:10:00Z",
            "isAvailable" : true,
            "deviceTypeIdentifier" : "com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Series-11-46mm",
            "state" : "Shutdown",
            "name" : "Apple Watch Series 11 (46mm)"
          }
        ]
      }
    }
    """

    static func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
}

@Suite struct SimulatorParsingTests {
    private func parse(_ text: String) -> [SimulatorDevice]? { SimulatorScanner.parse(Data(text.utf8)) }
    private func device(_ id: Int, in list: [SimulatorDevice]) -> SimulatorDevice? {
        list.first { $0.udid == "00000000-0000-4000-8000-00000000000\(id)" }
    }

    // MARK: Contrat (fixture anonymisé)

    @Test func readsAllSevenDevicesOfTheContractFixture() throws {
        let list = try #require(parse(SimulatorFixture.json))
        #expect(list.count == 7)
        #expect(Set(list.map(\.udid)).count == 7)
    }

    @Test func readsTheFieldsOfABootedDevice() throws {
        let list = try #require(parse(SimulatorFixture.json))
        let booted = try #require(device(1, in: list))
        #expect(booted.name == "iPhone 17 Pro")
        #expect(booted.state == "Booted")
        #expect(booted.isAvailable)
        #expect(booted.modelIdentifier == "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro")
        #expect(booted.runtimeIdentifier == "com.apple.CoreSimulator.SimRuntime.iOS-26-2")
        #expect(booted.runtimeName == "iOS 26.2")
        #expect(booted.lastUsed == SimulatorFixture.date("2026-11-16T09:00:00Z"))
    }

    @Test func readsShutdownUnavailableUndatedAndNonIOSDevices() throws {
        let list = try #require(parse(SimulatorFixture.json))
        #expect(device(2, in: list)?.state == "Shutdown")
        #expect(device(2, in: list)?.lastUsed == SimulatorFixture.date("2026-10-01T08:30:15Z"))
        #expect(device(3, in: list)?.lastUsed == nil, "un appareil sans lastUsedAt n'a pas de date")
        #expect(device(4, in: list)?.isAvailable == false)
        #expect(device(7, in: list)?.runtimeName == "watchOS 26.0")
        #expect(device(5, in: list)?.runtimeName == "iOS 18.0")
    }

    @Test func theDuplicatePairKeepsBothEntriesWithTheirOwnDates() throws {
        let list = try #require(parse(SimulatorFixture.json))
        let a = try #require(device(5, in: list)), b = try #require(device(6, in: list))
        #expect(a.modelIdentifier == b.modelIdentifier)
        #expect(a.runtimeIdentifier == b.runtimeIdentifier)
        #expect(a.lastUsed != b.lastUsed)
    }

    @Test func orderIsDeterministicWhateverTheDictionaryOrder() throws {
        let first = try #require(parse(SimulatorFixture.json))
        for _ in 0..<5 { #expect(parse(SimulatorFixture.json) == first) }
        #expect(first.map(\.runtimeIdentifier) == first.map(\.runtimeIdentifier).sorted())
    }

    // MARK: Illisible, mais jamais de plantage

    @Test func brokenOrNonObjectInputIsUnreadable() {
        #expect(SimulatorScanner.parse(Data()) == nil)
        #expect(parse("") == nil)
        #expect(parse("{ \"devices\" : { ") == nil)
        #expect(parse("not json at all") == nil)
        #expect(SimulatorScanner.parse(Data([0xFF, 0xFE, 0x00, 0x80])) == nil)
        #expect(parse("[1, 2, 3]") == nil)
        #expect(parse("\"devices\"") == nil)
        #expect(parse("null") == nil)
    }

    @Test func missingOrWrongTypedDevicesKeyIsUnreadable() {
        #expect(parse("{}") == nil)
        #expect(parse("{\"other\": {}}") == nil)
        #expect(parse("{\"devices\": []}") == nil)
        #expect(parse("{\"devices\": 3}") == nil)
    }

    @Test func emptyDevicesIsAValidEmptyList() {
        #expect(parse("{\"devices\": {}}") == [])
        #expect(parse("{\"devices\": {\"com.apple.CoreSimulator.SimRuntime.iOS-26-2\": []}}") == [])
    }

    // MARK: Tolérance

    private func one(_ fields: String, runtime: String = "com.apple.CoreSimulator.SimRuntime.iOS-26-2") -> String {
        "{\"devices\": {\"\(runtime)\": [{\(fields)}]}}"
    }
    private let udid = "\"udid\": \"00000000-0000-4000-8000-000000000001\""

    @Test func unknownExtraKeysAreIgnored() throws {
        let list = try #require(parse(one("\(udid), \"name\": \"X\", \"state\": \"Shutdown\", \"futureKey\": {\"a\": [1, 2]}, \"anotherOne\": 7")))
        #expect(list.count == 1)
    }

    @Test func missingOptionalKeysAreTolerated() throws {
        let list = try #require(parse(one(udid)))
        let d = try #require(list.first)
        #expect(d.modelIdentifier == nil)
        #expect(d.lastUsed == nil)
        #expect(d.isAvailable)
        #expect(d.name == "")
        #expect(d.state != "Shutdown", "état inconnu : traité comme en cours d'exécution plus tard, jamais comme arrêté")
    }

    @Test func entryWithoutAValidUDIDIsSkippedOthersAreKept() throws {
        let bad = ["", "\"udid\": 5", "\"udid\": \"\"", "\"udid\": \"not-a-uuid\"",
                   "\"udid\": \"../../../../tmp\"", "\"udid\": \"00000000-0000-4000-8000-000000000001/../x\"",
                   "\"udid\": \"00000000-0000-4000-8000-00000000000\"", "\"udid\": \"0000000000000000000000000000000000000\"",
                   "\"name\": \"no udid\""]
        for field in bad {
            let json = "{\"devices\": {\"r\": [{\(field)}, {\(udid), \"name\": \"ok\"}]}}"
            let list = try #require(parse(json), "\(field)")
            #expect(list.map(\.name) == ["ok"], "\(field)")
        }
    }

    @Test func entriesThatAreNotObjectsAreSkipped() throws {
        let list = try #require(parse("{\"devices\": {\"r\": [1, \"x\", null, {\(udid)}], \"s\": \"oops\"}}"))
        #expect(list.count == 1)
    }

    @Test func aLowerCaseUDIDIsAccepted() throws {
        let list = try #require(parse(one("\"udid\": \"abcdef00-0000-4000-8000-00000000000a\"")))
        #expect(list.count == 1)
    }

    @Test func aDuplicatedUDIDIsKeptOnce() throws {
        let json = "{\"devices\": {\"r\": [{\(udid)}, {\(udid)}]}}"
        #expect(parse(json)?.count == 1)
    }

    // MARK: Dates

    @Test func datesWithAndWithoutFractionalSecondsAreAccepted() throws {
        let plain = try #require(parse(one("\(udid), \"lastUsedAt\": \"2026-11-05T08:11:22Z\"")))
        #expect(plain.first?.lastUsed == SimulatorFixture.date("2026-11-05T08:11:22Z"))

        let fractional = try #require(parse(one("\(udid), \"lastUsedAt\": \"2026-11-05T08:11:22.250Z\"")))
        let value = try #require(fractional.first?.lastUsed)
        #expect(abs(value.timeIntervalSince(SimulatorFixture.date("2026-11-05T08:11:22Z")) - 0.25) < 0.001)
    }

    @Test func anUnparsableDateMeansNoDate() throws {
        for text in ["yesterday", "", "2026-13-45T99:99:99Z", "1700000000"] {
            let list = try #require(parse(one("\(udid), \"lastUsedAt\": \"\(text)\"")), "\(text)")
            #expect(list.first?.lastUsed == nil, "«\(text)»")
        }
        let notAString = try #require(parse(one("\(udid), \"lastUsedAt\": 1700000000")))
        #expect(notAString.first?.lastUsed == nil)
    }

    @Test func lastUsedAtWinsAndLastBootedAtIsTheOnlyFallback() throws {
        let both = try #require(parse(one("\(udid), \"lastUsedAt\": \"2026-11-05T08:11:22Z\", \"lastBootedAt\": \"2026-01-01T00:00:00Z\"")))
        #expect(both.first?.lastUsed == SimulatorFixture.date("2026-11-05T08:11:22Z"))
        let onlyBooted = try #require(parse(one("\(udid), \"lastBootedAt\": \"2026-01-01T00:00:00Z\"")))
        #expect(onlyBooted.first?.lastUsed == SimulatorFixture.date("2026-01-01T00:00:00Z"))
        // lastUsedAt présent mais illisible : pas de repli (l'absence seule autorise le repli).
        let broken = try #require(parse(one("\(udid), \"lastUsedAt\": \"junk\", \"lastBootedAt\": \"2026-01-01T00:00:00Z\"")))
        #expect(broken.first?.lastUsed == nil)
    }

    // MARK: Noms d'environnement

    @Test func runtimeNamesAreReadableOrFallBackToTheRawIdentifier() {
        #expect(SimulatorScanner.runtimeName("com.apple.CoreSimulator.SimRuntime.iOS-26-2") == "iOS 26.2")
        #expect(SimulatorScanner.runtimeName("com.apple.CoreSimulator.SimRuntime.iOS-18-0") == "iOS 18.0")
        #expect(SimulatorScanner.runtimeName("com.apple.CoreSimulator.SimRuntime.tvOS-26-1") == "tvOS 26.1")
        #expect(SimulatorScanner.runtimeName("com.apple.CoreSimulator.SimRuntime.xrOS-2-0") == "xrOS 2.0")
        #expect(SimulatorScanner.runtimeName("com.apple.CoreSimulator.SimRuntime.iOS-17") == "iOS 17")
        #expect(SimulatorScanner.runtimeName("com.apple.CoreSimulator.SimRuntime.iOS-26-2-beta") == "com.apple.CoreSimulator.SimRuntime.iOS-26-2-beta")
        #expect(SimulatorScanner.runtimeName("something.else") == "something.else")
        #expect(SimulatorScanner.runtimeName("") == "")
    }

    @Test func theFixtureContainsNoPersonalPath() {
        #expect(!SimulatorFixture.json.contains("/Users/") || SimulatorFixture.json.components(separatedBy: "/Users/").dropFirst().allSatisfy { $0.hasPrefix("test/") })
    }
}
