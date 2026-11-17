import Foundation

/// Appareils virtuels Android (AVD) pour l'outil « Simulators and emulators » (R16, R18). Ce fichier LIT seulement (ADR 0009) :
/// il ne supprime, ne déplace ni n'écrit rien sous `~/.android` ou dans le SDK, et ne lance aucun outil du SDK. La suppression
/// d'un AVD (SL11) est dans `AndroidEmulatorRemover.swift`, seul fichier Android qui supprime.
/// Cette première partie : fonctions PURES de lecture des fichiers d'un AVD (aucun accès au disque).
enum AndroidEmulatorScanner {
    // MARK: Nom

    /// Un nom d'AVD est valide s'il tient dans `[A-Za-z0-9._-]`, a au moins un caractère et n'est ni `.` ni `..`.
    /// C'est la SEULE chose qui est ensuite jointe à un chemin ou comparée à une ligne de processus.
    static func isValidAVDName(_ name: String) -> Bool {
        guard !name.isEmpty, name != ".", name != ".." else { return false }
        return name.utf8.allSatisfy { byte in
            switch byte {
            case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "0")...UInt8(ascii: "9"),
                 UInt8(ascii: "."), UInt8(ascii: "_"), UInt8(ascii: "-"): true
            default: false
            }
        }
    }

    // MARK: Fichiers INI

    /// Lit un fichier `clé=valeur` (`<nom>.ini`, `config.ini`) : coupe à la PREMIÈRE `=`, clés et valeurs sans blancs autour ;
    /// lignes vides, lignes commençant par `#` ou `;`, lignes sans `=` ignorées ; pour une clé répétée la première gagne.
    /// - Returns: `nil` si le contenu n'est pas de l'UTF-8 valide.
    static func parseINI(_ data: Data) -> [String: String]? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        var values: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix(";") { continue }
            guard let equals = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[..<equals].trimmingCharacters(in: .whitespaces)
            let value = trimmed[trimmed.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if key.isEmpty || values[key] != nil { continue }
            values[key] = value
        }
        return values
    }

    // MARK: Système et nom affiché

    /// `system-images/android-36/google_apis_playstore/arm64-v8a/` donne `"36"` ; `android-36.1` donne `"36.1"`.
    /// Le segment qui suit `system-images` doit avoir la forme `android-<N>` ou `android-<N>.<M>` ; tout autre cas
    /// (`android-Baklava`, clé absente) donne `nil`, affiché « Unknown system ».
    static func systemVersion(imageSysdir: String?) -> String? {
        guard let imageSysdir else { return nil }
        let parts = imageSysdir.split(separator: "/", omittingEmptySubsequences: true)
        guard let index = parts.firstIndex(of: "system-images"), index + 1 < parts.count else { return nil }
        let segment = String(parts[index + 1])
        guard segment.range(of: "^android-[0-9]+(\\.[0-9]+)?$", options: .regularExpression) != nil else { return nil }
        return String(segment.dropFirst("android-".count))
    }

    /// `avd.ini.displayname` de `config.ini` quand il existe et n'est pas vide, sinon le nom de l'AVD.
    static func displayName(config: [String: String], avdName: String) -> String {
        let name = config["avd.ini.displayname"]?.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? avdName : name
    }
}

// MARK: - Liste sur le disque (lecture seule)

/// La date de modification d'un fichier du signal « dernière utilisation » (`AndroidEmulatorScanner.lastUsedFiles`).
struct AndroidFileDate: Equatable {
    /// Chemin relatif au dossier de l'AVD.
    let file: String
    let date: Date
}

/// Un appareil virtuel Android, SANS taille (la taille est mesurée à part, dossier par dossier).
struct AndroidDevice: Equatable {
    /// Nom de l'AVD (validé) : la clé de l'appareil, jamais montrée comme clé de catalogue.
    let name: String
    /// `avd.ini.displayname`, sinon le nom de l'AVD.
    let displayName: String
    /// `"36"` ou `"36.1"` ; `nil` : « Unknown system ».
    let systemVersion: String?
    /// Dossier `.avd`, standardisé et sans lien symbolique, STRICTEMENT dans le dossier personnel.
    let folder: URL
    /// Date de dernière utilisation (proposition, voir `AndroidEmulatorScanner.lastUsedFiles`), `nil` si inconnue.
    let lastUsed: Date?
    /// Le fichier (relatif au dossier de l'AVD) qui a donné la date, `nil` si inconnue. Affiché par `--scan`.
    let lastUsedSource: String?
    /// Un processus tourne avec `-avd <nom>` (rempli par `AndroidEmulatorScanner.list`).
    let isRunning: Bool
    /// La date de CHAQUE fichier de `lastUsedFiles` qui existe, dans l'ordre de la constante (pour que l'auteur compare
    /// fichier par fichier avec `--scan`). Vide : aucun de ces fichiers.
    let fileDates: [AndroidFileDate]
    /// Les AUTRES inscriptions (`<nom>.ini`) qui désignent le même dossier, dans l'ordre des noms : une ligne par dossier, mais un
    /// émulateur lancé sous l'un de ces noms rend le dossier « en cours d'exécution » (la suppression de SL11 refuse toute
    /// inscription en cours d'exécution).
    let aliases: [String]
    /// La valeur brute de `image.sysdir.1` de `config.ini`, `nil` si absente (SL12a : sert à rattacher l'appareil à une image système).
    let imageSysdir: String?

    init(name: String, displayName: String, systemVersion: String?, folder: URL, lastUsed: Date?, lastUsedSource: String?,
         isRunning: Bool = false, fileDates: [AndroidFileDate] = [], aliases: [String] = [], imageSysdir: String? = nil) {
        self.name = name
        self.displayName = displayName
        self.systemVersion = systemVersion
        self.folder = folder
        self.lastUsed = lastUsed
        self.lastUsedSource = lastUsedSource
        self.isRunning = isRunning
        self.fileDates = fileDates
        self.aliases = aliases
        self.imageSysdir = imageSysdir
    }

    /// L'ordre des appareils Android, PARTAGÉ (listage, départage des suggestions, lignes pendant la mesure) : nom affiché sans tenir
    /// compte de la casse, puis nom d'AVD.
    static func isOrderedBefore(_ a: AndroidDevice, _ b: AndroidDevice) -> Bool {
        let (x, y) = (a.displayName.lowercased(), b.displayName.lowercased())
        return x != y ? x < y : a.name < b.name
    }

    func withRunning(_ running: Bool) -> AndroidDevice {
        AndroidDevice(name: name, displayName: displayName, systemVersion: systemVersion, folder: folder,
                      lastUsed: lastUsed, lastUsedSource: lastUsedSource, isRunning: running, fileDates: fileDates, aliases: aliases, imageSysdir: imageSysdir)
    }

    func withAliases(_ aliases: [String]) -> AndroidDevice {
        AndroidDevice(name: name, displayName: displayName, systemVersion: systemVersion, folder: folder,
                      lastUsed: lastUsed, lastUsedSource: lastUsedSource, isRunning: isRunning, fileDates: fileDates, aliases: aliases, imageSysdir: imageSysdir)
    }
}

/// Résultat de la lecture de `<home>/.android/avd` : l'état, et les appareils SANS taille.
struct AndroidAVDListing: Equatable {
    enum Status: Equatable {
        /// Lu (éventuellement vide, aussi quand le dossier `avd` n'existe pas).
        case ok
        /// Le dossier existe mais ne peut pas être listé.
        case unreadable
    }

    let status: Status
    let devices: [AndroidDevice]
    /// Inscriptions (`<nom>.ini` de nom valide) qui n'ont donné aucun appareil : dossier absent, hors du dossier personnel,
    /// qui ne ressemble pas à un AVD, ou déjà pris par une autre inscription. Un décompte, jamais de nom ni de chemin.
    var skippedCount = 0
}

extension AndroidEmulatorScanner {
    /// Les fichiers que l'émulateur écrit quand l'appareil tourne, relatifs au dossier de l'AVD. Le signal « dernière utilisation »
    /// est la date de modification la plus récente parmi eux (PROPOSITION de SL10, à confirmer par l'auteur : un changement
    /// après la revue tient en cette seule constante). `config.ini`, `multiinstance.lock` et le `.ini` sont EXCLUS exprès :
    /// Android Studio écrit les deux premiers sans que l'appareil serve, et le verrou existe même quand rien ne tourne (ADR 0009).
    static let lastUsedFiles = [
        "hardware-qemu.ini", "emulator-user.ini", "userdata-qemu.img.qcow2", "userdata-qemu.img",
        "cache.img.qcow2", "snapshots/default_boot/snapshot.pb",
    ]

    /// Borne de lecture d'un `.ini` ou d'un `config.ini` : 1 Mio. Au-delà, ou illisible, le fichier compte comme absent.
    static let iniSizeLimit = 1_048_576

    /// Lit `<home>/.android/avd` : un appareil par `<nom>.ini` (nom valide), dont le dossier est dans le dossier personnel.
    /// LECTURE SEULE, synchrone, sans taille. Triés par nom affiché (sans tenir compte de la casse), puis par nom d'AVD.
    /// - Un `.avd` sans son `.ini` est ignoré ; un `.ini` sans dossier utilisable est ignoré.
    /// - Le dossier : le premier existant parmi `path=` (absolu seulement), `path.rel` (contre `<home>/.android`), puis
    ///   `<home>/.android/avd/<nom>.avd` ; il doit être strictement dans le dossier personnel (ADR 0009, règle 1) ET ressembler à un
    ///   dossier d'AVD (`looksLikeAVDFolder`), sinon l'AVD est ignoré (sans essayer un autre candidat). Deux `.ini` vers le même
    ///   dossier : une seule ligne.
    static func listAVDs(home: URL) -> AndroidAVDListing {
        let androidFolder = home.appendingPathComponent(".android", isDirectory: true)
        let avdFolder = androidFolder.appendingPathComponent("avd", isDirectory: true)

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: avdFolder.path, isDirectory: &isDirectory) else {
            return AndroidAVDListing(status: .ok, devices: [])
        }
        guard isDirectory.boolValue, let entries = try? FileManager.default.contentsOfDirectory(atPath: avdFolder.path) else {
            return AndroidAVDListing(status: .unreadable, devices: [])
        }

        let homePath = resolvedPath(home)
        var devices: [AndroidDevice] = []
        // Dossiers déjà pris (chemin résolu) : deux `.ini` vers le même dossier ne donnent qu'une ligne (le premier par nom).
        var firstIndexByFolder: [String: Int] = [:]
        var skipped = 0
        for entry in entries.sorted() where entry.hasSuffix(".ini") {
            let name = String(entry.dropLast(".ini".count))
            guard isValidAVDName(name) else { continue }
            let registration = readINI(avdFolder.appendingPathComponent(entry)) ?? [:]
            guard let folder = deviceFolder(name: name, registration: registration, androidFolder: androidFolder, avdFolder: avdFolder),
                  isStrictlyInside(folder, homePath: homePath), looksLikeAVDFolder(folder) else {
                skipped += 1
                continue
            }
            // Deux inscriptions vers le même dossier : une seule ligne (la première par nom), l'autre nom devient un alias.
            if let first = firstIndexByFolder[resolvedPath(folder)] {
                devices[first] = devices[first].withAliases(devices[first].aliases + [name])
                skipped += 1
                continue
            }
            firstIndexByFolder[resolvedPath(folder)] = devices.count
            let config = readINI(folder.appendingPathComponent("config.ini")) ?? [:]
            let dates = fileDates(in: folder)
            let used = dates.max { $0.date < $1.date }
            devices.append(AndroidDevice(name: name,
                                         displayName: displayName(config: config, avdName: name),
                                         systemVersion: systemVersion(imageSysdir: config["image.sysdir.1"]),
                                         folder: folder.resolvingSymlinksInPath().standardizedFileURL,
                                         lastUsed: used?.date, lastUsedSource: used?.file, fileDates: dates,
                                         imageSysdir: config["image.sysdir.1"]))
        }
        devices.sort(by: AndroidDevice.isOrderedBefore)
        return AndroidAVDListing(status: .ok, devices: devices, skippedCount: skipped)
    }

    /// Le premier candidat qui est un dossier existant (`path=` absolu, `path.rel`, dossier par défaut). `nil` sinon.
    static func deviceFolder(name: String, registration: [String: String], androidFolder: URL, avdFolder: URL) -> URL? {
        var candidates: [URL] = []
        if let path = registration["path"], path.hasPrefix("/") { candidates.append(URL(fileURLWithPath: path, isDirectory: true)) }
        if let rel = registration["path.rel"], !rel.isEmpty, !rel.hasPrefix("/") {
            candidates.append(androidFolder.appendingPathComponent(rel, isDirectory: true))
        }
        candidates.append(avdFolder.appendingPathComponent("\(name).avd", isDirectory: true))
        return candidates.first { url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
    }

    private static func resolvedPath(_ url: URL) -> String { url.resolvingSymlinksInPath().standardizedFileURL.path }

    /// Le dossier ressemble à un dossier d'AVD : son nom (résolu) finit par `.avd` ET il contient un `config.ini` ordinaire.
    /// Le suffixe est `.avd` en minuscules exactement (les outils d'Android l'écrivent ainsi ; une autre casse est rejetée : on se
    /// trompe du côté sûr), et seule la forme RÉSOLUE compte (un lien nommé `X.avd` vers un autre dossier est rejeté).
    /// Règle la plus stricte qui reste sûre pour les vraies dispositions : `avdmanager` et Android Studio créent toujours
    /// `<nom>.avd/config.ini`. Un `.ini` qui désigne `~/Documents` ou `../x` n'est donc jamais une cible (SL11 en fait la cible
    /// d'une suppression, après l'avoir relue).
    /// Le LISTAGE accepte un dossier atteint par un lien symbolique (le chemin résolu compte) ; la SUPPRESSION (`prepareRemoval`) le
    /// refuse : supprimer le dossier visé laisserait un lien cassé, l'appareil reste visible mais n'est pas supprimé. Un AVD déplacé par `ANDROID_AVD_HOME` hors du dossier personnel reste hors périmètre (le dossier fixe
    /// est `<home>/.android/avd`) ; déplacé DANS le dossier personnel, il est accepté s'il respecte cette règle.
    private static func looksLikeAVDFolder(_ folder: URL) -> Bool {
        let resolved = folder.resolvingSymlinksInPath().standardizedFileURL
        guard resolved.lastPathComponent.hasSuffix(".avd"), resolved.lastPathComponent != ".avd" else { return false }
        var info = stat()
        return stat(resolved.appendingPathComponent("config.ini").path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFREG
    }

    /// Le dossier, standardisé et sans lien symbolique, est STRICTEMENT dans le dossier personnel (jamais le dossier lui-même).
    private static func isStrictlyInside(_ folder: URL, homePath: String) -> Bool {
        let path = resolvedPath(folder)
        let prefix = homePath.hasSuffix("/") ? homePath : homePath + "/"
        return path.count > prefix.count && path.hasPrefix(prefix)
    }

    /// Lit et analyse un fichier INI : fichier ordinaire de 1 Mio au plus, UTF-8 valide. Sinon `nil` (le fichier compte comme absent).
    static func readINI(_ url: URL) -> [String: String]? {
        var info = stat()
        guard stat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_size <= iniSizeLimit,
              let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        // Une lecture de plus que la borne : un fichier qui a grossi entre-temps compte aussi comme trop gros.
        guard let data = try? handle.read(upToCount: iniSizeLimit + 1), data.count <= iniSizeLimit else { return nil }
        return parseINI(data)
    }

    /// La date de modification (contenu) de chaque fichier de `lastUsedFiles` qui existe (fichiers ordinaires, liens suivis),
    /// dans l'ordre de la constante. Le signal est la plus récente ; à égalité, le premier de la liste.
    private static func fileDates(in folder: URL) -> [AndroidFileDate] {
        var result: [AndroidFileDate] = []
        for file in lastUsedFiles {
            var info = stat()
            guard stat(folder.appendingPathComponent(file).path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { continue }
            let date = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec) + TimeInterval(info.st_mtimespec.tv_nsec) / 1e9)
            result.append(AndroidFileDate(file: file, date: date))
        }
        return result
    }
}

// MARK: - Appareils en cours d'exécution (liste des processus)

extension AndroidEmulatorScanner {
    /// Arguments exacts de `ps` : toutes les lignes de commande, sans limite de largeur, sans en-tête.
    static let processListArguments = ["-axww", "-o", "command="]
    /// Délai de `ps` : 10 secondes (une seule valeur dans le code).
    static let processListTimeLimit: TimeInterval = 10
    /// Borne de la sortie de `ps` : 4 Mio (une seule valeur dans le code).
    static let processListOutputLimit = 4 * 1024 * 1024

    /// Les noms d'AVD en cours d'exécution, d'après le texte de `ps -axww -o command=` (ADR 0009, règle 3).
    /// Chaque ligne est coupée sur les blancs : un mot `-avd` suivi d'un mot donne ce nom ; un mot `@<nom>` (forme courte
    /// `emulator @nom`) compte aussi (prudent : un faux positif rend seulement une ligne non sélectionnable).
    /// Le nom est gardé tel qu'écrit (la comparaison avec un AVD, `isRunning`, ignore la casse) ; seuls les noms valides sont gardés.
    static func runningNames(fromProcessList text: String) -> Set<String> {
        var names = Set<String>()
        for line in text.split(whereSeparator: \.isNewline) {
            let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            for (index, token) in tokens.enumerated() {
                if token == "-avd", index + 1 < tokens.count, isValidAVDName(tokens[index + 1]) {
                    names.insert(tokens[index + 1])
                } else if token.hasPrefix("@"), isValidAVDName(String(token.dropFirst())) {
                    names.insert(String(token.dropFirst()))
                }
            }
        }
        return names
    }

    /// Le nom d'AVD est-il parmi les noms en cours d'exécution ? Comparaison SANS tenir compte de la casse : APFS ne la distingue
    /// pas (un faux positif rend seulement une ligne non sélectionnable ; jamais de préfixe, le nom entier doit être égal).
    static func isRunning(_ name: String, in running: Set<String>) -> Bool {
        let lowered = name.lowercased()
        return running.contains { $0.lowercased() == lowered }
    }

    /// Lance `<psPath> -axww -o command=` et rend les noms en cours d'exécution, ou `nil` (« indisponible ») : chemin absent
    /// (rien n'est lancé), délai dépassé, lancement impossible, refus, code non nul, fin par un signal, sortie tronquée.
    /// La sortie d'erreur n'est jamais lue. Une sortie vide est un ensemble vide, pas « indisponible ».
    /// - Parameter runner: sans valeur par défaut (ADR 0009) : un test ne lance jamais le vrai `ps` par mégarde.
    static func runningAVDNames(runner: CommandRunner, psPath: String?) -> Set<String>? {
        guard let psPath else { return nil }
        let outcome = runner.run(executable: psPath, arguments: processListArguments,
                                 timeLimit: processListTimeLimit, outputLimit: processListOutputLimit)
        guard case .completed(let output) = outcome,
              output.exitCode == 0, output.termination == .exited, !output.truncated else { return nil }
        return runningNames(fromProcessList: String(decoding: output.stdout, as: UTF8.self))
    }
}

// MARK: - Un seul listage : SDK, AVD, processus

/// Résultat d'un listage Android : l'état, les appareils SANS taille (avec `isRunning`), et le SDK trouvé.
struct AndroidListing: Equatable {
    enum Status: Equatable {
        /// Lu (éventuellement aucun appareil).
        case ok
        /// Pas de SDK : le groupe n'existe pas (R18), même s'il reste des AVD.
        case sdkNotFound
        /// Dossier des AVD illisible, ou liste des processus indisponible : « Could not read the Android emulators. »
        case couldNotRead
    }

    let status: Status
    let devices: [AndroidDevice]
    /// Le SDK trouvé (`nil` : `sdkNotFound`). Sa source est affichée par `--scan`.
    let sdk: AndroidSDKLocation?
    /// Inscriptions ignorées (voir `AndroidAVDListing.skippedCount`).
    let skippedCount: Int

    init(status: Status, devices: [AndroidDevice] = [], sdk: AndroidSDKLocation? = nil, skippedCount: Int = 0) {
        self.status = status
        self.devices = devices
        self.sdk = sdk
        self.skippedCount = skippedCount
    }
}

extension AndroidEmulatorScanner {
    /// Le listage complet, synchrone, dans cet ordre :
    /// 1. le SDK (`ToolLocator.androidSDK`) : absent, `sdkNotFound`, rien n'est lu ni lancé ;
    /// 2. les AVD (`listAVDs`) : illisibles, `couldNotRead` ; aucun, `ok` et vide, sans appeler `ps` ;
    /// 3. `ps` : indisponible, `couldNotRead` (un état « en cours » invérifiable n'est jamais proposé) ;
    /// 4. sinon `ok`, chaque appareil portant `isRunning`.
    /// Les tailles sont mesurées par l'appelant (espace alloué, R7), dossier par dossier, avec `AndroidDevice.folder`.
    /// - Parameters:
    ///   - runner: sans valeur par défaut (ADR 0009).
    ///   - psPath: chemin absolu de `ps` (`ToolLocator.processListCandidates`), `nil` s'il est absent.
    ///   - environment: injecté, jamais lu sur la machine ici.
    static func list(runner: CommandRunner, psPath: String?, environment: [String: String], home: URL) -> AndroidListing {
        guard let sdk = ToolLocator.androidSDK(environment: environment, home: home) else {
            return AndroidListing(status: .sdkNotFound)
        }
        let avds = listAVDs(home: home)
        guard avds.status == .ok else { return AndroidListing(status: .couldNotRead, sdk: sdk) }
        if avds.devices.isEmpty { return AndroidListing(status: .ok, sdk: sdk, skippedCount: avds.skippedCount) }
        guard let running = runningAVDNames(runner: runner, psPath: psPath) else {
            return AndroidListing(status: .couldNotRead, sdk: sdk, skippedCount: avds.skippedCount)
        }
        return AndroidListing(status: .ok, devices: avds.devices.map { device in
                                  device.withRunning(([device.name] + device.aliases).contains { isRunning($0, in: running) })
                              }, sdk: sdk,
                              skippedCount: avds.skippedCount)
    }
}

// MARK: - Scan avec tailles (pour `--scan`)

/// Un listage Android avec la taille réelle (espace alloué) de chaque dossier.
struct AndroidScan: Equatable {
    let status: AndroidListing.Status
    let sdk: AndroidSDKLocation?
    let devices: [SizedAndroidDevice]
    /// Inscriptions ignorées (décompte, voir `AndroidAVDListing.skippedCount`).
    var skippedCount = 0
}
