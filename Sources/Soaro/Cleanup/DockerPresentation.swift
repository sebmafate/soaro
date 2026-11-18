import Foundation

/// Textes de l'outil Docker (S4, R8, R10, R12) : fonctions PURES (locale explicite), testables sans vue.
/// Vocabulaire : « build cache », « untagged images », « containers », « volumes », « tag » ; jamais « prune », « dangling » ni « layer ».
enum DockerPresentation {
    // MARK: Titres et lignes

    static var buildCacheTitle: String { String(localized: "Build cache") }
    static var untaggedImagesTitle: String { String(localized: "Untagged images") }
    static var containersTitle: String { String(localized: "Containers") }
    static var volumesTitle: String { String(localized: "Volumes") }
    static var otherImagesTitle: String { String(localized: "Other unused images") }

    static func title(_ prune: DockerPrune) -> String {
        switch prune {
        case .buildCache: buildCacheTitle
        case .untaggedImages: untaggedImagesTitle
        }
    }

    /// La taille, ou « unknown size » quand Docker ne l'a pas donnée (jamais un chiffre deviné).
    static func sizeText(_ size: UInt64?, locale: Locale) -> String {
        size.map { Format.fileBytes($0, locale: locale) } ?? String(localized: "unknown size", locale: locale)
    }

    /// Deuxième ligne d'une ligne cochable.
    static func detail(_ cleanable: DockerCleanable, locale: Locale) -> String {
        switch cleanable.prune {
        case .buildCache:
            return String(localized: "Rebuilt by your next build", locale: locale)
        case .untaggedImages:
            return String(localized: "Images no container uses: \(cleanable.count ?? 0)", locale: locale)
        }
    }

    /// « In use: 2 of 11 », ou `nil` quand Docker ne donne pas les deux nombres.
    static func inUseDetail(_ line: DockerUsageLine, locale: Locale) -> String? {
        guard let total = line.total, let active = line.active else { return nil }
        return String(localized: "In use: \(active) of \(total)", locale: locale)
    }

    /// Deuxième ligne des autres images inutilisées : leur nombre quand il est connu.
    static func otherImagesDetail(_ other: DockerOtherImages, locale: Locale) -> String? {
        other.count.map { String(localized: "Images no container uses: \($0)", locale: locale) }
    }

    static func buildCacheUnknownDetail(locale: Locale) -> String { String(localized: "Docker did not say how big it is", locale: locale) }

    /// Pied de la liste : ce que Soaro ne touche jamais.
    static var neverRemovedFooter: String {
        String(localized: "Containers, volumes and images with a tag are never removed here. Removing a tagged image means downloading it again.")
    }

    /// Note sous le résultat : le chiffre est une mesure, pas une garantie.
    static var measurementNote: String {
        String(localized: "Measured as the change in free space about a minute after the cleanup. Other activity on this Mac can change it.")
    }

    static var nothingToClean: String { String(localized: "Nothing to clean in Docker.") }

    // MARK: Messages d'état

    static var notFoundMessage: String { String(localized: "Docker was not found on this Mac.") }
    static var notRunningMessage: String { String(localized: "Docker is not running. Start it, then scan again.") }
    static var notAnsweringMessage: String { String(localized: "Docker did not answer. Try again in a moment.") }
    static var couldNotReadMessage: String { String(localized: "Could not read Docker’s disk usage.") }
    /// SL16 : le moteur ou le constructeur courant de Docker n'est pas local (ou on n'a pas pu le lire). Rien n'est listé ni nettoyé.
    static var notLocalMessage: String { String(localized: "Soaro only cleans Docker on this Mac. The selected Docker engine or builder is not local.") }
    static var listingMessage: String { String(localized: "Looking at Docker…") }
    static var cleaningMessage: String { String(localized: "Cleaning…") }
    static var measuringMessage: String { String(localized: "Measuring…") }

    // MARK: Confirmation (R8)

    static func confirmationTitle(count: Int, locale: Locale = .current) -> String {
        String(localized: "Clean the selected Docker items? (\(count))", locale: locale)
    }

    /// SL16 : « Docker engine: desktop-linux (~/.docker/run/docker.sock) » : où le nettoyage va tourner.
    static func engineLine(_ engine: DockerEngine, home: URL, locale: Locale = .current) -> String {
        String(localized: "Docker engine: \(engine.contextName) (\(displayPath(engine.socketPath, home: home)))", locale: locale)
    }

    /// Le chemin, avec le dossier personnel écrit « ~ » quand le chemin est dans ce dossier (nom de dossier entier : « /Users/test2 » n'est pas
    /// sous « /Users/test »). Rien n'est abrégé pour la racine.
    static func displayPath(_ path: String, home: URL) -> String {
        var base = home.path
        while base.count > 1, base.hasSuffix("/") { base.removeLast() }
        guard base.count > 1 else { return path }
        if path == base { return "~" }
        if path.hasPrefix(base + "/") { return "~" + path.dropFirst(base.count) }
        return path
    }

    /// Ce qui est retiré, avec sa taille ; le moteur sur lequel cela tourne (SL16) ; que la prochaine compilation sera plus lente quand le cache
    /// de build est coché ; ce qui n'est jamais touché. Les noms des lignes sont les mêmes que sur l'écran.
    static func confirmationMessage(targets: [DockerCleanable], engine: DockerEngine, home: URL, locale: Locale = .current) -> String {
        let allKnown = targets.allSatisfy { $0.size != nil }
        let known = DockerSize.saturatingSum(targets.map { $0.size ?? 0 })
        let intro = allKnown
            ? String(localized: "About \(Format.fileBytes(known, locale: locale)) will be removed:", locale: locale)
            : String(localized: "These will be removed:", locale: locale)
        let bullets = targets.map { "• \(title($0.prune)) · \(sizeText($0.size, locale: locale))" }.joined(separator: "\n")
        var closing: [String] = []
        if targets.contains(where: { $0.prune == .buildCache }) {
            closing.append(String(localized: "The next build will be slower, because the cache is rebuilt.", locale: locale))
        }
        closing.append(String(localized: "Containers, volumes and images with a tag are not touched.", locale: locale))
        return "\(intro)\n\n\(bullets)\n\n\(engineLine(engine, home: home, locale: locale))\n\n\(closing.joined(separator: " "))"
    }

    // MARK: VoiceOver

    /// Morceaux lus après le nom d'une ligne cochable : taille, détail.
    static func accessibilityDetails(_ cleanable: DockerCleanable, locale: Locale) -> [String] {
        [sizeText(cleanable.size, locale: locale), detail(cleanable, locale: locale)]
    }
}
