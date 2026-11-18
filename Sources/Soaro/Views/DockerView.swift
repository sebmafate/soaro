import SwiftUI

/// Écran « Docker » (S4) : deux sections, « Can be cleaned » (le cache de build et les images sans étiquette, cochés d'office, avec « Select all »)
/// puis « Not touched » (conteneurs, volumes, autres images inutilisées : lecture seule, ni case ni bouton), choisies par `DockerScreen.layout`.
/// Le bouton « Clean » (barre d'action « danger ») demande d'abord la confirmation (S3, injectée dans le modèle) ; pendant un lot : barre occupée
/// (« Cleaning… » puis « Measuring… »), « Scan again » désactivé. Aucun raccourci clavier ni action par défaut : Retour ne nettoie jamais (R8).
/// Soaro ne démarre jamais Docker : moteur arrêté = un message, pas un bouton. Textes d'appoint : jeton « texte de soutien » (`supportingText`).
struct DockerView: View {
    @ObservedObject var model: DockerModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        // Le scan démarre à l'ouverture ; revenir sur un écran déjà scanné garde ses résultats. Pendant un lot (même lancé ailleurs), le
        // listage demandé à l'ouverture est retenu par le modèle, qui le relance à la fin.
        .onAppear { if model.phase == .notScanned { model.scan() } }
    }

    // MARK: En-tête : « Scan again »

    private var header: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 8)
            Button("Scan again") { model.scan() }
                .controlSize(.small)
                .disabled(!model.canScanAgain)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    // MARK: Corps

    @ViewBuilder private var content: some View {
        let layout = DockerScreen.layout(phase: model.phase)
        switch layout {
        case .spinner:
            VStack(spacing: 10) {
                ProgressView()
                Text(verbatim: model.progressMessage).font(.caption).supportingText()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .hint(let warning):
            EmptyHint(verbatim: model.message ?? "", systemImage: warning ? "exclamationmark.triangle" : "info.circle")
                .padding(14).frame(maxHeight: .infinity, alignment: .top)
        case .list:
            list
            if DockerScreen.showsActionBar(layout: layout, hasCleanables: !model.cleanables.isEmpty) { actionBar }
        }
    }

    private var list: some View {
        let locale = Locale.current
        return List {
            if let result = model.lastResult {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: result).font(.callout).fixedSize(horizontal: false, vertical: true)
                        Text(verbatim: DockerPresentation.measurementNote).font(.caption).supportingText()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                }
            }
            if model.showsNothingToClean {
                Section {
                    EmptyHint(verbatim: DockerPresentation.nothingToClean, systemImage: "info.circle")
                }
            } else {
                Section {
                    ForEach(model.cleanables, id: \.prune) { cleanable in
                        cleanableRow(cleanable, locale: locale)
                    }
                } header: {
                    SectionHeader(title: "Can be cleaned", selectAll: selectAll)
                }
            }
            if let overview = model.overview {
                Section {
                    if overview.buildCacheSizeUnknown {
                        readOnlyRow(title: DockerPresentation.buildCacheTitle, size: nil,
                                    detail: DockerPresentation.buildCacheUnknownDetail(locale: locale), locale: locale)
                    }
                    readOnlyRow(title: DockerPresentation.containersTitle, size: overview.containers.size,
                                detail: DockerPresentation.inUseDetail(overview.containers, locale: locale), locale: locale)
                    readOnlyRow(title: DockerPresentation.volumesTitle, size: overview.volumes.size,
                                detail: DockerPresentation.inUseDetail(overview.volumes, locale: locale), locale: locale)
                    if let other = overview.otherUnusedImages {
                        readOnlyRow(title: DockerPresentation.otherImagesTitle, size: other.size,
                                    detail: DockerPresentation.otherImagesDetail(other, locale: locale), locale: locale)
                    }
                } header: {
                    SectionHeader(title: "Not touched")
                } footer: {
                    Text(verbatim: DockerPresentation.neverRemovedFooter)
                        .font(.caption).supportingText()
                        .lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                }
            }
        }
        .listStyle(.plain)
    }

    /// La case « Select all » de la section « Can be cleaned » : à trois états, inactive pendant un lot, sans raccourci.
    private var selectAll: SelectAllControl {
        SelectAllControl(state: model.selectAllState, enabled: model.canSelectAll, sectionName: String(localized: "Can be cleaned"),
                         action: { model.toggleAll() })
    }

    private var actionBar: some View {
        ActionBar(
            summary: summary,
            button: String(localized: "Clean"), enabled: model.canClean, destructive: true, busy: model.isBusy,
            action: { model.cleanSelected() }
        )
    }

    private var summary: String {
        switch model.stage {
        case .cleaning: DockerPresentation.cleaningMessage
        case .measuring: DockerPresentation.measuringMessage
        case .idle:
            model.selectedCount == 0
                ? String(localized: "Nothing selected")
                : String(localized: "Selected: \(model.selectedCount) · \(Format.fileBytes(model.selectedSize))")
        }
    }

    // MARK: Une ligne

    private func cleanableRow(_ cleanable: DockerCleanable, locale: Locale) -> some View {
        let name = DockerPresentation.title(cleanable.prune)
        return SelectionRow(
            name: name,
            isOn: model.selected.contains(cleanable.prune),
            details: DockerPresentation.accessibilityDetails(cleanable, locale: locale),
            toggle: { model.toggle(cleanable.prune) }
        ) {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: name).font(.callout).lineLimit(1).truncationMode(.tail)
                Text(verbatim: DockerPresentation.detail(cleanable, locale: locale)).font(.caption).supportingText()
            }
            Spacer(minLength: 8)
            Text(verbatim: DockerPresentation.sizeText(cleanable.size, locale: locale))
                .font(.caption.monospacedDigit()).supportingText()
                .lineLimit(1).fixedSize()
                .layoutPriority(2)
        }
    }

    /// Une ligne en lecture seule, EN DERNIER dans ce fichier : ni case, ni bouton, ni action. Le texte s'aligne sur les noms des lignes
    /// cochables. Un seul élément pour VoiceOver : nom, taille, détail.
    private func readOnlyRow(title: String, size: UInt64?, detail: String?, locale: Locale) -> some View {
        HStack(alignment: .center, spacing: SelectionMetrics.rowSpacing) {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: title).font(.callout).lineLimit(1).truncationMode(.tail)
                if let detail { Text(verbatim: detail).font(.caption).supportingText() }
            }
            Spacer(minLength: 8)
            Text(verbatim: DockerPresentation.sizeText(size, locale: locale))
                .font(.caption.monospacedDigit()).supportingText()
                .lineLimit(1).fixedSize()
                .layoutPriority(2)
        }
        .padding(.leading, SelectionMetrics.minimumTargetSize + SelectionMetrics.rowSpacing)
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([title, DockerPresentation.sizeText(size, locale: locale), detail ?? ""].filter { !$0.isEmpty }.joined(separator: ", "))
    }
}
