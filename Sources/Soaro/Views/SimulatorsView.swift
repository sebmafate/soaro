import SwiftUI

/// Écran « Simulators and emulators » (S2). Le bouton « Delete » (barre d'action « danger ») est disponible quand `canDelete`
/// l'autorise ; il demande d'abord la confirmation (S3, injectée dans le modèle). Pendant la suppression : barre occupée,
/// menu de limite et « Scan again » désactivés. Aucun raccourci clavier ni action par défaut : Retour ne supprime jamais (R8).
/// Textes d'appoint (tailles, résumés, pieds de page) : jeton « texte de soutien » (`supportingText`), pas de style système estompé.
struct SimulatorsView: View {
    @ObservedObject var model: SimulatorsModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        // Le scan démarre à l'ouverture ; revenir sur un écran déjà scanné garde ses résultats.
        .onAppear { if model.phase == .notScanned { model.scan() } }
        // Pendant une suppression (même lancée ailleurs), le scan demandé à l'ouverture est retenu par le modèle, qui le relance
        // à la fin du lot.
    }

    // MARK: En-tête : résumé, menu de limite, « Scan again » (peut passer sur deux lignes dans le panneau)

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { summary; Spacer(minLength: 8); limitMenu; scanAgain }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) { summary; Spacer(minLength: 8); scanAgain }
                limitMenu
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    @ViewBuilder private var summary: some View {
        if model.isMeasuring {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Measuring sizes…").font(.caption).supportingText()
            }
        } else if model.phase == .listed {
            Text(SimulatorPresentation.headerSummary(count: model.rows.count, size: model.measuredSizeTotal))
                .font(.caption).supportingText()
        }
    }

    private var limitMenu: some View {
        HStack(spacing: 6) {
            Text("Inactive for more than").font(.caption).supportingText()
            Picker("Inactive for more than", selection: Binding(get: { model.limitDays }, set: { model.setLimit($0) })) {
                ForEach(SimulatorsModel.limitChoices(), id: \.self) { days in
                    Text("\(days) days").tag(days)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .disabled(model.isDeleting)
        }
    }

    private var scanAgain: some View {
        Button("Scan again") { model.scan() }
            .controlSize(.small)
            .disabled(!model.canScanAgain)
    }

    // MARK: Corps

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .notScanned, .listing:
            VStack(spacing: 10) {
                ProgressView()
                Text(verbatim: model.progressMessage).font(.caption).supportingText()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            hint(model.message ?? "", systemImage: "exclamationmark.triangle")
        case .empty:
            hint(model.message ?? "", systemImage: "info.circle")
        case .listed:
            listed
        }
    }

    private func hint(_ message: String, systemImage: String) -> some View {
        EmptyHint(verbatim: message, systemImage: systemImage, supporting: true)
            .padding(14).frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder private var listed: some View {
        if model.showsNothingToSuggest {
            hintBanner
        }
        List {
            Section {
                ForEach(model.rows, id: \.device.device.udid) { row in
                    deviceRow(row)
                }
            } header: {
                SectionHeader(title: "iOS Simulators")
            } footer: {
                footer
            }
        }
        .listStyle(.plain)
        ActionBar(
            summary: model.isDeleting
                ? String(localized: "Deleting…")
                : model.selectedCount == 0
                    ? String(localized: "Nothing selected")
                    : String(localized: "Selected: \(model.selectedCount) · \(Format.fileBytes(model.selectedSize))"),
            button: String(localized: "Delete"), enabled: model.canDelete, destructive: true, busy: model.isDeleting,
            action: { model.deleteSelected() }
        )
    }

    private var hintBanner: some View {
        EmptyHint(verbatim: SimulatorPresentation.nothingToSuggest(limitDays: model.limitDays),
                  systemImage: "info.circle", supporting: true)
            .padding(.horizontal, 14).padding(.vertical, 8)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let small = SimulatorPresentation.smallDevicesFooter(count: model.hiddenSmallCount, size: model.hiddenSmallSize, locale: .current) {
                Text(verbatim: small)
            }
            Text(verbatim: SimulatorPresentation.explanationFooter(limitDays: model.limitDays))
        }
        .font(.caption)
        .supportingText()
        .padding(.top, 6)
    }

    // MARK: Une ligne

    private func deviceRow(_ row: DeviceSuggestions.Row) -> some View {
        let device = row.device.device
        let size = model.size(of: row)
        let now = Date()
        let locale = Locale.current
        let system = SimulatorPresentation.systemLabel(runtimeIdentifier: device.runtimeIdentifier)
        let reason = SimulatorPresentation.reasonLine(for: row, now: now, locale: locale)
        return SelectionRow(
            name: device.name,
            isOn: model.selected.contains(device.udid),
            unavailableReason: SimulatorPresentation.unavailableReason(for: row),
            details: SimulatorPresentation.accessibilityDetails(row: row, size: size, now: now, locale: locale),
            toggle: { model.toggle(row) }
        ) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(verbatim: device.name).font(.callout).lineLimit(1).truncationMode(.tail)
                        .help(device.name)
                    Text(verbatim: "· \(system)").font(.caption).supportingText().lineLimit(1).fixedSize()
                        .layoutPriority(1)
                }
                if !reason.isEmpty {
                    Text(verbatim: reason).font(.caption)
                }
            }
            Spacer(minLength: 8)
            Text(verbatim: SimulatorPresentation.sizeText(size, locale: locale))
                .font(.caption.monospacedDigit()).supportingText()
                .lineLimit(1).fixedSize()
                .layoutPriority(2)
        }
    }
}
