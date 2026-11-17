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
              let version = version(ofFolderName: parts[index + 1]) else { return nil }
        let variant = parts[index + 2]
        let abi = parts[index + 3]
        guard AndroidEmulatorScanner.isValidAVDName(variant), AndroidEmulatorScanner.isValidAVDName(abi) else { return nil }
        return AndroidSystemImageKey(version: version, variant: variant, abi: abi)
    }
}

// MARK: - Lecture de `<sdk>/system-images` (lecture seule)

/// Un dossier d'image système trouvé sur le disque : sa clé et son dossier (standardisé, sans lien symbolique, dans le dossier personnel).
struct AndroidSystemImageFolder: Equatable {
    let key: AndroidSystemImageKey
    let folder: URL
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

        var images: [AndroidSystemImageFolder] = []
        var taken = Set<String>()
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
            guard let version = version(ofFolderName: versionEntry),
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
                          hasMarker(in: abi.url), taken.insert(resolved).inserted else {
                        skipped += 1
                        continue
                    }
                    images.append(AndroidSystemImageFolder(key: AndroidSystemImageKey(version: version, variant: variant.name, abi: abi.name),
                                                           folder: abi.url.resolvingSymlinksInPath().standardizedFileURL))
                }
            }
        }
        images.sort(by: isOrderedBefore)
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
