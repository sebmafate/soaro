import Foundation

/// Suppression d'un appareil virtuel Android (SL11, R17, ADR 0009 règles 3, 4, 6, 7, 8) : seul fichier Android qui supprime.
/// Ordre, par cible : le plan AU MOMENT DE L'ACTION (`prepareRemoval` : listage frais et portée, sans effet), la mesure avant, un `ps`
/// frais (`runningCheck`), la suppression du dossier puis des `.ini` par `AndroidEmulatorRemover.removeFile` (qui revérifie le chemin),
/// la mesure après.

/// Ce que l'utilisateur a confirmé : le nom de l'AVD et le dossier vu au scan (`AndroidDevice.folder`, déjà résolu).
struct AndroidRemovalTarget: Equatable {
    let name: String
    let folder: URL
}

/// Ce qui sera supprimé pour une cible, d'après un listage FRAIS (jamais le chemin du scan).
struct AndroidRemovalPlan: Equatable {
    /// Nom affiché, du listage frais.
    let displayName: String
    /// Tous les noms qui désignent ce dossier : le nom de l'appareil, puis ses alias (dans l'ordre des noms).
    let names: [String]
    /// Le dossier `.avd`, résolu et standardisé.
    let folder: URL
    /// Les `<home>/.android/avd/<nom>.ini` de chaque nom de `names`, dans le même ordre.
    let registrations: [URL]
}

/// Résultat de la préparation : un plan, ou une issue sans action.
enum AndroidRemovalPreparation: Equatable {
    case plan(AndroidRemovalPlan)
    /// Plus d'inscription ni d'appareil : quelqu'un l'a déjà supprimé. Ce n'est pas un échec.
    case alreadyGone
    /// La cible a changé ou sort du périmètre sûr : rien n'est supprimé.
    case refused
    /// Le dossier des AVD n'a pas pu être lu : rien n'est supprimé.
    case couldNotCheck
}

extension AndroidEmulatorScanner {
    /// Retrouve la cible dans un listage FRAIS de `<home>/.android/avd` (le chemin du scan n'est jamais cru). Pur, synchrone, sans effet.
    /// Règles, dans l'ordre :
    /// 1. listage illisible : `couldNotCheck` ;
    /// 2. appareil dont le nom (ou un alias) est exactement celui de la cible. Absent : `alreadyGone` si `<nom>.ini` n'existe plus,
    ///    sinon `refused` (chemin qui sort du dossier personnel, dossier qui n'est plus un AVD, dossier absent) ;
    /// 3. dossier frais (résolu, standardisé) différent de celui du scan : `refused` (lien échangé ou `.ini` réécrit) ;
    /// 4. chaque chemin du plan (le dossier ET tous les `.ini`) passe `CleanupService.isSafeToDelete` (le vrai dossier personnel,
    ///    ADR 0006) : sinon `refused`.
    /// - Un nom qui n'est pas un nom d'AVD valide n'est jamais joint à un chemin : `refused`.
    static func prepareRemoval(home: URL, target: AndroidRemovalTarget) -> AndroidRemovalPreparation {
        guard isValidAVDName(target.name) else { return .refused }
        let listing = listAVDs(home: home)
        guard listing.status == .ok else { return .couldNotCheck }

        let avdFolder = home.appendingPathComponent(".android/avd", isDirectory: true)
        guard let device = listing.devices.first(where: { ([$0.name] + $0.aliases).contains(target.name) }) else {
            // Un lien (même cassé) ou un fichier nommé `<nom>.ini` compte comme présent : on se trompe du côté sûr.
            var info = stat()
            let registration = avdFolder.appendingPathComponent("\(target.name).ini")
            return lstat(registration.path, &info) == 0 ? .refused : .alreadyGone
        }

        let freshFolder = device.folder.resolvingSymlinksInPath().standardizedFileURL
        // Le dossier du scan est DÉJÀ résolu : le résoudre de nouveau maintenant suivrait un lien posé depuis, et le contrôle ne verrait rien.
        let seenFolder = target.folder.standardizedFileURL
        guard freshFolder.path == seenFolder.path else { return .refused }

        let names = [device.name] + device.aliases
        let registrations = names.map { avdFolder.appendingPathComponent("\($0).ini") }
        guard CleanupService.isSafeToDelete(freshFolder), registrations.allSatisfy(CleanupService.isSafeToDelete) else { return .refused }
        // Le dossier ne passe par aucun lien symbolique côté inscription (le dernier composant du chemin enregistré, pour chaque nom) :
        // sinon on supprimerait le dossier visé et on laisserait un lien cassé.
        for (name, registration) in zip(names, registrations) {
            let registered = deviceFolder(name: name, registration: readINI(registration) ?? [:],
                                          androidFolder: home.appendingPathComponent(".android", isDirectory: true), avdFolder: avdFolder)
            var info = stat()
            // Un chemin enregistré qui n'est pas sous sa forme standard (composant `.` ou `..`, `//`) est refusé : `lstat` sur `Lien.avd/.`
            // suit le lien et le ferait passer pour un vrai dossier. Une barre finale seule est acceptée (l'URL la normalise à l'identique).
            guard let registered, registered.path == registered.standardizedFileURL.path,
                  lstat(registered.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR else { return .refused }
        }
        // Le dossier ne contient ni un autre AVD du listage ni le dossier des inscriptions (le supprimer les emporterait).
        let inside = freshFolder.path + "/"
        let avdPath = avdFolder.resolvingSymlinksInPath().standardizedFileURL.path
        let others = listing.devices.filter { $0.name != device.name }
        guard !avdPath.hasPrefix(inside), !others.contains(where: { $0.folder.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(inside) })
        else { return .refused }
        // Chaque inscription est un fichier ordinaire (ou un lien vers un fichier) : un DOSSIER nommé `<nom>.ini` serait supprimé
        // récursivement.
        guard registrations.allSatisfy(isRegistrationFile) else { return .refused }
        return .plan(AndroidRemovalPlan(displayName: device.displayName, names: names, folder: freshFolder, registrations: registrations))
    }
}

extension AndroidEmulatorScanner {
    /// Un fichier ordinaire, ou un lien symbolique vers un fichier ordinaire. Tout le reste (dossier, fichier spécial, lien cassé) : non.
    static func isRegistrationFile(_ url: URL) -> Bool {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return false }
        switch info.st_mode & S_IFMT {
        case S_IFREG: return true
        case S_IFLNK: return stat(url.path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFREG
        default: return false
        }
    }
}

// MARK: - Vérification des processus (juste avant de supprimer)

extension AndroidEmulatorScanner {
    /// Un `ps` FRAIS (une fois par cible), à faire le plus près possible de la suppression (ADR 0009, règles 3 et 4) :
    /// indisponible (chemin absent, délai, échec, refus, code non nul, signal, sortie tronquée) : `couldNotCheck` ; un nom quelconque du
    /// plan (le nom ou un alias) en cours d'exécution : `running(nom affiché frais)`. `nil` : rien ne tourne, on peut supprimer.
    /// Un délai de `ps` n'est JAMAIS un « délai dépassé » (ce résultat parle du service des simulateurs iOS) : c'est « impossible de vérifier ».
    /// - Parameter runner: sans valeur par défaut (ADR 0009).
    static func runningCheck(runner: CommandRunner, psPath: String?, plan: AndroidRemovalPlan) -> SimulatorRemovalResult? {
        guard let running = runningAVDNames(runner: runner, psPath: psPath) else { return .couldNotCheck }
        return plan.names.contains(where: { isRunning($0, in: running) }) ? .running(name: plan.displayName) : nil
    }
}

// MARK: - Suppression du couple et espace libéré

/// Le suppresseur réel : le SEUL endroit des fichiers Android qui supprime quoi que ce soit (un test de source le vérifie).
/// Suppression directe, pas la corbeille (D8 : la corbeille ne libérerait rien ; ADR 0006 supprime directement ce qui se reconstruit).
enum AndroidEmulatorRemover {
    /// Le chemin a changé ou sort de ce qui est sûr depuis le plan : rien n'est supprimé.
    struct Refusal: Error, Equatable {}

    /// Supprime un dossier d'AVD ou un `.ini`, APRÈS avoir revérifié, juste avant (le plan date d'avant la mesure et de `ps`, qui durent) :
    /// - le chemin passe `CleanupService.isSafeToDelete` (strictement dans le vrai dossier personnel, liens résolus) ;
    /// - un DOSSIER : un vrai dossier (pas un lien posé depuis), dont le chemin est son propre chemin résolu (le plan donne le dossier
    ///   résolu : un lien posé sur un parent le change), nommé `*.avd`, avec un `config.ini` ordinaire ;
    /// - une inscription : un fichier ordinaire (ou un lien vers un fichier ordinaire, `isRegistrationFile`) nommé `*.ini` : jamais un
    ///   dossier, qui serait supprimé récursivement.
    /// Sinon il lève `Refusal` et ne supprime rien.
    static func removeFile(_ url: URL) throws {
        guard CleanupService.isSafeToDelete(url) else { throw Refusal() }
        var info = stat()
        guard lstat(url.path, &info) == 0 else { throw Refusal() }
        let name = url.lastPathComponent
        switch info.st_mode & S_IFMT {
        case S_IFDIR:
            var config = stat()
            guard name.hasSuffix(".avd"), name != ".avd",
                  url.resolvingSymlinksInPath().standardizedFileURL.path == url.standardizedFileURL.path,
                  stat(url.appendingPathComponent("config.ini").path, &config) == 0, (config.st_mode & S_IFMT) == S_IFREG
            else { throw Refusal() }
        case S_IFREG, S_IFLNK:
            guard name.hasSuffix(".ini"), AndroidEmulatorScanner.isRegistrationFile(url) else { throw Refusal() }
        default:
            throw Refusal()
        }
        try FileManager.default.removeItem(at: url)
    }
}

extension AndroidEmulatorScanner {
    /// Supprime UN appareil, dans cet ordre, synchrone (jamais sur l'acteur principal) :
    /// 1. `prepareRemoval` : listage frais, portée, nature des fichiers ; refusé, déjà disparu, illisible : on s'arrête, rien n'est lancé
    ///    ni mesuré ;
    /// 2. taille avant : le dossier, plus chaque `.ini` du plan (lecture seule, et la longue étape : elle précède `ps`) ;
    /// 3. `ps` FRAIS (`runningCheck`), le plus près possible de la suppression : un émulateur lancé pendant la mesure est vu. En cours
    ///    d'exécution ou impossible à vérifier : on s'arrête, rien n'est supprimé (la mesure d'avant a eu lieu, elle ne change rien).
    ///    Il reste une fenêtre de quelques microsecondes entre la dernière vérification de `removeFile` et `removeItem` (un autre processus
    ///    du même utilisateur qui écrit dans le dossier personnel) : acceptée, la fermer demanderait une suppression relative à un dossier
    ///    ouvert ;
    /// 4. le DOSSIER d'abord (D3). S'il échoue, ou s'il existe encore : `failed`, AUCUN `.ini` n'est supprimé. L'appareil reste listé et
    ///    réessayable TANT QUE le dossier est encore un dossier d'AVD valide (il contient son `config.ini`) ; un dossier supprimé en partie
    ///    (`config.ini` déjà parti) n'est plus listé et son `.ini` reste (l'inverse, les `.ini` d'abord, laisserait un dossier orphelin invisible) ;
    /// 5. puis chaque `.ini` du plan (le principal, puis les alias par nom) ; tous sont essayés, un seul échec donne `failed`. Attention :
    ///    si le dossier est parti mais qu'un `.ini` échoue, ce `.ini` reste orphelin (Soaro ne le liste plus, Android Studio le montre cassé) ;
    /// 6. si tout a disparu : taille après, `removed(freed: avant moins après)`, plancher à zéro (R7).
    /// Un échec n'ajoute rien à l'espace libéré, même si une partie a été supprimée (D7 : on sous-estime, on ne promet jamais trop).
    /// Jamais touchés : l'appareil voisin, le dossier `avd` lui-même, tout autre fichier. Aucun outil du SDK, aucun interpréteur ; le seul
    /// appel au lanceur est `ps`. Un appareil Android ne rend jamais `timedOut`.
    /// - Parameters:
    ///   - runner: sans valeur par défaut (ADR 0009).
    ///   - psPath: chemin absolu de `ps` (`ToolLocator.processListCandidates`), `nil` s'il est absent.
    ///   - removeFile: sans valeur par défaut ici ; le modèle donne `AndroidEmulatorRemover.removeFile`, qui revérifie le chemin.
    static func remove(runner: CommandRunner,
                       psPath: String?,
                       home: URL,
                       measure: (URL) -> UInt64,
                       removeFile: (URL) throws -> Void,
                       target: AndroidRemovalTarget) -> SimulatorRemovalResult {
        let plan: AndroidRemovalPlan
        switch prepareRemoval(home: home, target: target) {
        case .alreadyGone: return .alreadyGone
        case .refused: return .refused
        case .couldNotCheck: return .couldNotCheck
        case .plan(let found): plan = found
        }

        let paths = [plan.folder] + plan.registrations
        let before = paths.reduce(UInt64(0)) { $0 + measure($1) }

        if let stop = runningCheck(runner: runner, psPath: psPath, plan: plan) { return stop }

        do { try removeFile(plan.folder) } catch { return .failed }
        guard !exists(plan.folder) else { return .failed }

        var failed = false
        for registration in plan.registrations {
            do { try removeFile(registration) } catch { failed = true }
            if exists(registration) { failed = true }
        }
        guard !failed else { return .failed }

        let after = paths.reduce(UInt64(0)) { $0 + measure($1) }
        return .removed(freed: before > after ? before - after : 0)
    }

    /// Le chemin existe encore (un lien, même cassé, compte comme présent).
    private static func exists(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0
    }
}
