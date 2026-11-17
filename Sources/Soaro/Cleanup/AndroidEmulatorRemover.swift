import Foundation

/// Suppression d'un appareil virtuel Android (SL11, R17, ADR 0009 règles 3, 4, 6, 7, 8).
/// Cette première partie : retrouver la cible AU MOMENT DE L'ACTION. Lecture seule : rien n'est lancé, mesuré ni supprimé.

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
        return .plan(AndroidRemovalPlan(displayName: device.displayName, names: names, folder: freshFolder, registrations: registrations))
    }
}

// MARK: - Vérification juste avant d'agir (processus en cours)

/// Ce qui suit la vérification d'une cible : continuer avec le plan, ou s'arrêter avec un résultat (rien n'est alors mesuré ni supprimé).
enum AndroidRemovalCheck: Equatable {
    case proceed(AndroidRemovalPlan)
    case stop(SimulatorRemovalResult)
}

extension AndroidEmulatorScanner {
    /// Les deux vérifications qui précèdent toute mesure et toute suppression d'une cible, dans cet ordre (ADR 0009, règles 3 et 4) :
    /// 1. le listage frais (`prepareRemoval`) : déjà disparu, refusé ou illisible : on s'arrête, SANS lancer `ps` ;
    /// 2. un `ps` FRAIS (une fois par cible) : indisponible (chemin absent, délai, échec, refus, code non nul, signal, sortie tronquée) :
    ///    « impossible de vérifier » ; un nom quelconque du plan (le nom ou un alias) en cours d'exécution : `running(nom affiché frais)`.
    /// Un délai de `ps` n'est JAMAIS un « délai dépassé » (ce résultat parle du service des simulateurs iOS) : c'est « impossible de vérifier ».
    /// - Parameter runner: sans valeur par défaut (ADR 0009).
    static func checkBeforeRemoval(runner: CommandRunner, psPath: String?, home: URL, target: AndroidRemovalTarget) -> AndroidRemovalCheck {
        switch prepareRemoval(home: home, target: target) {
        case .alreadyGone: return .stop(.alreadyGone)
        case .refused: return .stop(.refused)
        case .couldNotCheck: return .stop(.couldNotCheck)
        case .plan(let plan):
            guard let running = runningAVDNames(runner: runner, psPath: psPath) else { return .stop(.couldNotCheck) }
            if plan.names.contains(where: { isRunning($0, in: running) }) { return .stop(.running(name: plan.displayName)) }
            return .proceed(plan)
        }
    }
}

// MARK: - Suppression du couple et espace libéré

/// Le suppresseur réel : le SEUL endroit des fichiers Android qui supprime quoi que ce soit (un test de source le vérifie).
/// Suppression directe, pas la corbeille (D8 : la corbeille ne libérerait rien ; ADR 0006 supprime directement ce qui se reconstruit).
enum AndroidEmulatorRemover {
    /// Supprime un fichier ou un dossier. Le chemin a déjà passé `CleanupService.isSafeToDelete` (voir `prepareRemoval`).
    static func removeFile(_ url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
}

extension AndroidEmulatorScanner {
    /// Supprime UN appareil, dans cet ordre, synchrone (jamais sur l'acteur principal) :
    /// 1. `checkBeforeRemoval` : listage frais puis `ps` frais ; refusé, déjà disparu, illisible, en cours d'exécution : on s'arrête, rien n'est
    ///    mesuré ni supprimé ;
    /// 2. taille avant : le dossier, plus chaque `.ini` du plan ;
    /// 3. le DOSSIER d'abord (D3). S'il échoue, ou s'il existe encore : `failed`, AUCUN `.ini` n'est supprimé (l'appareil reste visible et
    ///    peut être réessayé : l'inverse laisserait un dossier orphelin invisible) ;
    /// 4. puis chaque `.ini` du plan (le principal, puis les alias par nom) ; tous sont essayés, un seul échec donne `failed` ;
    /// 5. si tout a disparu : taille après, `removed(freed: avant moins après)`, plancher à zéro (R7).
    /// Un échec n'ajoute rien à l'espace libéré, même si une partie a été supprimée (D7 : on sous-estime, on ne promet jamais trop).
    /// Jamais touchés : l'appareil voisin, le dossier `avd` lui-même, tout autre fichier. Aucun outil du SDK, aucun interpréteur ; le seul
    /// appel au lanceur est `ps`. Un appareil Android ne rend jamais `timedOut`.
    /// - Parameters:
    ///   - runner: sans valeur par défaut (ADR 0009).
    ///   - psPath: chemin absolu de `ps` (`ToolLocator.processListCandidates`), `nil` s'il est absent.
    ///   - removeFile: sans valeur par défaut ici ; le modèle donne `AndroidEmulatorRemover.removeFile`.
    static func remove(runner: CommandRunner,
                       psPath: String?,
                       home: URL,
                       measure: (URL) -> UInt64,
                       removeFile: (URL) throws -> Void,
                       target: AndroidRemovalTarget) -> SimulatorRemovalResult {
        let plan: AndroidRemovalPlan
        switch checkBeforeRemoval(runner: runner, psPath: psPath, home: home, target: target) {
        case .stop(let result): return result
        case .proceed(let found): plan = found
        }

        let paths = [plan.folder] + plan.registrations
        let before = paths.reduce(UInt64(0)) { $0 + measure($1) }

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
