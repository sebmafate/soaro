import AppKit
import SwiftUI

/// Trois seuils (en %) qui séparent normal / moyen / élevé / critique.
struct LevelThresholds: Equatable {
    var medium: Int
    var high: Int
    var critical: Int

    /// Mesure où « haut » est mauvais (charge, disque occupé).
    func level(ascending percent: Double) -> PressureLevel {
        if percent >= Double(critical) { return .critical }
        if percent >= Double(high) { return .high }
        if percent >= Double(medium) { return .medium }
        return .normal
    }

    /// Mesure où « bas » est mauvais (batterie).
    func level(descending percent: Double) -> PressureLevel {
        if percent <= Double(critical) { return .critical }
        if percent <= Double(high) { return .high }
        if percent <= Double(medium) { return .medium }
        return .normal
    }

    /// Remet les seuils dans l'ordre et dans 1…100, quoi qu'il y ait dans les préférences.
    func sanitized(ascending: Bool) -> LevelThresholds {
        let values = [medium, high, critical].map { min(100, max(1, $0)) }.sorted()
        return ascending
            ? LevelThresholds(medium: values[0], high: values[1], critical: values[2])
            : LevelThresholds(medium: values[2], high: values[1], critical: values[0])
    }
}

/// Seuils de couleur de la barre de menus, réglables dans les préférences.
struct PressureThresholds: Equatable {
    var load = LevelThresholds(medium: 60, high: 80, critical: 95)       // CPU et GPU
    var disk = LevelThresholds(medium: 80, high: 90, critical: 95)       // % occupé
    var battery = LevelThresholds(medium: 20, high: 10, critical: 5)     // % restant, hors secteur

    static let `default` = PressureThresholds()

    private static func read(_ name: String, fallback: LevelThresholds, ascending: Bool, from defaults: UserDefaults) -> LevelThresholds {
        func value(_ part: String, _ fallback: Int) -> Int {
            (defaults.object(forKey: "threshold.\(name).\(part)") as? Int) ?? fallback
        }
        return LevelThresholds(medium: value("medium", fallback.medium), high: value("high", fallback.high), critical: value("critical", fallback.critical))
            .sanitized(ascending: ascending)
    }

    static func load(from defaults: UserDefaults = .standard) -> PressureThresholds {
        PressureThresholds(
            load: read("load", fallback: PressureThresholds.default.load, ascending: true, from: defaults),
            disk: read("disk", fallback: PressureThresholds.default.disk, ascending: true, from: defaults),
            battery: read("battery", fallback: PressureThresholds.default.battery, ascending: false, from: defaults)
        )
    }

    func save(to defaults: UserDefaults = .standard) {
        for (name, t) in [("load", load), ("disk", disk), ("battery", battery)] {
            defaults.set(t.medium, forKey: "threshold.\(name).medium")
            defaults.set(t.high, forKey: "threshold.\(name).high")
            defaults.set(t.critical, forKey: "threshold.\(name).critical")
        }
    }
}

/// Niveau de sollicitation d'une mesure, qui décide de la couleur de sa valeur dans la barre de menus.
enum PressureLevel: Int, Comparable {
    case normal, medium, high, critical
    static func < (l: PressureLevel, r: PressureLevel) -> Bool { l.rawValue < r.rawValue }

    /// Charge instantanée (CPU, GPU), de 0 à 1.
    static func load(_ fraction: Double, thresholds: LevelThresholds = PressureThresholds.default.load) -> PressureLevel {
        thresholds.level(ascending: fraction * 100)
    }

    /// Mémoire : le pourcentage utilisé ne dit rien sur macOS (la RAM libre est de la RAM gâchée).
    /// On suit la pression réelle du système, aggravée quand le swap devient massif. Pas de seuil réglable ici.
    static func memory(_ m: MemoryStats) -> PressureLevel {
        switch m.pressure {
        case .normal: .normal
        case .warning: m.total > 0 && Double(m.swapUsed) >= Double(m.total) * 0.5 ? .high : .medium
        case .critical: .critical
        }
    }

    /// Disque : part occupée, de 0 à 1.
    static func disk(_ usedFraction: Double, thresholds: LevelThresholds = PressureThresholds.default.disk) -> PressureLevel {
        thresholds.level(ascending: usedFraction * 100)
    }

    /// Batterie : seul un niveau bas *sur batterie* est préoccupant.
    static func battery(_ b: BatteryStats, thresholds: LevelThresholds = PressureThresholds.default.battery) -> PressureLevel {
        b.isPluggedIn ? .normal : thresholds.level(descending: b.percent)
    }
}

/// Une mesure affichée dans la barre de menus.
enum MenuBarItem: Equatable {
    /// Petit libellé au-dessus, valeur en dessous (« CPU » / « 43% »).
    case stacked(label: String, value: String, level: PressureLevel = .normal)
    /// Deux lignes alignées à droite (envoi / réception).
    case pair(top: String, bottom: String)
    /// Drapeau du pays de l'IP publique (SL19), à droite du bloc réseau. Ne porte que le code : l'adresse IP n'arrive jamais ici.
    case flag(countryCode: String)

    var level: PressureLevel {
        if case .stacked(_, _, let level) = self { return level }
        return .normal
    }

    /// Mesures choisies dans les réglages, dans un ordre fixe.
    static func items(for s: SystemSnapshot, cpu: Bool, gpu: Bool, memory: Bool, disk: Bool, network: Bool, battery: Bool,
                      thresholds t: PressureThresholds = .default, publicIPCountryCode: String? = nil) -> [MenuBarItem] {
        var items: [MenuBarItem] = []
        if cpu { items.append(.stacked(label: "CPU", value: Format.percent(s.cpu.total), level: .load(s.cpu.total, thresholds: t.load))) }
        if gpu, let g = s.gpu { items.append(.stacked(label: "GPU", value: Format.percent(g.utilization), level: .load(g.utilization, thresholds: t.load))) }
        if memory { items.append(.stacked(label: "RAM", value: Format.percent(s.memory.usedFraction), level: .memory(s.memory))) }
        if disk { items.append(.stacked(label: "SSD", value: Format.percent(s.disk.usedFraction), level: .disk(s.disk.usedFraction, thresholds: t.disk))) }
        if network, let n = s.network {
            items.append(.pair(top: "↑ " + Format.menuBarRate(n.upRate), bottom: "↓ " + Format.menuBarRate(n.downRate)))
            // Seulement avec le bloc réseau, et seulement si la police d'émojis a un drapeau pour ce code.
            if let code = publicIPCountryCode?.uppercased(), MenuBarFlag.emoji(forCountryCode: code) != nil {
                items.append(.flag(countryCode: code))
            }
        }
        if battery, let b = s.battery {
            items.append(.stacked(label: b.isCharging ? "BAT ⚡︎" : "BAT", value: Format.percent(b.percent / 100), level: .battery(b, thresholds: t.battery)))
        }
        return items
    }

    /// Une image « modèle » est monochrome : un drapeau en couleur doit donc passer par une image qui porte ses couleurs.
    var isFlag: Bool {
        if case .flag = self { return true }
        return false
    }

    /// Version texte sur une ligne (style « classique »). Le drapeau suit le bloc réseau, sans séparateur.
    static func inlineText(_ items: [MenuBarItem]) -> String? {
        var parts: [String] = []
        for item in items {
            switch item {
            case .stacked(let label, let value, _): parts.append("\(label) \(value)")
            case .pair(let top, let bottom): parts.append("\(bottom) \(top)")
            case .flag(let code):
                guard let flag = MenuBarFlag.emoji(forCountryCode: code) else { continue }
                if parts.isEmpty { parts.append(flag) } else { parts[parts.count - 1] += " " + flag }
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Le libellé d'un `MenuBarExtra` n'affiche que du texte et des images simples : on dessine donc tout le
/// libellé (icône, badge d'alerte, mesures) dans une image « modèle », qui suit le thème clair/sombre de la barre.
@MainActor
enum MenuBarRenderer {
    private struct Key: Equatable {
        var severity: Severity?
        var compact: Bool
        var items: [MenuBarItem]
        var darkBar: Bool
    }
    private static var cache: (key: Key, image: NSImage)?

    /// Recalculée seulement si une valeur affichée change.
    static func image(severity: Severity?, compact: Bool, items: [MenuBarItem], darkBar: Bool? = nil) -> NSImage? {
        let darkBar = darkBar ?? isMenuBarDark
        // Tant que tout est normal, image « modèle » : macOS la teinte lui-même (rendu le plus fidèle).
        // Dès qu'une valeur doit être colorée, l'image porte ses propres couleurs, dont le blanc/noir du reste.
        // Un drapeau (SL19) y oblige aussi : une image modèle est monochrome (seul son alpha compte), il deviendrait une silhouette.
        let colored = items.contains { $0.level > .normal || $0.isFlag }
        let key = Key(severity: severity, compact: compact, items: items, darkBar: colored && darkBar)
        if let cache, cache.key == key { return cache.image }

        let base: Color = colored ? (darkBar ? .white : .black) : .black
        let renderer = ImageRenderer(content: MenuBarWidgetsView(severity: severity, compact: compact, items: items, baseColor: base))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return nil }
        image.isTemplate = !colored
        cache = (key, image)
        return image
    }
}

extension MenuBarRenderer {
    /// Boutons de barre de menus de l'app (le `MenuBarExtra` de SwiftUI ne les expose pas directement).
    static var statusBarButtons: [NSStatusBarButton] {
        func find(in view: NSView) -> [NSStatusBarButton] {
            (view as? NSStatusBarButton).map { [$0] } ?? view.subviews.flatMap(find)
        }
        return (NSApp?.windows ?? [])
            .filter { String(describing: type(of: $0)).contains("StatusBar") }
            .compactMap(\.contentView)
            .flatMap(find)
    }

    private static var statusBarWindows: [NSWindow] {
        (NSApp?.windows ?? []).filter { String(describing: type(of: $0)).contains("StatusBar") }
    }

    /// Infobulle affichée au survol de l'élément de barre de menus. Renvoie le nombre de vues mises à jour.
    ///
    /// - Elle est posée sur *toutes* les vues de l'élément : sur les écrans secondaires, macOS n'affiche
    ///   qu'une copie de l'élément (`NSStatusItemReplicantView`), sans le bouton d'origine.
    /// - Elle n'est pas réécrite tant que le pointeur survole l'élément : changer le texte (dont les chiffres
    ///   bougent toutes les 3 s) annulerait l'infobulle en train d'apparaître.
    @discardableResult
    static func setToolTip(_ text: String, mouseLocation: NSPoint = NSEvent.mouseLocation) -> Int {
        let windows = statusBarWindows
        if windows.contains(where: { $0.frame.insetBy(dx: -2, dy: -2).contains(mouseLocation) }) { return 0 }

        var updated = 0
        func apply(_ view: NSView) {
            if view.toolTip != text { view.toolTip = text; updated += 1 }
            view.subviews.forEach(apply)
        }
        for window in windows {
            window.allowsToolTipsWhenApplicationIsInactive = true
            if let content = window.contentView { apply(content) }
        }
        return updated
    }

    /// Trace de la hiérarchie de vues de l'élément de barre de menus (mode `SOARO_DEBUG`).
    static func debugHierarchy() -> String {
        var out = ""
        func dump(_ view: NSView, _ depth: Int) {
            out += String(repeating: "  ", count: depth) + "\(type(of: view)) frame=\(view.frame) tooltip=\(view.toolTip == nil ? "nil" : "oui") tracking=\(view.trackingAreas.count)\n"
            view.subviews.forEach { dump($0, depth + 1) }
        }
        for window in NSApp?.windows ?? [] where String(describing: type(of: window)).contains("StatusBar") {
            out += "window \(type(of: window)) frame=\(window.frame) ignoresMouse=\(window.ignoresMouseEvents)\n"
            if let content = window.contentView { dump(content, 1) }
        }
        return out
    }

    /// La barre de menus est-elle sombre ? Elle suit le fond d'écran, pas seulement le thème : on interroge
    /// donc l'élément de barre de menus lui-même, avec le thème de l'app comme solution de repli.
    static var isMenuBarDark: Bool {
        let statusWindow = NSApp?.windows.first { String(describing: type(of: $0)).contains("StatusBar") }
        let appearance = statusWindow?.contentView?.effectiveAppearance ?? statusWindow?.effectiveAppearance ?? NSApp?.effectiveAppearance
        return appearance?.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

extension PressureLevel {
    var label: String {
        switch self {
        case .normal: String(localized: "normal")
        case .medium: String(localized: "medium")
        case .high: String(localized: "high")
        case .critical: String(localized: "critical")
        }
    }

    static let scarlet = Color(red: 1.0, green: 0.14, blue: 0.0)      // écarlate #FF2400

    /// Couleur de la valeur ; `nil` = couleur par défaut de la barre de menus.
    var color: Color? {
        switch self {
        case .normal: nil
        case .medium: .orange
        case .high: .red
        case .critical: Self.scarlet
        }
    }
}

/// Le glyphe d'Soaro, identique à l'icône de l'app : la houle qui s'apaise jusqu'à la ligne droite.
struct BrandGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        // Mêmes courbes que assets/icon.svg (x : 200…824, y : 214…694), ramenées au rectangle.
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + (x - 200) / 624 * rect.width, y: rect.minY + (y - 214) / 480 * rect.height)
        }
        var path = Path()
        for (base, crest, trough) in [(CGFloat(330), CGFloat(214), CGFloat(446)), (512, 454, 570)] {
            path.move(to: p(200, base))
            path.addCurve(to: p(412, base), control1: p(270, crest), control2: p(342, crest))
            path.addCurve(to: p(624, base), control1: p(482, trough), control2: p(554, trough))
            path.addCurve(to: p(824, base), control1: p(694, crest), control2: p(754, crest))
        }
        path.move(to: p(200, 694))
        path.addLine(to: p(824, 694))
        return path
    }
}

struct MenuBarWidgetsView: View {
    let severity: Severity?
    let compact: Bool
    let items: [MenuBarItem]
    var baseColor: Color = .black

    var body: some View {
        HStack(spacing: compact ? 9 : 6) {
            brand
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                switch item {
                case .stacked(let label, let value, let level):
                    if compact {
                        VStack(spacing: -1) {
                            Text(label).font(.system(size: 7.5, weight: .medium))
                            valueText(value, level: level, size: 12)
                        }
                        .frame(minWidth: 31)          // largeur mini : « 9% » et « 100% » ne décalent pas les voisins
                    } else {
                        HStack(spacing: 3) {
                            Text(label).font(.system(size: 13))
                            valueText(value, level: level, size: 13)
                        }
                    }
                case .flag(let code):
                    if let flag = MenuBarFlag.emoji(forCountryCode: code) {
                        // Émoji en couleur : il ignore la couleur du texte. Aucune largeur ni hauteur imposée aux autres blocs.
                        Text(flag).font(.system(size: MenuBarFlag.fontSize))
                    }
                case .pair(let top, let bottom):
                    if compact {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(top)
                            Text(bottom)
                        }
                        .font(.system(size: 9, weight: .medium)).monospacedDigit()
                        .frame(minWidth: 54, alignment: .trailing)     // largeur de « ↓ 999 KB/s » : le bloc réseau ne bouge plus
                    } else {
                        Text("\(bottom) \(top)").font(.system(size: 13)).monospacedDigit()
                    }
                }
            }
        }
        .foregroundStyle(baseColor)
        .frame(height: 22)
        .fixedSize()
    }

    /// Orange puis rouge colorent le texte. Le niveau critique passe en pastille écarlate : sur une barre de menus,
    /// rouge et écarlate en simple texte seraient indiscernables (et la couleur seule ne suffit pas aux daltoniens).
    @ViewBuilder private func valueText(_ value: String, level: PressureLevel, size: CGFloat) -> some View {
        let text = Text(value).font(.system(size: size, weight: compact ? .semibold : .regular)).monospacedDigit()
        if level == .critical {
            text.foregroundStyle(.white)
                .padding(.horizontal, 3)
                .background(PressureLevel.scarlet, in: RoundedRectangle(cornerRadius: 3.5))
        } else if let color = level.color {
            text.foregroundStyle(color)
        } else {
            text
        }
    }

    /// L'icône de l'app est toujours là ; une alerte s'ajoute en petit badge au lieu de la remplacer.
    private var brand: some View {
        HStack(alignment: .top, spacing: 1.5) {
            BrandGlyph()
                .stroke(style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                .frame(width: 16, height: 12)
            switch severity {
            case .critical:
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 8, weight: .bold))
            case .warning:
                Circle().frame(width: 4.5, height: 4.5)
            default:
                EmptyView()
            }
        }
    }
}

/// Texte de l'infobulle : pourquoi il y a un badge d'alerte, et pourquoi une valeur est en couleur.
enum MenuBarTooltip {
    /// Langue de l'app (pas celle des réglages régionaux) pour écrire le nom du pays.
    static var appLocale: Locale { Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en") }

    /// « France », « フランス »… : calculé localement à partir du code, sans rien demander au service.
    static func countryName(code: String, locale: Locale = appLocale) -> String {
        locale.localizedString(forRegionCode: code) ?? code
    }

    static func text(recommendations: [Recommendation], snapshot: SystemSnapshot?, items: [MenuBarItem], locale: Locale = appLocale) -> String {
        var lines: [String] = []

        let alerts = recommendations.filter { $0.severity >= .warning }
        let suggestions = recommendations.filter { $0.severity == .info }
        if alerts.isEmpty {
            lines.append(String(localized: "Soaro: everything is fine"))
        } else {
            lines.append(alerts.count == 1 ? String(localized: "Soaro: 1 attention point") : String(localized: "Soaro: \(alerts.count) attention points"))
            for rec in alerts {
                lines.append("\(rec.severity == .critical ? "⚠︎" : "•") \(rec.title)")
                lines.append("   \(rec.detail)")
            }
        }

        let colored = snapshot.map { explanations(for: items, snapshot: $0) } ?? []
        if !colored.isEmpty {
            lines.append("")
            lines.append(String(localized: "Colored values:"))
            lines.append(contentsOf: colored.map { "• \($0)" })
        }
        // Le pays de l'IP publique (jamais l'adresse elle-même) quand le drapeau est affiché.
        if let code = items.compactMap({ item -> String? in if case .flag(let code) = item { code } else { nil } }).first {
            lines.append("")
            lines.append(String(localized: "Public IP country: \(countryName(code: code, locale: locale))"))
        }
        if !suggestions.isEmpty {
            lines.append("")
            lines.append(suggestions.count == 1 ? String(localized: "1 suggestion:") : String(localized: "\(suggestions.count) suggestions:"))
            lines.append(contentsOf: suggestions.map { "• \($0.title)" })
        }
        return lines.joined(separator: "\n")
    }

    /// Une phrase par valeur colorée, avec la vraie raison (pas seulement le pourcentage).
    static func explanations(for items: [MenuBarItem], snapshot s: SystemSnapshot) -> [String] {
        items.compactMap { item in
            guard case .stacked(let label, let value, let level) = item, level > .normal else { return nil }
            let suffix = String(localized: "(level: \(level.label))")
            switch label.prefix(3) {
            case "CPU": return String(localized: "Processor at \(value) \(suffix)")
            case "GPU": return String(localized: "Graphics processor at \(value) \(suffix)")
            case "RAM": return String(localized: "Memory: \(s.memory.pressure.label.lowercased()) pressure, swap \(Format.bytes(s.memory.swapUsed)) \(suffix)")
            case "SSD": return String(localized: "Disk \(value) full, \(Format.fileBytes(s.disk.available)) free \(suffix)")
            case "BAT": return String(localized: "Battery at \(value), not plugged in \(suffix)")
            default: return "\(label) \(value) \(suffix)"
            }
        }
    }
}
