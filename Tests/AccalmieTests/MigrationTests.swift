import Foundation
import Testing
@testable import Accalmie

@Suite struct LegacyMigrationTests {
    private func makeSupportDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("accalmie-migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeDefaults() -> (UserDefaults, () -> Void) {
        let name = "accalmie.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        return (defaults, { defaults.removePersistentDomain(forName: name) })
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func read(_ url: URL) -> String? {
        (try? Data(contentsOf: url)).map { String(decoding: $0, as: UTF8.self) }
    }

    // MARK: Dossier de données

    @Test func movesHistoryFilesTogether() throws {
        let support = try makeSupportDirectory()
        defer { try? FileManager.default.removeItem(at: support) }
        let old = support.appendingPathComponent("MyCleaner")
        for name in ["history.sqlite", "history.sqlite-wal", "history.sqlite-shm"] { try write(name, to: old.appendingPathComponent(name)) }

        let moved = LegacyMigration.moveFolder(from: old, to: support.appendingPathComponent("Accalmie"))

        #expect(moved == 3)
        for name in ["history.sqlite", "history.sqlite-wal", "history.sqlite-shm"] {
            #expect(read(support.appendingPathComponent("Accalmie/\(name)")) == name)
        }
        #expect(!FileManager.default.fileExists(atPath: old.path), "l'ancien dossier vide doit disparaître")
    }

    @Test func neverOverwritesExistingFiles() throws {
        let support = try makeSupportDirectory()
        defer { try? FileManager.default.removeItem(at: support) }
        let old = support.appendingPathComponent("MyCleaner")
        let new = support.appendingPathComponent("Accalmie")
        try write("ANCIEN", to: old.appendingPathComponent("history.sqlite"))
        try write("NOUVEAU", to: new.appendingPathComponent("history.sqlite"))
        try write("autre", to: old.appendingPathComponent("extra.txt"))

        let moved = LegacyMigration.moveFolder(from: old, to: new)

        #expect(moved == 1)
        #expect(read(new.appendingPathComponent("history.sqlite")) == "NOUVEAU")
        #expect(read(old.appendingPathComponent("history.sqlite")) == "ANCIEN", "ce qui n'a pas pu être déplacé reste en place")
        #expect(read(new.appendingPathComponent("extra.txt")) == "autre")
    }

    @Test func missingOrEmptyLegacyFolderIsANoOp() throws {
        let support = try makeSupportDirectory()
        defer { try? FileManager.default.removeItem(at: support) }
        #expect(LegacyMigration.moveFolder(from: support.appendingPathComponent("MyCleaner"), to: support.appendingPathComponent("Accalmie")) == 0)
        #expect(!FileManager.default.fileExists(atPath: support.appendingPathComponent("Accalmie").path), "pas de dossier créé pour rien")
    }

    // MARK: Préférences

    @Test func copiesOnlyKnownKeysAndKeepsExistingValues() {
        let (defaults, cleanup) = makeDefaults()
        defer { cleanup() }
        defaults.set(false, forKey: SettingsKey.notifications)           // l'utilisateur a déjà choisi dans la nouvelle version

        LegacyMigration.copyPreferences([
            SettingsKey.menuBarMemory: true,
            SettingsKey.notifications: true,
            "traffic.day": "2026-11-14",
            "traffic.down": 123.0,
            "NSWindow Frame Something": "ne doit pas passer",
        ], into: defaults)

        #expect(defaults.bool(forKey: SettingsKey.menuBarMemory))
        #expect(!defaults.bool(forKey: SettingsKey.notifications), "une valeur existante n'est jamais écrasée")
        #expect(defaults.string(forKey: "traffic.day") == "2026-11-14")
        #expect(defaults.double(forKey: "traffic.down") == 123)
        #expect(defaults.object(forKey: "NSWindow Frame Something") == nil, "les clés inconnues sont ignorées")
    }

    @Test func translatesTheFirstVersionMenuBarMode() {
        let cases: [(String, Bool, Bool)] = [("cpuAndMemory", true, true), ("cpu", true, false), ("memory", false, true), ("iconOnly", false, false)]
        for (mode, cpu, memory) in cases {
            let (defaults, cleanup) = makeDefaults()
            defer { cleanup() }
            LegacyMigration.copyPreferences(["menuBarMode": mode], into: defaults)
            #expect(defaults.bool(forKey: SettingsKey.menuBarCPU) == cpu, "\(mode) → CPU")
            #expect(defaults.bool(forKey: SettingsKey.menuBarMemory) == memory, "\(mode) → mémoire")
        }
    }

    @Test func recentMenuBarChoiceWinsOverTheFirstVersionMode() {
        let (defaults, cleanup) = makeDefaults()
        defer { cleanup() }
        // Cas réel : ancien mode « CPU + mémoire », puis case « mémoire » décochée dans la version suivante.
        LegacyMigration.copyPreferences(["menuBarMode": "cpuAndMemory", SettingsKey.menuBarMemory: false], into: defaults)
        #expect(defaults.bool(forKey: SettingsKey.menuBarCPU))
        #expect(!defaults.bool(forKey: SettingsKey.menuBarMemory))
        LegacyMigration.copyPreferences(["menuBarMode": "bogus"], into: defaults)           // valeur inconnue : ignorée
    }

    // MARK: Ensemble

    @Test func runIsIdempotent() throws {
        let support = try makeSupportDirectory()
        defer { try? FileManager.default.removeItem(at: support) }
        let (defaults, cleanup) = makeDefaults()
        defer { cleanup() }
        try write("v1", to: support.appendingPathComponent("MyCleaner/history.sqlite"))

        LegacyMigration.run(supportDirectory: support, defaults: defaults, legacyPreferences: [SettingsKey.menuBarGPU: true])
        #expect(defaults.bool(forKey: LegacyMigration.doneFlag))
        #expect(read(support.appendingPathComponent("Accalmie/history.sqlite")) == "v1")
        #expect(defaults.bool(forKey: SettingsKey.menuBarGPU))

        // Deuxième lancement : une ancienne version qui réapparaîtrait ne doit plus rien écraser.
        try write("v2-ancien", to: support.appendingPathComponent("MyCleaner/history.sqlite"))
        defaults.set(false, forKey: SettingsKey.menuBarGPU)
        LegacyMigration.run(supportDirectory: support, defaults: defaults, legacyPreferences: [SettingsKey.menuBarGPU: true])

        #expect(read(support.appendingPathComponent("Accalmie/history.sqlite")) == "v1")
        #expect(!defaults.bool(forKey: SettingsKey.menuBarGPU))
        #expect(read(support.appendingPathComponent("MyCleaner/history.sqlite")) == "v2-ancien", "après migration, l'ancien dossier n'est plus touché")
    }

    @Test func freshInstallJustSetsTheFlag() throws {
        let support = try makeSupportDirectory()
        defer { try? FileManager.default.removeItem(at: support) }
        let (defaults, cleanup) = makeDefaults()
        defer { cleanup() }

        LegacyMigration.run(supportDirectory: support, defaults: defaults, legacyPreferences: nil)

        #expect(defaults.bool(forKey: LegacyMigration.doneFlag))
        #expect((try? FileManager.default.contentsOfDirectory(atPath: support.path))?.isEmpty == true)
    }
}
