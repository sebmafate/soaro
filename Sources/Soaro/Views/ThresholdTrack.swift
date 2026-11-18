import SwiftUI

extension ThresholdHandle {
    /// Les couleurs de la barre de menus (`PressureLevel`) : orange, rouge, écarlate.
    var color: Color {
        switch self {
        case .orange: PressureLevel.medium.color ?? .orange
        case .red: PressureLevel.high.color ?? .red
        case .scarlet: PressureLevel.scarlet
        }
    }
}

extension ThresholdTrackLogic.Band {
    var color: Color {
        switch self {
        case .normal: .green
        case .orange: ThresholdHandle.orange.color
        case .red: ThresholdHandle.red.color
        case .scarlet: ThresholdHandle.scarlet.color
        }
    }
}

/// Une piste de 0 à 100 % avec trois poignées rondes glissables (SL17), à la place des trois Steppers d'un groupe de seuils.
///
/// - Les bandes de couleur suivent les poignées en direct ; les poignées ne se croisent jamais ; le pas est de 5 et l'écart minimal de 5
///   (`ThresholdTrackLogic`, qui porte les règles et leurs tests).
/// - Chaque poignée est un élément « réglable » pour VoiceOver (incrément / décrément de 5), atteignable au clavier
///   (flèches : 5, Maj : 10, Début et Fin : les bornes) ; la zone cliquable fait 24 x 24 pt ; la valeur est toujours écrite
///   (la couleur n'est jamais le seul signal).
/// - Aucune animation : « Réduire les animations » est sans objet.
struct ThresholdTrack: View {
    @Binding var thresholds: LevelThresholds
    /// `true` : la valeur est mauvaise quand elle monte ; `false` : quand elle descend (batterie).
    let ascending: Bool
    /// Valeur actuelle du groupe en %, `nil` si inconnue (le repère est alors caché).
    let current: Double?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @FocusState private var focused: ThresholdHandle?
    /// Poignée en cours de glisser et sa valeur au début du geste.
    @State private var drag: (handle: ThresholdHandle, origin: Int)?

    private typealias Metrics = ThresholdTrackMetrics

    private static let trackSpaceName = "soaro.threshold-track"

    private var increasedContrast: Bool { contrast == .increased }

    var body: some View {
        GeometryReader { geometry in
            let width = Double(geometry.size.width)
            let unit = Metrics.pointsPerUnit(forWidth: width)
            let placements = ThresholdTrackLogic.labelPlacements(for: thresholds, pointsPerUnit: unit)
            ZStack(alignment: .topLeading) {
                bands(unit: unit)
                nowMarker(unit: unit)
                ForEach(ThresholdHandle.allCases, id: \.self) { handle in
                    handleView(handle, unit: unit, placement: placements[handle] ?? .init(raised: false, shift: 0))
                }
            }
            .frame(width: geometry.size.width, height: Metrics.totalHeight, alignment: .topLeading)
            .coordinateSpace(name: Self.trackSpaceName)
        }
        .frame(height: Metrics.totalHeight)
    }

    private func x(_ percent: Double, unit: Double) -> CGFloat {
        CGFloat(Double(Metrics.inset) + percent * unit)
    }

    // MARK: Bandes et repère

    private func bands(unit: Double) -> some View {
        let segments = ThresholdTrackLogic.segments(for: thresholds, ascending: ascending)
        let opacity = ThresholdTrackStyle.normalBandOpacity(reduceTransparency: reduceTransparency, increasedContrast: increasedContrast)
        let outline = ThresholdTrackStyle.outlineWidth(increasedContrast: increasedContrast)
        return HStack(spacing: 0) {
            ForEach(segments.indices, id: \.self) { index in
                let segment = segments[index]
                Rectangle()
                    .fill(segment.band.color.opacity(segment.band == .normal ? opacity : 1))
                    .frame(width: CGFloat(Double(segment.to - segment.from) * unit))
            }
        }
        .frame(width: CGFloat(100 * unit), height: Metrics.trackHeight)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.primary.opacity(0.6), lineWidth: outline))
        .position(x: x(50, unit: unit), y: Metrics.centreY)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func nowMarker(unit: Double) -> some View {
        if let current {
            let clamped = ThresholdTrackLogic.fraction(ofPercent: current) * 100
            ZStack {
                Rectangle().fill(Color.primary.opacity(0.85)).frame(width: 2, height: 18)
                Text("now")
                    .font(.caption2).foregroundStyle(.supportingText).lineLimit(1).fixedSize()
                    .offset(y: 19)
            }
            .frame(width: 40, height: 18)
            .position(x: x(clamped, unit: unit), y: Metrics.centreY)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(ThresholdTrackLogic.nowAccessibilityText(current))
        }
    }

    // MARK: Poignée

    private func handleView(_ handle: ThresholdHandle, unit: Double, placement: ThresholdTrackLogic.LabelPlacement) -> some View {
        let value = ThresholdTrackLogic.value(of: handle, in: thresholds)
        let centre = x(Double(value), unit: unit)
        let isFocused = focused == handle
        let ring = ThresholdTrackStyle.ringWidth(increasedContrast: increasedContrast)
        return ZStack {
            // Étiquette de la valeur, au-dessus de la poignée ; relevée sur une seconde rangée, avec une tige, quand la voisine est trop près.
            valueLabel(handle, value: value, placement: placement, centre: centre)
            ZStack {
                Circle().fill(Color.white)
                Circle().strokeBorder(handle.color, lineWidth: ring)
                if increasedContrast {
                    Circle().stroke(Color.black, lineWidth: 1)
                }
            }
            .frame(width: Metrics.handleSize, height: Metrics.handleSize)
            .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
            .overlay {
                if isFocused {
                    Circle().stroke(Color.accentColor, lineWidth: 3)
                        .frame(width: Metrics.handleSize + 8, height: Metrics.handleSize + 8)
                }
            }
            .frame(width: ThresholdTrackMetrics.hitSize, height: ThresholdTrackMetrics.hitSize)
            .contentShape(Circle())
            .position(x: centre, y: Metrics.centreY)
            .gesture(dragGesture(handle, unit: unit))
            // `.activate` : focalisable avec la navigation au clavier (Full Keyboard Access) seulement, pas de focus au clic ni à l'ouverture.
            .focusable(true, interactions: .activate)
            .focused($focused, equals: handle)
            .focusEffectDisabled()
            .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow, .home, .end], phases: [.down, .repeat]) { press in
                guard let key = Self.key(for: press.key) else { return .ignored }
                move(handle, ThresholdTrackLogic.command(for: key, shift: press.modifiers.contains(.shift)))
                return .handled
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(ThresholdTrackLogic.name(of: handle))
            .accessibilityValue(ThresholdTrackLogic.valueText(value, ascending: ascending))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: move(handle, .step(1))
                case .decrement: move(handle, .step(-1))
                @unknown default: break
                }
            }
        }
        .zIndex(drag?.handle == handle || isFocused ? 1 : 0)
    }

    private func valueLabel(_ handle: ThresholdHandle, value: Int, placement: ThresholdTrackLogic.LabelPlacement, centre: CGFloat) -> some View {
        let top = placement.raised ? Metrics.raisedLabelTop : Metrics.labelTop
        let labelCentre = centre + CGFloat(placement.shift)
        return ZStack {
            if placement.raised {
                // Tige fine de l'étiquette relevée jusqu'à la poignée.
                let stemTop = top + Metrics.labelHeight
                let stemBottom = Metrics.centreY - Metrics.handleSize / 2
                Rectangle().fill(handle.color).frame(width: 2, height: max(0, stemBottom - stemTop))
                    .position(x: centre, y: (stemTop + stemBottom) / 2)
            }
            Text(ThresholdTrackLogic.percentText(value))
                .font(.caption2.weight(.semibold)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.8)
                .foregroundStyle(.primary)
                .frame(width: CGFloat(Metrics.labelWidth), height: Metrics.labelHeight)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(handle.color, lineWidth: 1.5))
                .position(x: labelCentre, y: top + Metrics.labelHeight / 2)
        }
        .allowsHitTesting(false)         // l'étiquette ne prend jamais le pointeur à une poignée
        .accessibilityHidden(true)      // la poignée dit déjà sa valeur
    }

    // MARK: Geste et clavier

    private func dragGesture(_ handle: ThresholdHandle, unit: Double) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.trackSpaceName))
            .onChanged { gesture in
                let origin: Int
                if let drag, drag.handle == handle {
                    origin = drag.origin
                } else {
                    origin = ThresholdTrackLogic.value(of: handle, in: thresholds)
                    drag = (handle, origin)
                }
                let value = ThresholdTrackLogic.draggedValue(from: origin, translation: Double(gesture.translation.width), pointsPerUnit: unit,
                                                            handle: handle, in: thresholds, ascending: ascending)
                set(handle, to: value)
            }
            .onEnded { _ in drag = nil }
    }

    private func set(_ handle: ThresholdHandle, to value: Int) {
        guard value != ThresholdTrackLogic.value(of: handle, in: thresholds) else { return }
        thresholds = ThresholdTrackLogic.with(value, for: handle, in: thresholds)
    }

    private func move(_ handle: ThresholdHandle, _ command: ThresholdTrackLogic.Command) {
        let updated = ThresholdTrackLogic.apply(command, to: handle, in: thresholds, ascending: ascending)
        if updated != thresholds { thresholds = updated }
    }

    private static func key(for key: KeyEquivalent) -> ThresholdTrackLogic.Key? {
        switch key {
        case .leftArrow: .left
        case .rightArrow: .right
        case .upArrow: .up
        case .downArrow: .down
        case .home: .home
        case .end: .end
        default: nil
        }
    }
}

/// Trois seuils réglables sur une piste, toujours gardés dans l'ordre (chaque poignée est bornée par ses voisines).
struct ThresholdEditor: View {
    let title: LocalizedStringKey
    @Binding var thresholds: LevelThresholds
    /// `true` : la valeur est mauvaise quand elle monte ; `false` : quand elle descend (batterie).
    let ascending: Bool
    /// Valeur actuelle du groupe, en % (`nil` : inconnue, pas de repère « now »).
    var current: Double?

    private var handles: [(handle: ThresholdHandle, value: Int)] {
        ThresholdHandle.allCases.map { ($0, ThresholdTrackLogic.value(of: $0, in: thresholds)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.callout.weight(.medium))
            ThresholdTrack(thresholds: $thresholds, ascending: ascending, current: current)
            legend
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(title))
    }

    /// « Orange from 60 % » : une ligne par poignée, sur une ligne si la largeur le permet, sinon l'une sous l'autre.
    private var legend: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) { entries }
            VStack(alignment: .leading, spacing: 2) { entries }
        }
        .font(.caption)
        .foregroundStyle(.supportingText)
        .accessibilityHidden(true)       // les poignées disent déjà la même chose
    }

    private var entries: some View {
        ForEach(handles, id: \.handle) { item in
            HStack(spacing: 5) {
                Circle().fill(item.handle.color).frame(width: 8, height: 8)
                // Deux phrases entières, pour que chaque langue place les mots comme elle veut.
                Text(ThresholdTrackLogic.legendText(item.handle, value: item.value, ascending: ascending))
                    .monospacedDigit().lineLimit(1).fixedSize()
            }
        }
    }
}
