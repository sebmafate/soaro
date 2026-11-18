import CoreText
import Foundation

/// Le drapeau du pays de l'IP publique dans la barre de menus (SL19).
/// Il ne lit QUE ce que la recherche facultative a déjà trouvé (réglage « Show public IP and country », coupé par défaut) :
/// il ne lance rien, ne demande rien à personne et n'a pas de réglage à lui.
enum MenuBarFlag {
    /// Corps du drapeau dans le libellé de 22 pt de haut, à côté du texte de 9 pt des débits (compact) ou de 13 pt (classique).
    static let fontSize: CGFloat = 12.5

    /// « FR » → 🇫🇷, ou `nil` si le code n'est pas valide **ou** si la police d'émojis n'a pas de drapeau pour lui :
    /// « XX » donnerait deux lettres encadrées côte à côte, une case de remplacement qu'on préfère ne pas afficher.
    static func emoji(forCountryCode code: String?) -> String? {
        guard let flag = PublicIPService.flagEmoji(code), hasSingleGlyph(flag) else { return nil }
        return flag
    }

    /// Le code à montrer, en majuscules, ou `nil`. Le réglage doit être activé (une valeur restée en mémoire ne suffit pas),
    /// sauf en mode démo où l'IP publique de démonstration (la France) s'affiche, sans rien demander à personne.
    /// Hors démo, la réponse doit venir de la connexion actuelle (`matchesNetwork`) et avoir au plus `flagMaxAge` : au-delà, aucun
    /// drapeau plutôt qu'un drapeau faux (la recherche a échoué, ou le VPN a changé et la nouvelle réponse n'est pas encore là).
    static func countryCode(lookupEnabled: Bool, demo: Bool, info: PublicIPInfo?, matchesNetwork: Bool, now: Date) -> String? {
        guard lookupEnabled || demo, let info, let code = info.countryCode?.uppercased(), emoji(forCountryCode: code) != nil else { return nil }
        if demo { return code }
        let age = now.timeIntervalSince(info.fetchedAt)
        guard matchesNetwork, age >= 0, age <= PublicIPLookupPolicy.flagMaxAge else { return nil }
        return code
    }

    /// Une paire d'indicateurs régionaux sans drapeau s'affiche en deux glyphes (deux lettres encadrées) ; un vrai drapeau en un seul.
    private static func hasSingleGlyph(_ flag: String) -> Bool {
        let font = CTFontCreateWithName("Apple Color Emoji" as CFString, fontSize, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: flag, attributes: [.font: font]))
        let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
        return runs.reduce(0) { $0 + CTRunGetGlyphCount($1) } == 1
    }
}
