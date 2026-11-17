import Foundation
import Testing
@testable import Soaro

/// SL11, T1 : retrouver la cible au moment de l'action (lecture seule). Tout se passe dans le bac à sable `.soaro-test-<uuid>`
/// (jamais le vrai `~/.android`) ; rien n'est supprimé ici.
@Suite(.serialized) struct AndroidRemovalTargetTests {
    /// Écrit un AVD complet : `<name>.ini` et `<name>.avd/config.ini` ; renvoie le dossier `.avd`.
    @discardableResult
    private func makeAVD(_ box: Sandbox, name: String, display: String? = nil, registration: String? = nil) throws -> URL {
        try box.dir(".android/avd/\(name).avd")
        let ini = registration ?? "avd.ini.encoding=UTF-8\npath=\(box.root.path)/.android/avd/\(name).avd\npath.rel=avd/\(name).avd\ntarget=android-36\n"
        try box.write(".android/avd/\(name).ini", ini)
        var config = "AvdId=\(name)\n"
        if let display { config += "avd.ini.displayname=\(display)\n" }
        config += "image.sysdir.1=system-images/android-36/google_apis_playstore/arm64-v8a/\n"
        try box.write(".android/avd/\(name).avd/config.ini", config)
        return box.root.appendingPathComponent(".android/avd/\(name).avd")
    }

    private func realPath(_ url: URL) -> String { url.resolvingSymlinksInPath().standardizedFileURL.path }

    /// La cible telle que le scan la voit : le nom et le dossier de l'appareil listé.
    private func scanTarget(_ box: Sandbox, _ name: String) throws -> AndroidRemovalTarget {
        let device = try #require(AndroidEmulatorScanner.listAVDs(home: box.root).devices.first { $0.name == name })
        return AndroidRemovalTarget(name: device.name, folder: device.folder)
    }

    private func prepare(_ box: Sandbox, _ target: AndroidRemovalTarget) -> AndroidRemovalPreparation {
        AndroidEmulatorScanner.prepareRemoval(home: box.root, target: target)
    }

    // MARK: Cas nominal

    @Test func theNominalCaseGivesAPlanWithTheFolderAndTheOneRegistration() throws {
        let box = try Sandbox(insideHome: true)
        let folder = try makeAVD(box, name: "Test_Phone_A", display: "Test Phone A")
        let target = try scanTarget(box, "Test_Phone_A")

        guard case .plan(let plan) = prepare(box, target) else { Issue.record("un plan était attendu"); return }
        #expect(plan.displayName == "Test Phone A")
        #expect(plan.names == ["Test_Phone_A"])
        #expect(realPath(plan.folder) == realPath(folder))
        #expect(plan.registrations.map { realPath($0) } == [realPath(box.root.appendingPathComponent(".android/avd/Test_Phone_A.ini"))])
    }

    @Test func thePreparationDeletesAndWritesNothing() throws {
        let box = try Sandbox(insideHome: true)
        try makeAVD(box, name: "Test_Phone_A")
        let target = try scanTarget(box, "Test_Phone_A")
        _ = prepare(box, target)
        #expect(box.exists(".android/avd/Test_Phone_A.ini"))
        #expect(box.exists(".android/avd/Test_Phone_A.avd/config.ini"))
    }

    @Test func twoRegistrationsForOneFolderGiveBothInThePlanAndTheTargetIsFoundByTheAliasToo() throws {
        let box = try Sandbox(insideHome: true)
        let folder = try makeAVD(box, name: "Test_Phone_A", display: "Test Phone A")
        try box.write(".android/avd/Test_Phone_B.ini", "path=\(folder.path)\n")
        let target = try scanTarget(box, "Test_Phone_A")

        guard case .plan(let plan) = prepare(box, target) else { Issue.record("un plan était attendu"); return }
        #expect(plan.names == ["Test_Phone_A", "Test_Phone_B"])
        #expect(plan.registrations.map(\.lastPathComponent) == ["Test_Phone_A.ini", "Test_Phone_B.ini"])

        // Trouvée aussi sous le nom de l'alias : le même plan.
        let byAlias = AndroidRemovalTarget(name: "Test_Phone_B", folder: target.folder)
        guard case .plan(let other) = prepare(box, byAlias) else { Issue.record("un plan était attendu"); return }
        #expect(other.names == ["Test_Phone_A", "Test_Phone_B"])
        #expect(other.displayName == "Test Phone A")
    }

    // MARK: Déjà disparu, refusé

    @Test func bothTheRegistrationAndTheFolderRemovedAfterTheScanMeansAlreadyGone() throws {
        let box = try Sandbox(insideHome: true)
        try makeAVD(box, name: "Test_Phone_A")
        try makeAVD(box, name: "Test_Tablet_B")
        let target = try scanTarget(box, "Test_Phone_A")
        try FileManager.default.removeItem(at: box.root.appendingPathComponent(".android/avd/Test_Phone_A.ini"))
        try FileManager.default.removeItem(at: box.root.appendingPathComponent(".android/avd/Test_Phone_A.avd"))
        #expect(prepare(box, target) == .alreadyGone)
    }

    @Test func aMissingAvdFolderAndNoRegistrationAlsoMeansAlreadyGone() throws {
        let box = try Sandbox(insideHome: true)
        let target = AndroidRemovalTarget(name: "Test_Phone_A", folder: box.root.appendingPathComponent(".android/avd/Test_Phone_A.avd"))
        #expect(prepare(box, target) == .alreadyGone)
    }

    @Test func onlyTheFolderRemovedWhileTheRegistrationStaysIsRefused() throws {
        let box = try Sandbox(insideHome: true)
        try makeAVD(box, name: "Test_Phone_A")
        let target = try scanTarget(box, "Test_Phone_A")
        try FileManager.default.removeItem(at: box.root.appendingPathComponent(".android/avd/Test_Phone_A.avd"))
        #expect(prepare(box, target) == .refused)
        #expect(box.exists(".android/avd/Test_Phone_A.ini"))
    }

    @Test func aRegistrationRewrittenToPointOutsideTheHomeIsRefused() throws {
        let box = try Sandbox(insideHome: true)
        try makeAVD(box, name: "Test_Phone_A")
        let target = try scanTarget(box, "Test_Phone_A")
        // Un dossier AVD valide (avec `config.ini`) mais HORS du dossier personnel injecté.
        let outside = try Sandbox(insideHome: false)
        try outside.write("Elsewhere.avd/config.ini", "AvdId=Elsewhere\n")
        try box.write(".android/avd/Test_Phone_A.ini", "path=\(outside.root.path)/Elsewhere.avd\n")

        #expect(prepare(box, target) == .refused)
        #expect(outside.exists("Elsewhere.avd/config.ini"))
        #expect(box.exists(".android/avd/Test_Phone_A.avd/config.ini"))
    }

    @Test func aRegistrationPointingToAFolderThatIsNotAnAvdFolderIsRefused() throws {
        let box = try Sandbox(insideHome: true)
        try makeAVD(box, name: "Test_Phone_A")
        let target = try scanTarget(box, "Test_Phone_A")
        try box.write("Documents/note.txt", "x")
        try box.write(".android/avd/Test_Phone_A.ini", "path=\(box.root.path)/Documents\n")

        #expect(prepare(box, target) == .refused)
        #expect(box.exists("Documents/note.txt"))
    }

    @Test func theScanTimeFolderReplacedByASymlinkToAnotherAvdFolderIsRefused() throws {
        let box = try Sandbox(insideHome: true)
        let folder = try makeAVD(box, name: "Test_Phone_A")
        let target = try scanTarget(box, "Test_Phone_A")
        // Un autre dossier `*.avd` valide, dans le dossier personnel, sans inscription.
        try box.write("Other.avd/config.ini", "AvdId=Other\n")
        try FileManager.default.removeItem(at: folder)
        try FileManager.default.createSymbolicLink(at: folder, withDestinationURL: box.root.appendingPathComponent("Other.avd"))

        #expect(prepare(box, target) == .refused)
        #expect(box.exists("Other.avd/config.ini"))
    }

    @Test func aFolderDifferentFromTheOneSeenAtScanTimeIsRefusedEvenWhenItLooksValid() throws {
        let box = try Sandbox(insideHome: true)
        try makeAVD(box, name: "Test_Phone_A")
        let target = try scanTarget(box, "Test_Phone_A")
        // L'`.ini` est réécrit vers un autre dossier d'AVD valide du dossier personnel.
        try box.write("Other.avd/config.ini", "AvdId=Other\n")
        try box.write(".android/avd/Test_Phone_A.ini", "path=\(box.root.path)/Other.avd\n")

        #expect(prepare(box, target) == .refused)
        #expect(box.exists("Other.avd/config.ini"))
    }

    @Test func aHomeOutsideTheRealHomeIsRefusedByTheSafetyRuleAndNothingIsDeleted() throws {
        // `isSafeToDelete` est lié au VRAI dossier personnel : un bac à sable dans le dossier temporaire est refusé, tout existe encore.
        let box = try Sandbox(insideHome: false)
        try makeAVD(box, name: "Test_Phone_A")
        let target = try scanTarget(box, "Test_Phone_A")

        #expect(prepare(box, target) == .refused)
        #expect(box.exists(".android/avd/Test_Phone_A.ini"))
        #expect(box.exists(".android/avd/Test_Phone_A.avd/config.ini"))
    }

    @Test func aRegistrationThatIsASymlinkToAFileOutsideTheHomeIsRefused() throws {
        let box = try Sandbox(insideHome: true)
        let folder = try makeAVD(box, name: "Test_Phone_A")
        try box.write(".android/avd/Test_Phone_B.ini", "path=\(folder.path)\n")
        let target = try scanTarget(box, "Test_Phone_A")
        // L'alias devient un lien vers un fichier hors du dossier personnel : `isSafeToDelete` le refuse, le plan entier est refusé.
        let outside = try Sandbox(insideHome: false)
        try outside.write("alias.ini", "path=\(folder.path)\n")
        let aliasURL = box.root.appendingPathComponent(".android/avd/Test_Phone_B.ini")
        try FileManager.default.removeItem(at: aliasURL)
        try FileManager.default.createSymbolicLink(at: aliasURL, withDestinationURL: outside.root.appendingPathComponent("alias.ini"))

        #expect(prepare(box, target) == .refused)
        #expect(outside.exists("alias.ini"))
    }

    @Test func anInvalidNameIsRefusedAndNeverJoinedToAPath() throws {
        let box = try Sandbox(insideHome: true)
        try makeAVD(box, name: "Test_Phone_A")
        let folder = box.root.appendingPathComponent(".android/avd/Test_Phone_A.avd")
        #expect(prepare(box, AndroidRemovalTarget(name: "../Test_Phone_A", folder: folder)) == .refused)
        #expect(prepare(box, AndroidRemovalTarget(name: "", folder: folder)) == .refused)
    }

    // MARK: Les inscriptions doivent être des fichiers

    @Test func aDirectoryNamedLikeTheRegistrationIsRefusedAndNeverRemovedRecursively() throws {
        let box = try Sandbox(insideHome: true)
        try makeAVD(box, name: "Test_Phone_A")
        // `<nom>.ini` devient un DOSSIER (avec un fichier dedans) : le listage garde l'appareil par le dossier par défaut.
        try FileManager.default.removeItem(at: box.root.appendingPathComponent(".android/avd/Test_Phone_A.ini"))
        try box.write(".android/avd/Test_Phone_A.ini/precious.txt", "x")
        let target = try scanTarget(box, "Test_Phone_A")

        #expect(prepare(box, target) == .refused)
        #expect(box.exists(".android/avd/Test_Phone_A.ini/precious.txt"))
    }

    @Test func aRegistrationThatIsASymlinkToAFileInsideTheHomeIsStillAccepted() throws {
        let box = try Sandbox(insideHome: true)
        let folder = try makeAVD(box, name: "Test_Phone_A")
        try box.write("elsewhere/real.ini", "path=\(folder.path)\n")
        let alias = box.root.appendingPathComponent(".android/avd/Test_Phone_B.ini")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: box.root.appendingPathComponent("elsewhere/real.ini"))
        let target = try scanTarget(box, "Test_Phone_A")

        guard case .plan(let plan) = prepare(box, target) else { Issue.record("un plan était attendu"); return }
        #expect(plan.names == ["Test_Phone_A", "Test_Phone_B"])
    }

    // MARK: Illisible

    @Test func anUnreadableAvdFolderMeansCouldNotCheck() throws {
        let box = try Sandbox(insideHome: true)
        try box.write(".android/avd", "pas un dossier")
        let target = AndroidRemovalTarget(name: "Test_Phone_A", folder: box.root.appendingPathComponent(".android/avd/Test_Phone_A.avd"))
        #expect(prepare(box, target) == .couldNotCheck)
    }
}
