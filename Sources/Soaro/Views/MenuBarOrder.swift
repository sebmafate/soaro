import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Les six mesures que l'on peut afficher dans la barre de menus (SL22). Le drapeau n'en fait pas partie : il suit le réseau.
/// Les identifiants (`rawValue`) sont écrits dans les préférences : ne pas les renommer.
enum MenuBarMeasure: String, CaseIterable, Identifiable, Codable {
    case cpu, gpu, memory, disk, network, battery

    var id: String { rawValue }

    /// Nom complet, celui du réglage (« CPU load »).
    var title: String {
        switch self {
        case .cpu: String(localized: "CPU load")
        case .gpu: String(localized: "GPU load")
        case .memory: String(localized: "Memory used")
        case .disk: String(localized: "Disk used")
        case .network: String(localized: "Network speed")
        case .battery: String(localized: "Battery level")
        }
    }

    /// Nom court, pour décrire l'aperçu en une phrase (« CPU, Memory, Battery »).
    var shortName: String {
        switch self {
        case .cpu: String(localized: "CPU")
        case .gpu: String(localized: "GPU")
        case .memory: String(localized: "Memory")
        case .disk: String(localized: "Disk")
        case .network: String(localized: "Network")
        case .battery: String(localized: "Battery")
        }
    }
}

/// L'ordre d'affichage des six mesures dans la barre de menus (SL22), toujours une permutation complète.
///
/// Écrit dans les préférences en une chaîne d'identifiants séparés par des virgules (« cpu,gpu,memory,disk,network,battery »).
/// La lecture est tolérante : identifiants inconnus et doublons ignorés, identifiants manquants ajoutés à la fin dans l'ordre
/// par défaut, valeur vide ou abîmée = ordre par défaut (celui de toujours, pour que rien ne change chez ceux qui n'y touchent pas).
/// L'ordre d'une mesure cachée ou indisponible est gardé : elle reprend sa place quand elle revient.
struct MenuBarOrder: Equatable {
    static let defaultMeasures: [MenuBarMeasure] = [.cpu, .gpu, .memory, .disk, .network, .battery]
    static let `default` = MenuBarOrder()
    static var defaultSerialized: String { `default`.serialized }

    private(set) var measures: [MenuBarMeasure]

    init() { measures = Self.defaultMeasures }

    init(parsing raw: String?) {
        var seen: [MenuBarMeasure] = []
        for part in (raw ?? "").split(separator: ",") {
            guard let measure = MenuBarMeasure(rawValue: part.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()),
                  !seen.contains(measure) else { continue }
            seen.append(measure)
        }
        measures = seen + Self.defaultMeasures.filter { !seen.contains($0) }
    }

    var serialized: String { measures.map(\.rawValue).joined(separator: ",") }

    // MARK: Préférences

    static func load(from defaults: UserDefaults = .standard) -> MenuBarOrder {
        MenuBarOrder(parsing: defaults.string(forKey: SettingsKey.menuBarOrder))
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(serialized, forKey: SettingsKey.menuBarOrder)
    }

    /// Lit la valeur écrite, applique un changement, rend la nouvelle valeur à écrire (ce que fait la ligne de Réglages).
    static func edit(stored: String?, _ change: (inout MenuBarOrder) -> Void) -> String {
        var order = MenuBarOrder(parsing: stored)
        change(&order)
        return order.serialized
    }

    // MARK: Déplacements

    func index(of measure: MenuBarMeasure) -> Int { measures.firstIndex(of: measure) ?? 0 }

    /// L'élément en `source` se retrouve à l'indice `destination` (borné à la liste) ; les autres se décalent. Source hors liste : rien.
    mutating func move(from source: Int, to destination: Int) {
        guard measures.indices.contains(source) else { return }
        let target = min(max(destination, 0), measures.count - 1)
        let measure = measures.remove(at: source)
        measures.insert(measure, at: target)
    }

    /// Dépose `measure` sur la ligne de `target` : il prend sa place, les autres se décalent.
    mutating func move(_ measure: MenuBarMeasure, onto target: MenuBarMeasure) {
        move(from: index(of: measure), to: index(of: target))
    }

    /// Voisin visible juste avant (`-1`) ou après (`+1`) : celui avec qui l'on échange. Les mesures cachées sont sautées,
    /// sinon le déplacement échangerait avec une ligne que l'on ne voit pas et rien ne bougerait à l'écran.
    private func neighbour(of measure: MenuBarMeasure, step: Int, among visible: Set<MenuBarMeasure>) -> MenuBarMeasure? {
        var i = index(of: measure) + step
        while measures.indices.contains(i) {
            if visible.contains(measures[i]) { return measures[i] }
            i += step
        }
        return nil
    }

    func canMoveUp(_ measure: MenuBarMeasure, among visible: Set<MenuBarMeasure> = Set(MenuBarMeasure.allCases)) -> Bool {
        neighbour(of: measure, step: -1, among: visible) != nil
    }

    func canMoveDown(_ measure: MenuBarMeasure, among visible: Set<MenuBarMeasure> = Set(MenuBarMeasure.allCases)) -> Bool {
        neighbour(of: measure, step: 1, among: visible) != nil
    }

    /// Monte d'un cran parmi les lignes visibles ; sans voisin au-dessus, ne fait rien.
    mutating func moveUp(_ measure: MenuBarMeasure, among visible: Set<MenuBarMeasure> = Set(MenuBarMeasure.allCases)) {
        if let other = neighbour(of: measure, step: -1, among: visible) { move(measure, onto: other) }
    }

    mutating func moveDown(_ measure: MenuBarMeasure, among visible: Set<MenuBarMeasure> = Set(MenuBarMeasure.allCases)) {
        if let other = neighbour(of: measure, step: 1, among: visible) { move(measure, onto: other) }
    }

    // MARK: Lignes de Réglages

    /// Les lignes de la liste : la batterie n'y est que si le Mac en a une.
    func visible(hasBattery: Bool) -> [MenuBarMeasure] {
        measures.filter { hasBattery || $0 != .battery }
    }

    /// « 2 of 6 » : la valeur d'accessibilité d'une ligne (rang à partir de 1).
    static func positionText(index: Int, of count: Int) -> String {
        String(localized: "\(index + 1) of \(count)")
    }
}

extension MenuBarOrder {
    /// Phrase annoncée à VoiceOver après un déplacement par action d'accessibilité : « CPU load, 2 of 6 ».
    static func announcement(title: String, index: Int, of count: Int) -> String {
        "\(title), \(positionText(index: index, of: count))"
    }

    /// Pas d'animation de déplacement quand « Réduire les animations » est activé.
    static func reorderAnimation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .snappy(duration: 0.25)
    }
}

extension UTType {
    /// Type de la ligne que l'on glisse dans Réglages. Déclaré dans l'Info.plist de l'app (`scripts/build-app.sh`) : il ne sort pas de l'app,
    /// et ne ressemble ni à du texte ni à un fichier (déposée ailleurs, la ligne ne produit rien).
    static let menuBarMeasure = UTType(exportedAs: "app.soaro.menu-bar-measure", conformingTo: .data)
}

/// Ce que porte le glissement d'une ligne : l'identifiant de la mesure, rien d'autre.
struct MenuBarMeasureDrag: Codable, Transferable {
    let measure: MenuBarMeasure

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .menuBarMeasure)
    }
}
