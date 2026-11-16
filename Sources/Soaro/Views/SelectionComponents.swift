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
                Text(summary).font(.caption).foregroundStyle(.secondary)
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

struct SelectionRow<Content: View>: View {
    let isOn: Bool
    let toggle: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button(action: toggle) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isOn ? Color.accentColor : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isOn ? "Selected" : "Not selected")
            content
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Aperçus (Xcode uniquement : aucun écran ne les utilise)

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
