import Foundation

/// Disposition de l'écran « Simulators and emulators » (S2) : fonction PURE des états de groupe, testable sans vue.
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

    enum Group: Equatable { case ios, android, images }

    enum Layout: Equatable {
        /// Attente (« Looking for simulators and emulators… », ou « Deleting… » ailleurs).
        case spinner
        /// « No simulator or emulator found. » : les trois groupes sont cachés ou vides.
        case nothingFound
        /// Le seul groupe en échec, les autres étant cachés ou vides : son message occupe tout l'écran.
        case failedOnly(Group)
        /// Les sections, dans l'ordre iOS, Android puis images système (SL12a ; `images` vaut `absent` par défaut).
        case sections(ios: Section, android: Section, images: Section = .absent)
    }

    /// `images` vaut `.hidden` par défaut : les appels qui ne connaissent pas encore le groupe des images ne changent pas.
    static func layout(ios: SimulatorsModel.Phase, android: SimulatorsModel.Phase, images: SimulatorsModel.Phase = .hidden) -> Layout {
        func isWaiting(_ phase: SimulatorsModel.Phase) -> Bool { phase == .notScanned || phase == .listing }
        if isWaiting(ios) || isWaiting(android) || isWaiting(images) { return .spinner }

        func section(_ phase: SimulatorsModel.Phase) -> Section {
            switch phase {
            case .listed: .listed
            case .failed: .failed
            case .notScanned, .listing, .hidden, .empty: .absent
            }
        }
        let (i, a, m) = (section(ios), section(android), section(images))
        switch (i, a, m) {
        case (.absent, .absent, .absent): return .nothingFound
        case (.failed, .absent, .absent): return .failedOnly(.ios)
        case (.absent, .failed, .absent): return .failedOnly(.android)
        case (.absent, .absent, .failed): return .failedOnly(.images)
        default: return .sections(ios: i, android: a, images: m)
        }
    }

    /// La barre d'action (« Delete ») s'affiche quand au moins un groupe d'APPAREILS est listé : un écran qui ne montre que des images
    /// (rien à cocher ni à supprimer) n'a pas de barre.
    static func showsActionBar(_ layout: Layout) -> Bool {
        if case .sections(let ios, let android, _) = layout { return ios == .listed || android == .listed }
        return false
    }

    /// Où vont les pieds de page des sections.
    struct Footers: Equatable {
        /// L'explication des règles (« …are pre-selected… ») ne vaut que pour iOS : sous la section iOS, quand elle est listée.
        let explanationUnderIos: Bool
        /// Le décompte des petits appareils (des deux groupes) : sous la dernière section présente.
        let smallCountUnder: Group?
    }

    /// Le décompte des petits appareils reste sous la dernière section d'APPAREILS ; `images` n'y change rien.
    static func footers(ios: Section, android: Section, images: Section = .absent) -> Footers {
        let last: Group? = android != .absent ? .android : (ios != .absent ? .ios : nil)
        return Footers(explanationUnderIos: ios == .listed, smallCountUnder: last)
    }

    /// « No simulator or emulator found. »
    static var nothingFoundMessage: String { String(localized: "No simulator or emulator found.") }
}
