import Foundation

/// Quand faut-il interroger le service d'IP publique ? Une seule fonction pure, à temps injecté (SL19 T4, ADR 0011).
///
/// La recherche reste facultative (réglage coupé par défaut) et passe par le même service et la même session qu'avant.
/// Elle tourne dans deux cas : l'onglet Réseau est ouvert (comme depuis toujours), **ou** le drapeau du pays est affiché dans
/// la barre de menus (réglage activé ET bloc réseau affiché). Rien ne tourne en mode démo ni réglage coupé.
enum PublicIPLookupPolicy {
    /// Une réponse plus vieille que cela est rafraîchie (règle d'origine).
    static let refreshAge: TimeInterval = 300
    /// Écart minimal entre deux tentatives quand le réseau ou le VPN vient de changer (règle d'origine).
    static let changeGap: TimeInterval = 5
    /// Écart minimal entre deux tentatives sans changement (règle d'origine).
    static let steadyGap: TimeInterval = 60
    /// Après un échec, pas de nouvelle tentative avant ce délai quand seul le drapeau demande la recherche (onglet Réseau fermé).
    static let failureBackoff: TimeInterval = 60
    /// Au-delà, le drapeau d'une réponse déjà connue n'est plus affiché : mieux vaut aucun drapeau qu'un drapeau faux.
    static let flagMaxAge: TimeInterval = 3_600
    /// SL25 (ADR 0012) : après une recherche déclenchée par un changement détecté, une seule recherche de confirmation, une dizaine de secondes
    /// plus tard (la première réponse peut encore venir de l'ancienne route). Aucune autre requête de plus.
    static let settleDelay: TimeInterval = 10
    /// SL25 : une empreinte qui vient de changer doit rester la même ce temps-là avant de compter comme un changement détecté
    /// (les événements réseau arrivent en rafale et l'IP publique n'est pas encore la bonne au premier). Même valeur pour le moniteur.
    static let quietPeriod: TimeInterval = 3
    /// SL25 : la toute première recherche du drapeau attend la fin de la détection du VPN (quelques centaines de millisecondes), au plus ce temps-là :
    /// sans cela elle part avec une empreinte incomplète (`vpn` pas encore lu). Passé ce délai, on cherche avec ce qu'on a.
    static let firstLookupWaitCap: TimeInterval = 10

    struct Inputs {
        /// « Show public IP and country » (`SettingsKey.publicIP`).
        var settingOn: Bool
        /// Le bloc réseau est dans la barre de menus (réglage coché ET débit mesuré) : c'est la condition d'affichage du drapeau.
        var networkItemShown: Bool
        var networkTabOpen: Bool
        var demo: Bool
        var state: PublicIPState
        /// Bouton « Actualiser », interrupteur des réglages : toujours permis (réglage activé, pas de démo, pas de recherche en cours).
        var force: Bool
        var fingerprintChanged: Bool
        /// Date de la dernière réponse reçue (`nil` : aucune réponse connue).
        var lastSuccess: Date?
        var lastAttempt: Date
        var lastFailure: Date?
        /// SL25 : date de la dernière recherche déclenchée par un changement détecté, tant que sa confirmation n'a pas eu lieu (`nil` : aucune
        /// confirmation attendue). Absente, la règle est exactement celle d'avant.
        var lastChangeTriggeredLookup: Date? = nil
        var now: Date
    }

    static func shouldLookUp(_ i: Inputs) -> Bool {
        guard !i.demo, i.settingOn, i.state != .loading else { return false }
        // Où : l'onglet Réseau, le drapeau affiché, ou une demande explicite de l'utilisateur.
        guard i.networkTabOpen || i.networkItemShown || i.force else { return false }

        let age = i.lastSuccess.map { i.now.timeIntervalSince($0) } ?? .infinity
        let confirmationDue = isConfirmationDue(i)
        // Les raisons d'origine, puis la confirmation (SL25) : la nouvelle entrée ne fait qu'ajouter une raison.
        let originalReason = i.force || i.lastSuccess == nil || i.fingerprintChanged || age > refreshAge
        let minimumGap: TimeInterval = i.force ? 0 : ((i.fingerprintChanged || confirmationDue) ? changeGap : steadyGap)
        // Garde-fou : un échec ne doit pas provoquer de requêtes en boucle.
        guard originalReason || confirmationDue, i.now.timeIntervalSince(i.lastAttempt) >= minimumGap else { return false }

        // Pause après échec : pour le drapeau (l'onglet Réseau garde exactement ses règles d'origine), et pour la seule confirmation, où que ce soit.
        let backoffApplies = !i.force && (!i.networkTabOpen || !originalReason)
        if backoffApplies, let failure = i.lastFailure, i.now.timeIntervalSince(failure) < failureBackoff { return false }
        return true
    }

    static func isConfirmationDue(_ i: Inputs) -> Bool {
        i.lastChangeTriggeredLookup.map { i.now.timeIntervalSince($0) >= settleDelay } ?? false
    }

    /// Faut-il surveiller le réseau (événements, réveil) ? Exactement quand une recherche peut être demandée sans qu'on la force : réglage activé,
    /// pas de démo, et le drapeau affiché ou l'onglet Réseau ouvert. Sinon, aucun moniteur n'existe.
    static func monitorWanted(settingOn: Bool, demo: Bool, networkItemShown: Bool, networkTabOpen: Bool) -> Bool {
        !demo && settingOn && (networkItemShown || networkTabOpen)
    }

    /// Un changement détecté : forcé (réveil), ou une empreinte différente de celle de la dernière recherche **et** stable depuis
    /// `quietPeriod`. Exceptions : la première recherche (rien à stabiliser) et l'onglet Réseau, qui garde sa règle d'origine (tout de suite).
    static func fingerprintChanged(_ current: String, _ attempted: String, _ settled: Bool, _ forced: Bool, _ tabOpen: Bool) -> Bool {
        if forced { return true }
        guard current != attempted else { return false }
        return attempted.isEmpty || settled || tabOpen
    }

    /// La première recherche attend-elle la fin de la détection du VPN ? Seulement pour le drapeau (l'onglet Réseau et un appel forcé cherchent tout de
    /// suite), seulement tant qu'aucune base n'existe, et au plus `firstLookupWaitCap` depuis le début de l'attente.
    static func mustWaitForFirstFingerprint(hadBaseline: Bool, vpnDetectionPending: Bool, tabOpen: Bool, force: Bool,
                                            waitingSince: Date?, now: Date) -> Bool {
        guard !hadBaseline, vpnDetectionPending, !tabOpen, !force else { return false }
        return now.timeIntervalSince(waitingSince ?? now) < firstLookupWaitCap
    }

    /// Pourquoi une recherche part (journal `SOARO_DEBUG`).
    enum LookupReason: String {
        case forced, wake, first, periodic, confirmation
        case networkChange = "network-change"
        /// Une recherche qui suit un changement détecté, donc suivie d'une confirmation.
        var isChangeTriggered: Bool { self == .wake || self == .networkChange }
    }

    static func reason(_ i: Inputs, wake: Bool, hadFingerprint: Bool) -> LookupReason {
        if i.force { return .forced }
        if wake { return .wake }
        if i.fingerprintChanged { return hadFingerprint ? .networkChange : .first }
        if isConfirmationDue(i) { return .confirmation }
        if i.lastSuccess == nil { return .first }
        return .periodic
    }

    /// Empreinte de la connexion : une autre adresse locale ou un VPN qui change = une nouvelle recherche.
    /// Depuis SL25 : et les signaux locaux (`NetworkSignals`). Sans signal, la chaîne est exactement celle d'avant.
    static func fingerprint(localIP: String?, vpn: VPNStatus?, signals: NetworkSignals = .empty) -> String {
        "\(localIP ?? "-")|\(vpn?.isActive == true ? "vpn" : "none")|\(vpn?.interface ?? "-")|\(vpn?.name ?? "-")" + signals.fingerprintPart
    }
}

/// Une empreinte qui vient de changer ne compte qu'une fois restée la même `quietPeriod` secondes (fonction pure, temps injecté).
struct FingerprintSettler: Equatable {
    private var candidate: String?
    private var since = Date.distantPast

    /// À appeler à chaque évaluation. Vrai quand l'empreinte n'a pas bougé depuis `quietPeriod`.
    mutating func observe(_ fingerprint: String, now: Date) -> Bool {
        if fingerprint != candidate { candidate = fingerprint; since = now }
        return now.timeIntervalSince(since) >= PublicIPLookupPolicy.quietPeriod
    }

    /// Le moniteur a déjà attendu le délai de calme : cette empreinte est stable.
    mutating func accept(_ fingerprint: String) {
        candidate = fingerprint
        since = .distantPast
    }
}
