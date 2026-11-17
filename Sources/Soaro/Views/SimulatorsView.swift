import SwiftUI

/// Écran « Simulators and emulators » (S2) : deux sections, iOS puis Android (SL10), choisies par `SimulatorsScreen.layout`.
/// Un groupe en échec montre son en-tête et son message (l'autre reste utilisable) ; un groupe caché ou vide est absent. Une ligne
/// Android en cours d'exécution est « indisponible » (jamais cochable). Le bouton « Delete » (barre d'action « danger ») est disponible quand `canDelete`
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
        } else if model.phase == .listed || model.androidPhase == .listed {
            Text(SimulatorPresentation.headerSummary(count: model.listedCount, size: model.measuredSizeTotal))
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
        switch SimulatorsScreen.layout(ios: model.phase, android: model.androidPhase) {
        case .spinner:
            VStack(spacing: 10) {
                ProgressView()
                Text(verbatim: model.progressMessage).font(.caption).supportingText()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .nothingFound:
            hint(SimulatorsScreen.nothingFoundMessage, systemImage: "info.circle")
        case .failedOnly(.ios):
            hint(model.message ?? "", systemImage: "exclamationmark.triangle")
        case .failedOnly(.android):
            hint(model.androidMessage ?? "", systemImage: "exclamationmark.triangle")
        case let .sections(ios, android):
            sections(ios: ios, android: android)
            if SimulatorsScreen.showsActionBar(.sections(ios: ios, android: android)) { actionBar }
        }
    }

    private func hint(_ message: String, systemImage: String) -> some View {
        EmptyHint(verbatim: message, systemImage: systemImage, supporting: true)
            .padding(14).frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder private func sections(ios: SimulatorsScreen.Section, android: SimulatorsScreen.Section) -> some View {
        if model.showsNothingToSuggest {
            hintBanner
        }
        List {
            switch ios {
            case .listed:
                Section {
                    ForEach(model.rows, id: \.device.device.udid) { row in
                        deviceRow(row)
                    }
                } header: {
                    SectionHeader(title: "iOS Simulators")
                } footer: {
                    if android == .absent { footer }
                }
            case .failed:
                Section {
                    failedGroup(model.message ?? "")
                } header: {
                    SectionHeader(title: "iOS Simulators")
                } footer: {
                    if android == .absent { footer }
                }
            case .absent:
                EmptyView()
            }
            switch android {
            case .listed:
                Section {
                    ForEach(model.androidRows, id: \.device.device.name) { row in
                        androidRow(row)
                    }
                } header: {
                    SectionHeader(title: "Android emulators")
                } footer: {
                    footer
                }
            case .failed:
                Section {
                    failedGroup(model.androidMessage ?? "")
                } header: {
                    SectionHeader(title: "Android emulators")
                } footer: {
                    footer
                }
            case .absent:
                EmptyView()
            }
        }
        .listStyle(.plain)
    }

    /// Un groupe dont la lecture a échoué : message neutre, icône d'avertissement, jeton « texte de soutien » (l'autre groupe reste utilisable).
    private func failedGroup(_ message: String) -> some View {
        EmptyHint(verbatim: message, systemImage: "exclamationmark.triangle", supporting: true)
            .font(.caption)
    }

    private var actionBar: some View {
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

    /// Une ligne Android : nom affiché, « · API 36 », ligne de raison, taille ; en cours d'exécution : ligne indisponible.
    private func androidRow(_ row: DeviceSuggestions.AndroidRow) -> some View {
        let device = row.device.device
        let size = model.size(of: row)
        let locale = Locale.current
        let system = AndroidEmulatorPresentation.systemLabel(version: device.systemVersion, locale: locale)
        let reason = AndroidEmulatorPresentation.reasonLine(for: row, locale: locale)
        return SelectionRow(
            name: device.displayName,
            isOn: model.androidSelected.contains(device.name),
            unavailableReason: AndroidEmulatorPresentation.unavailableReason(for: row),
            details: AndroidEmulatorPresentation.accessibilityDetails(row: row, size: size, locale: locale),
            toggle: { model.toggle(row) }
        ) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(verbatim: device.displayName).font(.callout).lineLimit(1).truncationMode(.tail)
                        .help(device.displayName)
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
