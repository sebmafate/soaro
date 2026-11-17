import Foundation
import Testing
@testable import Soaro

/// R7 et ADR 0006 sur un faux dossier `.nuget` dans le bac à sable `.soaro-test-<uuid>` : jamais le vrai `~/.nuget`.
@Suite struct NuGetCleanupTests {
    private func fileBytes(_ url: URL) -> UInt64 { CleanupService.allocatedSize(of: url) }

    @Test func happyPathFreesTheMeasuredSizeAndKeepsTheFolderAndTheConfiguration() throws {
        let box = try Sandbox(insideHome: true)
        try box.file(".nuget/packages/newtonsoft.json/13.0.3/lib/a.dll", bytes: 300_000)
        try box.file(".nuget/packages/serilog/3.1.1/b.dll", bytes: 120_000)
        try box.file(".nuget/NuGet/NuGet.Config", bytes: 200)
        let expected = fileBytes(box.root.appendingPathComponent(".nuget/packages"))
        #expect(expected >= 420_000)

        let result = CleanupService.clean(.nugetCache, home: box.root)

        #expect(result.freed == expected)
        #expect(result.failures == 0)
        #expect(result.error == nil)
        #expect(box.exists(".nuget/packages"))
        let left = try FileManager.default.contentsOfDirectory(atPath: box.root.appendingPathComponent(".nuget/packages").path)
        #expect(left.isEmpty)
        #expect(box.exists(".nuget/NuGet/NuGet.Config"))
    }

    @Test func aFailurePartwayCountsWhatWasReallyRemoved() throws {
        let box = try Sandbox(insideHome: true)
        try box.file(".nuget/packages/a/1.0/locked/inside.bin", bytes: 50_000)
        try box.file(".nuget/packages/a/1.0/free.bin", bytes: 3_000_000)
        // `removeItem` s'arrête à la première erreur, dans l'ordre de lecture du dossier : plusieurs fichiers libres
        // pour qu'au moins un précède « locked » (l'ordre est celui du système de fichiers, on le vérifie plus bas).
        for i in 0..<30 { try box.file(".nuget/packages/a/1.0/free-\(i).bin", bytes: 100_000) }
        try box.file(".nuget/packages/b/1.0/c.dll", bytes: 400_000)
        let locked = box.root.appendingPathComponent(".nuget/packages/a/1.0/locked")
        let a = box.root.appendingPathComponent(".nuget/packages/a")
        let b = box.root.appendingPathComponent(".nuget/packages/b")
        let aBefore = fileBytes(a)
        let bBefore = fileBytes(b)

        let order = try FileManager.default.contentsOfDirectory(atPath: box.root.appendingPathComponent(".nuget/packages/a/1.0").path)
        try #require(order.first != "locked", "ordre de lecture du dossier inattendu sur ce volume : le test ne prouverait rien")

        // Dossier en lecture seule : sa suppression échoue. Les droits sont rendus avant le nettoyage du bac à sable.
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: locked.path) }

        let result = CleanupService.clean(.nugetCache, home: box.root)
        let aAfter = fileBytes(a)

        #expect(result.failures == 1)
        #expect(!box.exists(".nuget/packages/b"))
        #expect(box.exists(".nuget/packages/a/1.0/locked/inside.bin"))
        #expect(aAfter < aBefore, "une partie de « a » a bien été supprimée")
        #expect(result.freed == bBefore + (aBefore - aAfter))
        #expect(result.freed > bBefore)
    }

    /// Un `packages` qui est un lien vers l'extérieur : `contentsOfDirectory(at:)` ne suit pas le lien, le dossier est
    /// « inaccessible » ; si un jour il le suivait, `isSafeToDelete` refuserait chaque élément. Dans les deux cas rien n'est supprimé.
    @Test func aSymlinkedPackagesFolderPointingOutsideTheHomeDeletesNothing() throws {
        let home = try Sandbox(insideHome: true)
        let outside = try Sandbox()
        let target = try outside.file("victim/precious.bin", bytes: 50_000)
        try home.dir(".nuget")
        try FileManager.default.createSymbolicLink(
            at: home.root.appendingPathComponent(".nuget/packages"), withDestinationURL: outside.root)

        let result = CleanupService.clean(.nugetCache, home: home.root)

        #expect(result.error != nil || result.failures == 1)
        #expect(result.freed == 0)
        #expect(FileManager.default.fileExists(atPath: target.path))
    }

    @Test func aSymlinkedPackagePointingOutsideNeverTouchesItsTarget() throws {
        let home = try Sandbox(insideHome: true)
        let outside = try Sandbox()
        let target = try outside.file("precious.bin", bytes: 50_000)
        try home.file(".nuget/packages/ok/1.0/x.dll", bytes: 20_000)
        try FileManager.default.createSymbolicLink(
            at: home.root.appendingPathComponent(".nuget/packages/evil"), withDestinationURL: outside.root)

        let result = CleanupService.clean(.nugetCache, home: home.root)

        #expect(FileManager.default.fileExists(atPath: target.path))
        #expect(!home.exists(".nuget/packages/ok"))
        #expect(result.failures == 1)                 // le lien est refusé : sa cible est hors du dossier personnel
        #expect(result.freed > 0)                      // « ok » a bien été supprimé
    }

    @Test func aMissingFolderReportsItAndFreesNothing() throws {
        let box = try Sandbox(insideHome: true)
        let result = CleanupService.clean(.nugetCache, home: box.root)
        #expect(result.error == "Folder not accessible")
        #expect(result.freed == 0)
    }

    @Test func existingKindsStillFreeTheirFullSize() throws {
        let box = try Sandbox(insideHome: true)
        try box.file(".npm/_cacache/content-v2/a", bytes: 70_000)
        let before = try #require(CleanupService.size(of: .npmCache, home: box.root))
        let result = CleanupService.clean(.npmCache, home: box.root)
        #expect(result.freed == before)
        #expect(result.failures == 0)
    }
}
