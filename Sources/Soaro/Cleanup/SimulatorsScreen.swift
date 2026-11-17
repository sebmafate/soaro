import Foundation

/// Disposition de l'écran « Simulators and emulators » (S2) : fonction PURE des deux états de groupe, testable sans vue.
enum SimulatorsScreen {
    /// Un groupe, tel que l'écran le montre à côté de l'autre.
    enum Section: Equatable {
        /// Caché ou vide : pas de section.
        case absent
        /// Ses lignes.
        case listed
        /// Son en-tête et son message d'échec (l'autre groupe reste utilisable).
        case failed
    }

    enum Group: Equatable { case ios, android }

    enum Layout: Equatable {
        /// Attente (« Looking for simulators and emulators… », ou « Deleting… » ailleurs).
        case spinner
        /// « No simulator or emulator found. » : les deux groupes sont cachés ou vides.
        case nothingFound
        /// Le seul groupe en échec, l'autre étant caché ou vide : son message occupe tout l'écran.
        case failedOnly(Group)
        /// Les sections, dans l'ordre iOS puis Android.
        case sections(ios: Section, android: Section)
    }

    static func layout(ios: SimulatorsModel.Phase, android: SimulatorsModel.Phase) -> Layout {
        func isWaiting(_ phase: SimulatorsModel.Phase) -> Bool { phase == .notScanned || phase == .listing }
        if isWaiting(ios) || isWaiting(android) { return .spinner }

        func section(_ phase: SimulatorsModel.Phase) -> Section {
            switch phase {
            case .listed: .listed
            case .failed: .failed
            case .notScanned, .listing, .hidden, .empty: .absent
            }
        }
        let (i, a) = (section(ios), section(android))
        switch (i, a) {
        case (.absent, .absent): return .nothingFound
        case (.failed, .absent): return .failedOnly(.ios)
        case (.absent, .failed): return .failedOnly(.android)
        default: return .sections(ios: i, android: a)
        }
    }

    /// La barre d'action (« Delete ») s'affiche quand au moins un groupe est listé.
    static func showsActionBar(_ layout: Layout) -> Bool {
        if case .sections(let ios, let android) = layout { return ios == .listed || android == .listed }
        return false
    }

    /// « No simulator or emulator found. »
    static var nothingFoundMessage: String { String(localized: "No simulator or emulator found.") }
}
