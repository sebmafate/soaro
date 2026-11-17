import Foundation

/// Images système du SDK Android pour l'outil « Simulators and emulators » (R19, SL12a). Ce fichier LIT seulement (ADR 0009) :
/// il ne supprime, ne déplace ni n'écrit rien, ne lance aucun outil (aucun lanceur de commandes) et n'utilise pas le réseau.
/// Une source test interdit tout code de suppression dans les fichiers `AndroidSystemImage*.swift`.

/// La clé d'une image système : `android-<N>[.<M>]/<variante>/<ABI>`. Deux clés qui ne diffèrent que par la casse sont égales
/// (APFS ignore la casse : un faux « utilisée » reste du côté sûr).
struct AndroidSystemImageKey: Hashable {
    /// `"36"` ou `"36.1"`.
    let version: String
    let variant: String
    let abi: String

    /// Le chemin relatif `android-<N>[.<M>]/<variante>/<ABI>`.
    var path: String { "android-\(version)/\(variant)/\(abi)" }

    static func == (a: AndroidSystemImageKey, b: AndroidSystemImageKey) -> Bool { a.path.lowercased() == b.path.lowercased() }

    func hash(into hasher: inout Hasher) { hasher.combine(path.lowercased()) }
}

enum AndroidSystemImageScanner {
    /// Le premier segment d'une image : `android-<N>` ou `android-<N>.<M>` ; renvoie la version, sinon `nil`
    /// (`android-Baklava` n'est pas une image publiée : écartée).
    static func version(ofFolderName name: String) -> String? {
        guard name.range(of: "^android-[0-9]+(\\.[0-9]+)?$", options: .regularExpression) != nil else { return nil }
        return String(name.dropFirst("android-".count))
    }

    /// La clé d'image d'un `image.sysdir.1`. Même règle de segments que `AndroidEmulatorScanner.systemVersion` : couper sur `/`,
    /// ignorer les parties vides, trouver le premier `system-images`, prendre les trois segments suivants. La variante et l'ABI
    /// doivent être des noms valides (`isValidAVDName`). Tout autre cas, ou une valeur absente, donne `nil`.
    static func imageKey(imageSysdir: String?) -> AndroidSystemImageKey? {
        guard let imageSysdir else { return nil }
        let parts = imageSysdir.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard let index = parts.firstIndex(of: "system-images"), index + 3 < parts.count,
              let versionNumber = version(ofFolderName: parts[index + 1]) else { return nil }
        let variant = parts[index + 2]
        let abi = parts[index + 3]
        guard AndroidEmulatorScanner.isValidAVDName(variant), AndroidEmulatorScanner.isValidAVDName(abi) else { return nil }
        return AndroidSystemImageKey(version: versionNumber, variant: variant, abi: abi)
    }
}

// MARK: - Lecture de `<sdk>/system-images` (lecture seule)

/// Un dossier d'image système trouvé sur le disque : sa clé et son dossier (standardisé, sans lien symbolique, dans le dossier personnel).
struct AndroidSystemImageFolder: Equatable {
    /// La clé AFFICHÉE : le vrai nom du dossier quand on peut le lire (ses trois derniers composants), sinon le premier nom trouvé.
    let key: AndroidSystemImageKey
    let folder: URL
    /// TOUTES les clés qui mènent à ce dossier (un lien `android-35` vers `android-36`, un lien d'ABI) : un appareil qui écrit l'une
    /// d'elles dans `image.sysdir.1` utilise ce dossier. Contient toujours `key`.
    let keys: [AndroidSystemImageKey]

    init(key: AndroidSystemImageKey, folder: URL, keys: [AndroidSystemImageKey]? = nil) {
        self.key = key
        self.folder = folder
        self.keys = keys ?? [key]
    }
}

/// Résultat de la lecture de `<sdk>/system-images`.
struct AndroidSystemImageFolderListing: Equatable {
    enum Status: Equatable {
        /// Lu (éventuellement vide, aussi quand le dossier `system-images` n'existe pas).
        case ok
        /// Le SDK (ou `system-images`) est hors du dossier personnel : rien n'est lu (ADR 0009, règle 1).
        case sdkOutsideHome
        /// `system-images` n'est pas un dossier, ou ne peut pas être listé.
        case unreadable
    }

    let status: Status
    let images: [AndroidSystemImageFolder]
    /// Dossiers écartés (un décompte, jamais un nom ni un chemin) : voir `AndroidSystemImageScanner.listImages`.
    var skippedCount = 0

    init(status: Status, images: [AndroidSystemImageFolder] = [], skippedCount: Int = 0) {
        self.status = status
        self.images = images
        self.skippedCount = skippedCount
    }
}

extension AndroidSystemImageScanner {
    /// Les fichiers dont la présence (fichier ordinaire) fait d'un dossier ABI une image système installée (décision D2).
    static let markerFiles = ["source.properties", "package.xml"]

    /// Lit `<sdk>/system-images` : synchrone, lecture seule, ne lance rien. Exactement trois niveaux
    /// (`android-<N>[.<M>]`, variante, ABI) ; rien de plus profond n'est lu.
    /// 1. Le SDK (résolu) doit être STRICTEMENT dans le dossier personnel, sinon `sdkOutsideHome` et rien n'est lu.
    /// 2. `system-images` absent : `ok` et vide ; un fichier ou un dossier illisible : `unreadable`.
    /// 3. Les entrées qui ne sont pas des dossiers sont ignorées, sans être comptées. Sont ÉCARTÉS et comptés : un premier niveau
    ///    qui n'est pas `android-<N>[.<M>]` ; une variante ou une ABI de nom invalide ; un niveau illisible ; un dossier dont le chemin
    ///    résolu n'est pas strictement dans le dossier personnel ; un dossier ABI sans `source.properties` ni `package.xml` ordinaire ;
    ///    un second nom qui mène à un dossier déjà pris (le premier par nom l'emporte).
    /// 4. Tri : version décroissante (numérique), puis variante, puis ABI, croissantes.
    static func listImages(sdk: AndroidSDKLocation, home: URL) -> AndroidSystemImageFolderListing {
        let homePath = AndroidEmulatorScanner.resolvedPath(home)
        let sdkFolder = URL(fileURLWithPath: sdk.path, isDirectory: true)
        guard AndroidEmulatorScanner.isStrictlyInside(sdkFolder, homePath: homePath) else {
            return AndroidSystemImageFolderListing(status: .sdkOutsideHome)
        }
        let root = sdkFolder.appendingPathComponent("system-images", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory) else {
            return AndroidSystemImageFolderListing(status: .ok)
        }
        // `system-images` lui-même est un lien qui sort du dossier personnel : même règle que pour le SDK.
        guard AndroidEmulatorScanner.isStrictlyInside(root, homePath: homePath) else {
            return AndroidSystemImageFolderListing(status: .sdkOutsideHome)
        }
        guard isDirectory.boolValue, let versions = try? FileManager.default.contentsOfDirectory(atPath: root.path) else {
            return AndroidSystemImageFolderListing(status: .unreadable)
        }

        /// Un dossier réel (chemin résolu) et tous les noms sous lesquels on y arrive, dans l'ordre de lecture.
        var groups: [(resolved: String, folder: URL, keys: [AndroidSystemImageKey])] = []
        var groupIndex: [String: Int] = [:]
        var skipped = 0

        /// Les sous-dossiers de `folder` (liens suivis) triés par nom, ou `nil` si le dossier ne peut pas être listé.
        func subfolders(of folder: URL) -> [(name: String, url: URL)]? {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return nil }
            return names.sorted().compactMap { name in
                let url = folder.appendingPathComponent(name, isDirectory: true)
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
                return (name, url)
            }
        }

        for versionEntry in versions.sorted() {
            let versionURL = root.appendingPathComponent(versionEntry, isDirectory: true)
            var versionIsDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: versionURL.path, isDirectory: &versionIsDirectory),
                  versionIsDirectory.boolValue else { continue }
            guard let versionNumber = version(ofFolderName: versionEntry),
                  AndroidEmulatorScanner.isStrictlyInside(versionURL, homePath: homePath),
                  let variants = subfolders(of: versionURL) else {
                skipped += 1
                continue
            }
            for variant in variants {
                guard AndroidEmulatorScanner.isValidAVDName(variant.name),
                      AndroidEmulatorScanner.isStrictlyInside(variant.url, homePath: homePath),
                      let abis = subfolders(of: variant.url) else {
                    skipped += 1
                    continue
                }
                for abi in abis {
                    let resolved = AndroidEmulatorScanner.resolvedPath(abi.url)
                    guard AndroidEmulatorScanner.isValidAVDName(abi.name),
                          AndroidEmulatorScanner.isStrictlyInside(abi.url, homePath: homePath),
                          hasMarker(in: abi.url) else {
                        skipped += 1
                        continue
                    }
                    let key = AndroidSystemImageKey(version: versionNumber, variant: variant.name, abi: abi.name)
                    // Un second nom du même dossier (lien) : on garde SA clé aussi (un appareil peut l'écrire dans `image.sysdir.1`),
                    // sans nouvelle ligne ; il reste compté comme écarté (une seule ligne par dossier).
                    if let index = groupIndex[resolved] {
                        if !groups[index].keys.contains(key) { groups[index].keys.append(key) }
                        skipped += 1
                        continue
                    }
                    groupIndex[resolved] = groups.count
                    groups.append((resolved, abi.url.resolvingSymlinksInPath().standardizedFileURL, [key]))
                }
            }
        }
        let images = groups.map { group -> AndroidSystemImageFolder in
            // La clé affichée est le vrai nom du dossier (ses trois derniers composants) quand c'est l'une des clés trouvées, sinon la première.
            let real = imageKey(imageSysdir: "system-images/" + group.folder.pathComponents.suffix(3).joined(separator: "/"))
            let shown = real.flatMap { group.keys.contains($0) ? $0 : nil } ?? group.keys[0]
            return AndroidSystemImageFolder(key: group.keys.first { $0 == shown } ?? shown, folder: group.folder, keys: group.keys)
        }.sorted(by: isOrderedBefore)
        return AndroidSystemImageFolderListing(status: .ok, images: images, skippedCount: skipped)
    }

    /// Le dossier contient un `source.properties` ou un `package.xml` ordinaire (liens suivis).
    private static func hasMarker(in folder: URL) -> Bool {
        markerFiles.contains { marker in
            var info = stat()
            return stat(folder.appendingPathComponent(marker).path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFREG
        }
    }

    /// Le numéro de version comme couple d'entiers `(N, M)` (`36.1` donne `(36, 1)`, `36` donne `(36, 0)`).
    private static func numericVersion(_ version: String) -> (Int, Int) {
        let parts = version.split(separator: ".")
        return (Int(parts[0]) ?? 0, parts.count > 1 ? Int(parts[1]) ?? 0 : 0)
    }

    /// L'ordre des images, PARTAGÉ : version décroissante (numérique), puis variante, puis ABI, croissantes.
    static func isOrderedBefore(_ a: AndroidSystemImageFolder, _ b: AndroidSystemImageFolder) -> Bool {
        isOrderedBefore(a.key, b.key)
    }

    static func isOrderedBefore(_ a: AndroidSystemImageKey, _ b: AndroidSystemImageKey) -> Bool {
        let (x, y) = (numericVersion(a.version), numericVersion(b.version))
        if x != y { return x > y }
        if a.variant != b.variant { return a.variant < b.variant }
        return a.abi < b.abi
    }
}

// MARK: - Qui utilise chaque image, et le listage complet

/// Une image système installée, avec qui l'utilise.
struct AndroidSystemImage: Equatable {
    enum Usage: Equatable {
        /// Les appareils listés (`listAVDs`) dont la clé d'image est celle-ci, dans l'ordre `AndroidDevice.isOrderedBefore`.
        case usedBy([AndroidDevice])
        /// Aucun appareil listé ne l'utilise, mais un appareil peut exister que Soaro ne voit pas.
        case cannotTell
        /// Aucun appareil listé ne l'utilise et la liste des appareils est complète.
        case notUsed
    }

    let key: AndroidSystemImageKey
    let folder: URL
    let usage: Usage
}

/// Les raisons pour lesquelles la liste des appareils peut être incomplète (jamais un chemin ni une valeur).
struct AndroidSystemImageIncompleteness: Equatable {
    enum Reason: Equatable {
        /// Variables d'environnement définies et non vides parmi `customLocationVariables` (`ANDROID_AVD_HOME`, `ANDROID_USER_HOME`,
        /// `ANDROID_EMULATOR_HOME`, `ANDROID_SDK_HOME`, `ANDROID_PREFS_ROOT`), dans cet ordre : les appareils déplacés par elles ne sont pas lus.
        case customLocation([String])
        /// Le dossier des AVD ne peut pas être lu.
        case avdFolderUnreadable
        /// Inscriptions (`<nom>.ini`) qui n'ont donné aucun appareil.
        case skippedRegistrations(Int)
        /// Appareils listés dont l'image système est inconnue (pas de `image.sysdir.1` lisible).
        case unknownImage(Int)
    }

    var reasons: [Reason]
    var isEmpty: Bool { reasons.isEmpty }
}

/// Résultat du listage complet des images système.
struct AndroidSystemImageListing: Equatable {
    enum Status: Equatable {
        /// Lu (éventuellement aucune image).
        case ok
        /// Pas de SDK : le groupe n'existe pas.
        case sdkNotFound
        /// Le SDK est hors du dossier personnel : rien n'est lu.
        case sdkOutsideHome
        /// `system-images` illisible.
        case unreadable
    }

    let status: Status
    let images: [AndroidSystemImage]
    let sdk: AndroidSDKLocation?
    /// Dossiers écartés (voir `AndroidSystemImageScanner.listImages`).
    let skippedCount: Int
    let incompleteness: AndroidSystemImageIncompleteness

    init(status: Status, images: [AndroidSystemImage] = [], sdk: AndroidSDKLocation? = nil, skippedCount: Int = 0,
         incompleteness: AndroidSystemImageIncompleteness = AndroidSystemImageIncompleteness(reasons: [])) {
        self.status = status
        self.images = images
        self.sdk = sdk
        self.skippedCount = skippedCount
        self.incompleteness = incompleteness
    }
}

extension AndroidSystemImageScanner {
    /// Les variables qui peuvent déplacer les AVD, dans l'ordre où elles sont nommées. Une UNIQUE constante. Les trois premières sont
    /// celles des outils actuels ; `ANDROID_SDK_HOME` (ancien emplacement de `.android`) et `ANDROID_PREFS_ROOT` ont été ajoutées de
    /// mémoire des outils Android et NON vérifiées sur la machine de l'auteur : il peut les retirer d'ici (plus de « cannot tell »
    /// seulement, le sens sûr).
    static let customLocationVariables = ["ANDROID_AVD_HOME", "ANDROID_USER_HOME", "ANDROID_EMULATOR_HOME", "ANDROID_SDK_HOME", "ANDROID_PREFS_ROOT"]

    /// Les raisons d'incomplétude, dans l'ordre : emplacements personnalisés, dossier illisible, inscriptions écartées, image inconnue.
    /// Fonction pure ; l'environnement est injecté.
    static func incompleteness(environment: [String: String], avds: AndroidAVDListing) -> AndroidSystemImageIncompleteness {
        var reasons: [AndroidSystemImageIncompleteness.Reason] = []
        let set = customLocationVariables.filter { !(environment[$0] ?? "").isEmpty }
        if !set.isEmpty { reasons.append(.customLocation(set)) }
        if avds.status == .unreadable { reasons.append(.avdFolderUnreadable) }
        // Les alias ne comptent pas : l'appareil est listé. Seules les inscriptions qui n'ont donné aucun appareil rendent la liste incomplète.
        if avds.unreadableRegistrationCount > 0 { reasons.append(.skippedRegistrations(avds.unreadableRegistrationCount)) }
        let unknown = avds.devices.filter { imageKey(imageSysdir: $0.imageSysdir) == nil }.count
        if unknown > 0 { reasons.append(.unknownImage(unknown)) }
        return AndroidSystemImageIncompleteness(reasons: reasons)
    }

    /// Rattache chaque image à ses appareils : tous les AVD listés comptent (même petits, même à l'arrêt), chacun une seule fois
    /// (les alias ne sont pas des utilisateurs distincts). Sans utilisateur : `cannotTell` si la liste est incomplète, sinon `notUsed`.
    /// Une image utilisée par un appareil listé reste « utilisée » même si la liste est incomplète. L'ordre des images est gardé.
    static func usage(images: [AndroidSystemImageFolder], devices: [AndroidDevice],
                      incompleteness: AndroidSystemImageIncompleteness) -> [AndroidSystemImage] {
        let sorted = devices.sorted(by: AndroidDevice.isOrderedBefore)
        return images.map { image in
            // Utilisée si l'UNE des clés du dossier est celle de l'appareil (un lien peut donner plusieurs noms à un même dossier).
            let users = sorted.filter { device in imageKey(imageSysdir: device.imageSysdir).map { image.keys.contains($0) } ?? false }
            let usage: AndroidSystemImage.Usage = !users.isEmpty ? .usedBy(users) : (incompleteness.isEmpty ? .notUsed : .cannotTell)
            return AndroidSystemImage(key: image.key, folder: image.folder, usage: usage)
        }
    }

    /// Le listage complet, synchrone, dans cet ordre :
    /// 1. le SDK (`ToolLocator.androidSDK`, première variable définie, sans repli) : absent, `sdkNotFound`, rien d'autre n'est lu ;
    /// 2. `listImages` : `sdkOutsideHome` et `unreadable` sont rendus tels quels ; aucune image : `ok` et vide (les AVD ne sont pas lus) ;
    /// 3. `AndroidEmulatorScanner.listAVDs` alimente le rattachement ;
    /// 4. `ok` avec les images, le décompte, l'incomplétude et le SDK.
    /// Aucun processus n'est lancé : le rattachement ne dépend pas des émulateurs en cours d'exécution.
    /// - Parameter environment: injecté, jamais lu sur la machine ici (aucune valeur par défaut).
    static func list(environment: [String: String], home: URL) -> AndroidSystemImageListing {
        guard let sdk = ToolLocator.androidSDK(environment: environment, home: home) else {
            return AndroidSystemImageListing(status: .sdkNotFound)
        }
        let folders = listImages(sdk: sdk, home: home)
        guard folders.status == .ok else { return AndroidSystemImageListing(status: folders.status.listingStatus, sdk: sdk) }
        guard !folders.images.isEmpty else {
            return AndroidSystemImageListing(status: .ok, sdk: sdk, skippedCount: folders.skippedCount)
        }
        let avds = AndroidEmulatorScanner.listAVDs(home: home)
        let reasons = incompleteness(environment: environment, avds: avds)
        return AndroidSystemImageListing(status: .ok, images: usage(images: folders.images, devices: avds.devices, incompleteness: reasons),
                                         sdk: sdk, skippedCount: folders.skippedCount, incompleteness: reasons)
    }
}

private extension AndroidSystemImageFolderListing.Status {
    var listingStatus: AndroidSystemImageListing.Status {
        switch self {
        case .ok: .ok
        case .sdkOutsideHome: .sdkOutsideHome
        case .unreadable: .unreadable
        }
    }
}

// MARK: - Scan avec tailles (pour `--scan`)

/// Un listage d'images système avec la taille réelle (espace alloué) de chaque dossier d'image, par clé.
struct AndroidSystemImageScan: Equatable {
    let listing: AndroidSystemImageListing
    let sizes: [AndroidSystemImageKey: UInt64]
}

