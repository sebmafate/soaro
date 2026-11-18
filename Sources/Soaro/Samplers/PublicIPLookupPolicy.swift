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
        var now: Date
    }

    static func shouldLookUp(_ i: Inputs) -> Bool {
        guard !i.demo, i.settingOn, i.state != .loading else { return false }
        // Où : l'onglet Réseau, le drapeau affiché, ou une demande explicite de l'utilisateur.
        guard i.networkTabOpen || i.networkItemShown || i.force else { return false }

        let age = i.lastSuccess.map { i.now.timeIntervalSince($0) } ?? .infinity
        let needsRefresh = i.force || i.lastSuccess == nil || i.fingerprintChanged || age > refreshAge
        // Garde-fou : un échec ne doit pas provoquer de requêtes en boucle.
        let minimumGap: TimeInterval = i.force ? 0 : (i.fingerprintChanged ? changeGap : steadyGap)
        guard needsRefresh, i.now.timeIntervalSince(i.lastAttempt) >= minimumGap else { return false }

        // Pause après échec : seulement pour le drapeau (l'onglet Réseau garde exactement ses règles d'origine).
        if !i.networkTabOpen, !i.force, let failure = i.lastFailure, i.now.timeIntervalSince(failure) < failureBackoff { return false }
        return true
    }

    /// Empreinte de la connexion : une autre adresse locale ou un VPN qui change = une nouvelle recherche.
    static func fingerprint(localIP: String?, vpn: VPNStatus?) -> String {
        "\(localIP ?? "-")|\(vpn?.isActive == true ? "vpn" : "none")|\(vpn?.interface ?? "-")|\(vpn?.name ?? "-")"
    }
}
