import SwiftUI

/// Teinte du bouton principal d'une `ActionBar`.
enum ActionBarTint: Equatable {
    /// Couleur d'accentuation du système (« Move to Trash », etc.).
    case accent
    /// Fond « danger » de DESIGN.md (#D32F2F, #B71C1C avec « Augmenter le contraste »).
    case danger

    /// Valeur fixe de la teinte, ou `nil` quand elle suit le système.
    func rgb(contrastIncreased: Bool) -> DesignTokens.RGB? {
        switch self {
        case .accent: nil
        case .danger: DesignTokens.dangerFill(contrastIncreased: contrastIncreased)
        }
    }

    func color(contrastIncreased: Bool) -> Color {
        rgb(contrastIncreased: contrastIncreased)?.color ?? .accentColor
    }
}

/// Barre d'action collée en bas d'une liste : résumé + bouton principal.
///
/// Le bouton n'est jamais le bouton par défaut et ne porte aucun raccourci clavier :
/// Retour ne supprime rien (R8).
struct ActionBar: View {
    let summary: String
    let button: String
    let enabled: Bool
    var destructive = false
    /// Une action est en cours : petit indicateur à côté du résumé, bouton désactivé.
    /// Le texte du résumé est fourni par l'appelant.
    var busy = false
    let action: () -> Void

    @Environment(\.colorSchemeContrast) private var contrast

    static func tintKind(destructive: Bool) -> ActionBarTint {
        destructive ? .danger : .accent
    }

    static func isButtonEnabled(enabled: Bool, busy: Bool) -> Bool {
        enabled && !busy
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                if busy {
                    ProgressView().controlSize(.small)
                        .accessibilityHidden(true)
                }
                Text(summary).font(.caption).foregroundStyle(.supportingText)
                Spacer()
                Button(button, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(Self.tintKind(destructive: destructive).color(contrastIncreased: contrast == .increased))
                    .disabled(!Self.isButtonEnabled(enabled: enabled, busy: busy))
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
    }
}

/// Mesures partagées des lignes de sélection.
enum SelectionMetrics {
    /// Côté minimal de la zone cliquable de la coche (en points).
    static let minimumTargetSize: CGFloat = 24
}

/// Texte lu par VoiceOver pour le bouton de sélection d'une ligne.
enum SelectionAccessibility {
    struct Description: Equatable {
        let label: String
        let value: String
    }

    /// Libellé = nom de l'élément, suivi des détails non vides (dans l'ordre, séparés par « , ») ; valeur = « Selected » /
    /// « Not selected » (clés existantes du catalogue). Ligne indisponible : la valeur est « <raison>, not selectable »
    /// (la ligne n'est pas sélectionnable, l'état coché n'a pas de sens). Sans nom (vide ou espaces), les détails servent de
    /// libellé s'il y en a ; sinon la valeur sert de libellé, sans valeur : pas de libellé vide ni de doublon.
    static func description(name: String, details: [String] = [], isOn: Bool, unavailableReason: String? = nil) -> Description {
        let state: String
        if let reason = unavailableReason {
            state = String(localized: "\(reason), not selectable")
        } else {
            state = isOn ? String(localized: "Selected") : String(localized: "Not selected")
        }
        func isBlank(_ text: String) -> Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var parts = details.filter { !isBlank($0) }
        if !isBlank(name) { parts.insert(name, at: 0) }
        if parts.isEmpty { return Description(label: state, value: "") }
        return Description(label: parts.joined(separator: ", "), value: state)
    }

    /// Seule une raison `nil` donne une ligne sélectionnable : une ligne indisponible n'a pas
    /// de bouton de bascule (la vue affiche une icône inerte).
    static func isSelectable(unavailableReason: String?) -> Bool {
        unavailableReason == nil
    }
}

// MARK: - « Select all » : une case à trois états par section

/// État de la case « Select all » d'une section : aucune ligne sélectionnable cochée, une partie, ou toutes.
enum SelectAllState: Equatable {
    case none, some, all
}

/// Règles PURES de la case « Select all » (testables sans vue ; les modèles et les vues s'en servent).
enum SelectAll {
    /// - Parameters:
    ///   - selectable: le nombre de lignes sélectionnables de la section (les lignes indisponibles, p. ex. en cours d'exécution, n'y comptent pas).
    ///   - selected: le nombre de lignes cochées PARMI les sélectionnables (borné).
    /// - Returns: `.none` sans ligne sélectionnable ou sans coche, `.all` quand toutes sont cochées, sinon `.some` (état mixte).
    static func state(selectable: Int, selected: Int) -> SelectAllState {
        guard selectable > 0, selected > 0 else { return .none }
        return selected >= selectable ? .all : .some
    }

    /// Le clic : mixte ou aucune → tout cocher ; tout → tout décocher.
    static func turnsOn(from state: SelectAllState) -> Bool { state != .all }

    /// Désactivée sans ligne sélectionnable, et tant que la section est verrouillée (suppression en cours).
    static func isEnabled(selectable: Int, locked: Bool = false) -> Bool { selectable > 0 && !locked }

    /// Un glyphe par état : la couleur n'est jamais le seul signal (coche, tiret, cercle vide).
    static func symbol(for state: SelectAllState) -> String {
        switch state {
        case .none: "circle"
        case .some: "minus.circle.fill"
        case .all: "checkmark.circle.fill"
        }
    }

    /// Le titre visible de l'en-tête est caché de VoiceOver quand la case n'a pas de nom de section : le titre est alors « Select all »
    /// (listes sans en-tête propre) et la case le dit déjà, il serait lu deux fois.
    static func hidesHeaderTitle(sectionName: String?) -> Bool {
        (sectionName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Texte VoiceOver : libellé « Select all » suivi du nom de la section quand il y en a un ; valeur « Not selected » /
    /// « Some selected » / « Selected ».
    static func description(state: SelectAllState, sectionName: String?) -> SelectionAccessibility.Description {
        let value: String
        switch state {
        case .none: value = String(localized: "Not selected")
        case .some: value = String(localized: "Some selected")
        case .all: value = String(localized: "Selected")
        }
        let name = sectionName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let label = String(localized: "Select all")
        return SelectionAccessibility.Description(label: name.isEmpty ? label : "\(label), \(name)", value: value)
    }
}

/// Ce que l'en-tête d'une section a besoin de savoir de sa case : l'état, si elle est active, le nom de la section (VoiceOver), le clic.
struct SelectAllControl {
    let state: SelectAllState
    let enabled: Bool
    var sectionName: String? = nil
    let action: () -> Void
}

/// La case « Select all » d'un en-tête : UN élément pour VoiceOver (« Select all, <section> », valeur Selected / Not selected /
/// Some selected), au moins 24 x 24 pt, atteignable au clavier (Full Keyboard Access : Espace bascule), sans aucun raccourci.
struct SelectAllCheckbox: View {
    let control: SelectAllControl

    var body: some View {
        let description = SelectAll.description(state: control.state, sectionName: control.sectionName)
        Button(action: control.action) {
            Image(systemName: SelectAll.symbol(for: control.state))
                .foregroundStyle(control.state == .none ? Color.secondary : Color.accentColor)
                .font(.title3)
                .frame(minWidth: SelectionMetrics.minimumTargetSize, minHeight: SelectionMetrics.minimumTargetSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!control.enabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(description.label)
        .accessibilityValue(description.value)
        .accessibilityAddTraits(.isButton)
    }
}

/// Ligne de sélection : UN SEUL élément pour VoiceOver (nom, détails, valeur « Selected » / « Not selected »),
/// activé pour basculer. Le texte visible n'est pas lu une seconde fois. Une ligne indisponible ne fait rien.
/// « Show in Finder » (si `revealAction` est fourni) est un bouton à la souris ET une action nommée de la ligne.
struct SelectionRow<Content: View>: View {
    /// Nom de l'élément, lu par VoiceOver en tête du libellé de la ligne.
    let name: String
    let isOn: Bool
    /// Variante « indisponible » : icône `minus.circle` au lieu de la coche, raison affichée en
    /// texte (pleine opacité, jamais estompée), aucune bascule. `nil` = ligne sélectionnable.
    var unavailableReason: String? = nil
    /// Morceaux lus après le nom (système, taille, raison…), dans l'ordre ; les vides sont ignorés.
    var details: [String] = []
    /// Révélation dans le Finder : bouton visible à droite, et action VoiceOver « Show in Finder ». `nil` : aucune.
    var revealAction: (() -> Void)? = nil
    let toggle: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        let description = SelectionAccessibility.description(name: name, details: details, isOn: isOn, unavailableReason: unavailableReason)
        let selectable = SelectionAccessibility.isSelectable(unavailableReason: unavailableReason)
        HStack(alignment: .center, spacing: 8) {
            if !selectable {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.secondary)
                    .font(.title3)
                    .frame(minWidth: SelectionMetrics.minimumTargetSize, minHeight: SelectionMetrics.minimumTargetSize)
            } else {
                Button(action: toggle) {
                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isOn ? Color.accentColor : .secondary)
                        .font(.title3)
                        .frame(minWidth: SelectionMetrics.minimumTargetSize, minHeight: SelectionMetrics.minimumTargetSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if let reason = unavailableReason {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .center, spacing: 8) { content }
                    Text(reason).font(.caption).foregroundStyle(.primary)
                }
            } else {
                content
            }
            if let revealAction {
                Button(action: revealAction) { Image(systemName: "magnifyingglass.circle") }
                    .buttonStyle(.borderless)
                    .help("Show in Finder")
                    .frame(minWidth: SelectionMetrics.minimumTargetSize, minHeight: SelectionMetrics.minimumTargetSize)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        // Un seul élément : tout le contenu visible (nom, détails, raison) est lu une fois, dans le libellé.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(description.label)
        .accessibilityValue(description.value)
        .accessibilityAddTraits(selectable ? .isButton : [])
        .modifier(RowActions(selectable: selectable, toggle: toggle, revealAction: revealAction))
    }
}

/// Actions de la ligne : activation = bascule (ligne sélectionnable seulement), « Show in Finder » en action nommée.
private struct RowActions: ViewModifier {
    let selectable: Bool
    let toggle: () -> Void
    let revealAction: (() -> Void)?

    @ViewBuilder func body(content: Content) -> some View {
        switch (selectable, revealAction) {
        case let (true, reveal?):
            content
                .accessibilityAction { toggle() }
                .accessibilityAction(named: Text("Show in Finder")) { reveal() }
        case (true, nil):
            content.accessibilityAction { toggle() }
        case let (false, reveal?):
            content.accessibilityAction(named: Text("Show in Finder")) { reveal() }
        case (false, nil):
            content
        }
    }
}

// MARK: - Aperçus (Xcode uniquement : aucun écran ne les utilise)

struct SelectionRow_Previews: PreviewProvider {
    static var previews: some View {
        VStack(alignment: .leading, spacing: 0) {
            SelectionRow(name: "web-shop", isOn: true, toggle: {}) {
                Text("web-shop").font(.callout); Spacer(); Text("1,2 GB").font(.caption.monospacedDigit())
            }
            SelectionRow(name: "api", isOn: false, toggle: {}) {
                Text("api").font(.callout); Spacer(); Text("340 MB").font(.caption.monospacedDigit())
            }
            SelectionRow(name: "iPhone 15", isOn: false, unavailableReason: "In use by Xcode", toggle: {}) {
                Text("iPhone 15").font(.callout); Spacer(); Text("4,1 GB").font(.caption.monospacedDigit())
            }
        }
        .padding(14).frame(width: 420)
        .previewDisplayName("SelectionRow: selected, not selected, unavailable")
    }
}

struct ActionBar_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 0) {
            ActionBar(summary: "Nothing selected", button: "Move to Trash", enabled: true, action: {})
            ActionBar(summary: "Nothing selected", button: "Move to Trash", enabled: false, action: {})
            ActionBar(summary: "Selected: 2", button: "Delete", enabled: true, destructive: true, action: {})
            ActionBar(summary: "Deleting…", button: "Delete", enabled: true, destructive: true, busy: true, action: {})
        }
        .frame(width: 420)
        .previewDisplayName("ActionBar: default, disabled, destructive, busy")
    }
}
