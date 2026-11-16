import SwiftUI

/// Barre d'action collée en bas d'une liste : résumé + bouton principal.
struct ActionBar: View {
    let summary: String
    let button: String
    let enabled: Bool
    var destructive = false
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Text(summary).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(button, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(destructive ? .red : .accentColor)
                    .disabled(!enabled)
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
