import Foundation
import Testing
@testable import Soaro

/// Liste des AVD sur le disque (R16) : LECTURE SEULE, dans le bac à sable `.soaro-test-<uuid>` (dans le vrai dossier personnel,
/// jamais le vrai `~/.android`). Dates posées avec `setAttributes`.
@Suite(.serialized) struct AndroidAVDListingTests {
    private let day: TimeInterval = 86_400
    private let reference = Date(timeIntervalSince1970: 1_700_000_000)

    private func daysAgo(_ days: Double) -> Date { reference.addingTimeInterval(-days * day) }

    /// Écrit un AVD complet : `<name>.ini` et `<name>.avd/config.ini` ; renvoie le dossier `.avd`.
    @discardableResult
    private func makeAVD(_ box: Sandbox, name: String, display: String? = nil, system: String? = "system-images/android-36/google_apis_playstore/arm64-v8a/",
                         registration: String? = nil) throws -> URL {
        try box.dir(".android/avd/\(name).avd")
        let ini = registration ?? "avd.ini.encoding=UTF-8\npath=\(box.root.path)/.android/avd/\(name).avd\npath.rel=avd/\(name).avd\ntarget=android-36\n"
        try box.write(".android/avd/\(name).ini", ini)
        var config = "AvdId=\(name)\n"
        if let display { config += "avd.ini.displayname=\(display)\n" }
        if let system { config += "image.sysdir.1=\(system)\n" }
        try box.write(".android/avd/\(name).avd/config.ini", config)
        return box.root.appendingPathComponent(".android/avd/\(name).avd")
    }

    private func touch(_ folder: URL, _ relative: String, daysAgo days: Double) throws {
        let url = folder.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: 4).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: daysAgo(days)], ofItemAtPath: url.path)
    }

    private func list(_ box: Sandbox) -> AndroidAVDListing { AndroidEmulatorScanner.listAVDs(home: box.root) }

    private func realPath(_ url: URL) -> String { url.resolvingSymlinksInPath().standardizedFileURL.path }

    // MARK: Cas nominal

    @Test func listsTwoDevicesWithNamesSystemsFoldersAndDates() throws {
        let box = try Sandbox(insideHome: true)
        let a = try makeAVD(box, name: "Test_Phone_A", display: "Test Phone A")
        let b = try makeAVD(box, name: "Test_Tablet_B", system: "system-images/android-34/default/arm64-v8a/")
        try touch(a, "userdata-qemu.img.qcow2", daysAgo: 10)
        try touch(a, "hardware-qemu.ini", daysAgo: 12)
        try touch(b, "cache.img.qcow2", daysAgo: 70)

        let listing = list(box)
        #expect(listing.status == .ok)
        #expect(listing.devices.map(\.name) == ["Test_Phone_A", "Test_Tablet_B"])
        #expect(listing.devices.map(\.displayName) == ["Test Phone A", "Test_Tablet_B"])
        #expect(listing.devices.map(\.systemVersion) == ["36", "34"])
        #expect(listing.devices.map { realPath($0.folder) } == [realPath(a), realPath(b)])
        #expect(listing.devices[0].lastUsed == daysAgo(10))
        #expect(listing.devices[0].lastUsedSource == "userdata-qemu.img.qcow2")
        #expect(listing.devices[1].lastUsed == daysAgo(70))
        #expect(listing.devices[1].lastUsedSource == "cache.img.qcow2")
        #expect(listing.devices.allSatisfy { !$0.isRunning })
    }

    @Test func devicesAreSortedByDisplayNameIgnoringCaseThenByName() throws {
        let box = try Sandbox(insideHome: true)
        try makeAVD(box, name: "Zeta", display: "alpha")
        try makeAVD(box, name: "B_Two", display: "Beta")
        try makeAVD(box, name: "A_One", display: "Beta")
        #expect(list(box).devices.map(\.name) == ["Zeta", "A_One", "B_Two"])
    }

    // MARK: Date de dernière utilisation

    @Test func theNewestListedFileGivesTheDate() throws {
        let box = try Sandbox(insideHome: true)
        let folder = try makeAVD(box, name: "Test_Phone_A")
        try FileManager.default.setAttributes([.modificationDate: daysAgo(100)], ofItemAtPath: folder.appendingPathComponent("config.ini").path)
        try touch(folder, "hardware-qemu.ini", daysAgo: 20)
        try touch(folder, "userdata-qemu.img", daysAgo: 40)
        let device = try #require(list(box).devices.first)
        #expect(device.lastUsed == daysAgo(20))
        #expect(device.lastUsedSource == "hardware-qemu.ini")
    }

    @Test func aNewerConfigIniOrLockFileIsIgnored() throws {
        let box = try Sandbox(insideHome: true)
        let folder = try makeAVD(box, name: "Test_Phone_A")
        try touch(folder, "hardware-qemu.ini", daysAgo: 50)
        try FileManager.default.setAttributes([.modificationDate: daysAgo(1)], ofItemAtPath: folder.appendingPathComponent("config.ini").path)
        try touch(folder, "multiinstance.lock", daysAgo: 0)
        try FileManager.default.setAttributes([.modificationDate: daysAgo(2)],
                                              ofItemAtPath: box.root.appendingPathComponent(".android/avd/Test_Phone_A.ini").path)
        let device = try #require(list(box).devices.first)
        #expect(device.lastUsed == daysAgo(50))
        #expect(device.lastUsedSource == "hardware-qemu.ini")
    }

    @Test func onlyTheSnapshotFileGivesItsDate() throws {
        let box = try Sandbox(insideHome: true)
        let folder = try makeAVD(box, name: "Test_Phone_A")
        try touch(folder, "snapshots/default_boot/snapshot.pb", daysAgo: 33)
        let device = try #require(list(box).devices.first)
        #expect(device.lastUsed == daysAgo(33))
        #expect(device.lastUsedSource == "snapshots/default_boot/snapshot.pb")
    }

    @Test func noListedFileMeansUnknown() throws {
        let box = try Sandbox(insideHome: true)
        let folder = try makeAVD(box, name: "Test_Phone_A")
        try touch(folder, "multiinstance.lock", daysAgo: 0)
        let device = try #require(list(box).devices.first)
        #expect(device.lastUsed == nil)
        #expect(device.lastUsedSource == nil)
    }

    @Test func everyExistingListedFileDateIsReturnedInConstantOrder() throws {
        let box = try Sandbox(insideHome: true)
        let folder = try makeAVD(box, name: "Test_Phone_A")
        try touch(folder, "cache.img.qcow2", daysAgo: 41)
        try touch(folder, "emulator-user.ini", daysAgo: 2)
        try touch(folder, "hardware-qemu.ini", daysAgo: 40)
        try touch(folder, "multiinstance.lock", daysAgo: 0)    // hors liste : jamais renvoyé
        let device = try #require(list(box).devices.first)
        #expect(device.fileDates == [AndroidFileDate(file: "hardware-qemu.ini", date: daysAgo(40)),
                                     AndroidFileDate(file: "emulator-user.ini", date: daysAgo(2)),
                                     AndroidFileDate(file: "cache.img.qcow2", date: daysAgo(41))])
        #expect(device.lastUsedSource == "emulator-user.ini")
    }

    @Test func noListedFileGivesNoFileDates() throws {
        let box = try Sandbox(insideHome: true)
        try makeAVD(box, name: "Test_Phone_A")
        #expect(try #require(list(box).devices.first).fileDates.isEmpty)
    }

    @Test func theSignalIsOneNamedConstant() {
        #expect(AndroidEmulatorScanner.lastUsedFiles == ["hardware-qemu.ini", "emulator-user.ini", "userdata-qemu.img.qcow2",
                                                        "userdata-qemu.img", "cache.img.qcow2", "snapshots/default_boot/snapshot.pb"])
    }

    // MARK: Dossier absent, illisible

    @Test func noAvdFolderIsOkAndEmpty() throws {
        let box = try Sandbox(insideHome: true)
        let listing = list(box)
        #expect(listing.status == .ok)
        #expect(listing.devices.isEmpty)
    }

    @Test func anAvdFolderThatCannotBeListedIsUnreadable() throws {
        let box = try Sandbox(insideHome: true)
        try box.dir(".android/avd")
        let avd = box.root.appendingPathComponent(".android/avd").path
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: avd)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: avd) }
        #expect(list(box).status == .unreadable)
    }

    @Test func anAvdPathThatIsAFileIsUnreadable() throws {
        let box = try Sandbox(insideHome: true)
        try box.file(".android/avd")
        #expect(list(box).status == .unreadable)
    }

    // MARK: Dossier de l'appareil

    @Test func anIniPointingOutsideTheHomeWithoutAValidRelativePathIsSkipped() throws {
        let box = try Sandbox(insideHome: true)
        let outside = try Sandbox()
        try outside.dir("Test_Phone_A.avd")
        try makeAVD(box, name: "Test_Phone_A", registration: "path=\(outside.root.path)/Test_Phone_A.avd\n")
        // Le dossier par défaut de l'AVD n'existe pas non plus sous le home : on le retire pour isoler le cas.
        try FileManager.default.removeItem(at: box.root.appendingPathComponent(".android/avd/Test_Phone_A.avd"))
        #expect(list(box).devices.isEmpty)
    }

    @Test func anExistingFolderOutsideTheHomeIsSkippedEvenWhenAnotherCandidateWouldBeInside() throws {
        let box = try Sandbox(insideHome: true)
        let outside = try Sandbox()
        try outside.dir("Test_Phone_A.avd")
        try makeAVD(box, name: "Test_Phone_A", registration: "path=\(outside.root.path)/Test_Phone_A.avd\npath.rel=avd/Test_Phone_A.avd\n")
        #expect(list(box).devices.isEmpty)
    }

    @Test func aStalePathFallsBackToTheRelativePath() throws {
        let box = try Sandbox(insideHome: true)
        // Le dossier n'est PAS au chemin par défaut `<nom>.avd` : seul `path.rel` y mène.
        try box.dir(".android/avd/Moved_A.avd")
        try box.write(".android/avd/Moved_A.avd/config.ini", "avd.ini.displayname=Moved A\n")
        try box.write(".android/avd/Test_Phone_A.ini", "path=/Users/test/.android/avd/Gone.avd\npath.rel=avd/Moved_A.avd\n")
        let listing = list(box)
        #expect(listing.devices.map(\.name) == ["Test_Phone_A"])
        #expect(listing.devices.map(\.displayName) == ["Moved A"])
        #expect(listing.devices.map { realPath($0.folder) } == [realPath(box.root.appendingPathComponent(".android/avd/Moved_A.avd"))])
    }

    @Test func aRelativeValueInPathIsNotUsed() throws {
        let box = try Sandbox(insideHome: true)
        // Un dossier existant que `path=avd/Moved_A.avd` désignerait s'il était résolu contre `<home>/.android` ; ni `path.rel`,
        // ni dossier par défaut `Test_Phone_A.avd` : accepter une valeur relative trouverait l'AVD.
        try box.dir(".android/avd/Moved_A.avd")
        try box.write(".android/avd/Moved_A.avd/config.ini", "avd.ini.displayname=Moved A\n")
        try box.write(".android/avd/Test_Phone_A.ini", "path=avd/Moved_A.avd\n")
        #expect(list(box).devices.isEmpty)
        // Même valeur, écrite en absolu : le dossier est trouvé (le test peut donc échouer si `path=` était ignoré).
        try box.write(".android/avd/Test_Phone_A.ini", "path=\(box.root.path)/.android/avd/Moved_A.avd\n")
        #expect(list(box).devices.map(\.name) == ["Test_Phone_A"])
    }

    @Test func theDefaultFolderIsUsedWhenTheIniNamesNothingUsable() throws {
        let box = try Sandbox(insideHome: true)
        let folder = try makeAVD(box, name: "Test_Phone_A", registration: "avd.ini.encoding=UTF-8\n")
        #expect(list(box).devices.map { realPath($0.folder) } == [realPath(folder)])
    }

    @Test func aSymlinkedAvdFolderPointingOutsideTheHomeIsSkipped() throws {
        let box = try Sandbox(insideHome: true)
        let outside = try Sandbox()
        try outside.dir("real.avd")
        try outside.write("real.avd/config.ini", "avd.ini.displayname=Outside\n")
        try box.dir(".android/avd")
        try FileManager.default.createSymbolicLink(atPath: box.root.appendingPathComponent(".android/avd/Test_Phone_A.avd").path,
                                                   withDestinationPath: outside.root.appendingPathComponent("real.avd").path)
        try box.write(".android/avd/Test_Phone_A.ini", "path.rel=avd/Test_Phone_A.avd\n")
        #expect(list(box).devices.isEmpty)
    }

    @Test func aFolderEqualToTheHomeItselfIsNotStrictlyInside() throws {
        let box = try Sandbox(insideHome: true)
        try makeAVD(box, name: "Test_Phone_A", registration: "path=\(box.root.path)\n")
        try FileManager.default.removeItem(at: box.root.appendingPathComponent(".android/avd/Test_Phone_A.avd"))
        // Le `home` du listage EST la racine du bac à sable : `path=` vaut le home, donc n'est pas « strictement dedans ».
        #expect(list(box).devices.isEmpty)
    }

    // MARK: Le dossier ressemble à un AVD (SL11 en fera la cible d'une suppression)

    @Test func anIniPointingAtAnOrdinaryFolderInsideTheHomeIsSkipped() throws {
        let box = try Sandbox(insideHome: true)
        try box.dir("Documents")
        try box.write("Documents/config.ini", "avd.ini.displayname=Not an AVD\n")   // config.ini, mais pas un dossier `.avd`
        try box.write(".android/avd/Test_Phone_A.ini", "path=\(box.root.path)/Documents\n")
        #expect(list(box).devices.isEmpty)
    }

    @Test func aRelativeValueClimbingOutOfTheAvdFolderIsSkipped() throws {
        let box = try Sandbox(insideHome: true)
        try box.dir("Documents")
        try box.write(".android/avd/Test_Phone_A.ini", "path.rel=../Documents\n")
        #expect(list(box).devices.isEmpty)
    }

    @Test func anAvdSuffixedFolderWithoutAConfigIniIsSkipped() throws {
        let box = try Sandbox(insideHome: true)
        try box.dir("Backups/Old.avd")
        try box.write(".android/avd/Test_Phone_A.ini", "path=\(box.root.path)/Backups/Old.avd\n")
        #expect(list(box).devices.isEmpty)
    }

    @Test func aRelocatedAvdFolderWithItsConfigInsideTheHomeIsAccepted() throws {
        let box = try Sandbox(insideHome: true)
        try box.dir("Dev/avds/Moved_Z.avd")
        try box.write("Dev/avds/Moved_Z.avd/config.ini", "avd.ini.displayname=Moved Z\n")
        try box.write(".android/avd/Test_Phone_Z.ini", "path=\(box.root.path)/Dev/avds/Moved_Z.avd\n")
        let listing = list(box)
        #expect(listing.devices.map(\.name) == ["Test_Phone_Z"])
        #expect(listing.devices.map(\.displayName) == ["Moved Z"])
    }

    @Test func aNonQualifyingFolderDoesNotFallThroughToAnotherCandidate() throws {
        let box = try Sandbox(insideHome: true)
        try box.dir("Documents")
        // Le dossier par défaut `<nom>.avd` existerait et serait valide, mais `path=` désigne un dossier ordinaire : AVD ignoré.
        let folder = try makeAVD(box, name: "Test_Phone_A", registration: "path=\(box.root.path)/Documents\n")
        #expect(FileManager.default.fileExists(atPath: folder.path))
        #expect(list(box).devices.isEmpty)
    }

    @Test func twoInisPointingAtTheSameFolderGiveOneRowKeptByNameOrder() throws {
        let box = try Sandbox(insideHome: true)
        let folder = try makeAVD(box, name: "Test_Phone_B")
        try box.write(".android/avd/Test_Phone_A.ini", "path=\(folder.path)\n")
        try box.write(".android/avd/Test_Phone_C.ini", "path.rel=avd/Test_Phone_B.avd\n")
        let listing = list(box)
        #expect(listing.devices.map(\.name) == ["Test_Phone_A"], "le premier par nom, de façon déterministe")
    }

    // MARK: Inscription

    @Test func anOrphanAvdFolderWithoutItsIniIsIgnored() throws {
        let box = try Sandbox(insideHome: true)
        try box.dir(".android/avd/Orphan_D.avd")
        try box.write(".android/avd/Orphan_D.avd/config.ini", "avd.ini.displayname=Orphan\n")
        #expect(list(box).devices.isEmpty)
    }

    @Test func anIniWithNoFolderIsSkipped() throws {
        let box = try Sandbox(insideHome: true)
        try box.dir(".android/avd")
        try box.write(".android/avd/Test_Phone_A.ini", "path.rel=avd/Test_Phone_A.avd\n")
        #expect(list(box).devices.isEmpty)
    }

    @Test func anInvalidFileNameIsIgnored() throws {
        let box = try Sandbox(insideHome: true)
        try makeAVD(box, name: "bad name")
        try makeAVD(box, name: "Test_Phone_A")
        #expect(list(box).devices.map(\.name) == ["Test_Phone_A"])
    }

    @Test func anOversizedIniCountsAsMissingAndTheDefaultFolderStillApplies() throws {
        let box = try Sandbox(insideHome: true)
        let folder = try makeAVD(box, name: "Test_Phone_A", display: "Big Config")
        // config.ini de plus de 1 Mio : traité comme absent, le nom affiché retombe sur le nom de l'AVD.
        var big = Data("avd.ini.displayname=Big Config\n".utf8)
        big.append(Data(count: 1_048_577))
        try big.write(to: folder.appendingPathComponent("config.ini"))
        let device = try #require(list(box).devices.first)
        #expect(device.displayName == "Test_Phone_A")
        #expect(device.systemVersion == nil)
    }

    @Test func aConfigJustUnderTheCapIsRead() throws {
        let box = try Sandbox(insideHome: true)
        let folder = try makeAVD(box, name: "Test_Phone_A")
        var text = Data("avd.ini.displayname=Fits\n".utf8)
        text.append(Data(repeating: UInt8(ascii: "#"), count: 1_048_576 - text.count))
        try text.write(to: folder.appendingPathComponent("config.ini"))
        #expect(list(box).devices.first?.displayName == "Fits")
    }

    @Test func aConfigThatIsNotValidUTF8CountsAsMissing() throws {
        let box = try Sandbox(insideHome: true)
        let folder = try makeAVD(box, name: "Test_Phone_A")
        try Data([0xFF, 0xFE, 0x00]).write(to: folder.appendingPathComponent("config.ini"))
        #expect(list(box).devices.first?.displayName == "Test_Phone_A")
    }

    // MARK: Lecture seule

    @Test func noAndroidSourceFileWritesOrDeletesAnything() throws {
        let cleanup = RepositoryRoot.url().appendingPathComponent("Sources/Soaro/Cleanup")
        let files = try FileManager.default.contentsOfDirectory(atPath: cleanup.path).filter { $0.hasPrefix("Android") && $0.hasSuffix(".swift") }
        #expect(files.contains("AndroidEmulatorScanner.swift"))
        for file in files {
            let text = try String(contentsOf: cleanup.appendingPathComponent(file), encoding: .utf8)
            for forbidden in ["removeItem(", "trashItem(", "\"/bin/rm\"", "createFile(", "write(to:"] {
                #expect(!text.contains(forbidden), "\(file) contient \(forbidden)")
            }
        }
    }
}
