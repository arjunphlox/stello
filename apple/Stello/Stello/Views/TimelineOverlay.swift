import SwiftUI

enum TimelineMetrics {
    static let barWidth: CGFloat = 3
    /// Hover/active thickness on the bar's cross-axis (these are vertical bars —
    /// thin width, variable height — so "thicker" means wider, not taller).
    static let barHoverWidth: CGFloat = barWidth + 2
    static let barCornerRadius: CGFloat = barWidth / 2
    static let barMinHeight: CGFloat = 6
    static let barGap: CGFloat = 4
    static let scrollSpyThreshold: CGFloat = 16
    /// The strip only needs to cover the bar itself plus the gap from the bar's
    /// trailing edge to the card's leading edge — not the full 44pt overreach the
    /// old fixed constant used. Bars sit centered in the `StelloLayout.windowInset`
    /// gutter via a `(windowInset - barWidth) / 2` leading padding applied where
    /// `TimelineOverlay` is placed (`MasonryGridView.gridWithTimeline`), and cards
    /// start at `windowInset` from that same origin. So, in `TimelineOverlay`'s own
    /// coordinate space, the card edge sits at `(windowInset + barWidth) / 2` —
    /// exactly where the strip should end.
    static let interactionStripWidth: CGFloat = (StelloLayout.windowInset + barWidth) / 2
}

struct WeekBarLayout {
    let topY: CGFloat
    let bottomY: CGFloat

    var height: CGFloat { max(2, bottomY - topY) }
    var midY: CGFloat { topY + height / 2 }
}

struct TimelineOverlay: View {
    let weekGroups: [WeekGroup]
    let weekBarLayouts: [String: WeekBarLayout]
    let activeWeekKey: String?
    let interactionWeekKey: String?
    let selectedWeekKey: String?
    let onWeekFilterToggled: (String) -> Void
    let onInteractionChanged: (String?) -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        ZStack(alignment: .topLeading) {
            barsLayer
                .allowsHitTesting(false)

            interactionStrip
        }
        .coordinateSpace(name: "timelineStack")
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .clipped()
    }

    private var barsLayer: some View {
        // GeometryReader fills the overlay and anchors children at topLeading,
        // so offset-positioned bars never contribute intrinsic height. A plain
        // ZStack sizes to its tallest bar; when one week's bar exceeds the
        // viewport height, the enclosing frame vertically centers the oversized
        // stack and every bar drifts upward (store-size-dependent misalignment).
        GeometryReader { _ in
            ZStack(alignment: .topLeading) {
                ForEach(weekGroups) { group in
                    if let layout = weekBarLayouts[group.key] {
                        timelineBar(for: group, layout: layout)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func timelineBar(for group: WeekGroup, layout: WeekBarLayout) -> some View {
        let isInteraction = interactionWeekKey == group.key
        let isSelected = selectedWeekKey == group.key
        let isScrollSpy = activeWeekKey == group.key && !isInteraction && !isSelected
        let isHighlighted = isInteraction || isSelected || isScrollSpy

        let color: Color = {
            if isInteraction || isSelected {
                return theme.accentColor
            }
            if isScrollSpy {
                return theme.accentColor.opacity(0.55)
            }
            return theme.textSecondary.opacity(0.5)
        }()

        let barHeight = max(TimelineMetrics.barMinHeight, layout.height)
        // Hover feedback for the narrower strip: the nearest/active line thickens by
        // +2pt on its width. Leading edge stays anchored so the growth extends trailing
        // into the bar→card gap (~4.5pt of in-overlay room) — a centering offset would
        // push the left edge outside the overlay's frame, where it gets clipped.
        let barThickness = isInteraction ? TimelineMetrics.barHoverWidth : TimelineMetrics.barWidth

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: TimelineMetrics.barCornerRadius, style: .continuous)
                .fill(color)
                .frame(width: barThickness, height: barHeight)
                .animation(.easeOut(duration: 0.2), value: barThickness)
                .animation(isInteraction || isSelected ? .easeOut(duration: 0.2) : nil, value: isHighlighted)

            if isInteraction {
                Text(group.label)
                    .font(.karst(size: 11, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(theme.backgroundSubtle, in: Capsule())
                    .fixedSize()
                    .offset(x: TimelineMetrics.barWidth + 6, y: max(0, layout.height / 2 - 12))
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
        .offset(y: layout.topY)
    }

    private var interactionStrip: some View {
        Color.clear
            .frame(width: TimelineMetrics.interactionStripWidth)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onContinuousHover(coordinateSpace: .named("timelineStack")) { phase in
                switch phase {
                case .active(let location):
                    onInteractionChanged(weekKey(at: location.y))
                case .ended:
                    onInteractionChanged(nil)
                }
            }
            #if os(iOS)
            .simultaneousGesture(touchScrubGesture)
            #else
            .onTapGesture(coordinateSpace: .named("timelineStack")) { location in
                if let key = weekKey(at: location.y) {
                    onWeekFilterToggled(key)
                }
            }
            #endif
    }

    #if os(iOS)
    private var touchScrubGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("timelineStack"))
            .onChanged { value in
                onInteractionChanged(weekKey(at: value.location.y))
            }
            .onEnded { value in
                if let key = weekKey(at: value.location.y) {
                    onWeekFilterToggled(key)
                }
                onInteractionChanged(nil)
            }
    }
    #endif

    private func weekKey(at y: CGFloat) -> String? {
        guard !weekGroups.isEmpty else { return nil }
        let entries = weekGroups.compactMap { group -> (key: String, layout: WeekBarLayout)? in
            guard let layout = weekBarLayouts[group.key] else { return nil }
            return (group.key, layout)
        }
        return Self.weekKey(at: y, entries: entries) ?? weekGroups.first?.key
    }

    /// Maps a pointer Y to the bar whose vertical *band* it physically falls inside,
    /// rather than the bar with the nearest center. Nearest-center hit-testing put the
    /// boundary between two bars at their shared midpoint, which — for bars of unequal
    /// height — could sit well outside the gap between them, so hovering just below a
    /// short bar (but still above the true midpoint) resolved to the bar ABOVE instead
    /// of the one physically under the pointer. Band boundaries are instead placed at
    /// the midpoint of each inter-bar GAP (`bar.bottomY` ↔ `nextBar.topY`), so every
    /// point inside a bar's rendered rect — and the gap immediately around it — resolves
    /// to that bar. The first/last bars own everything above/below them (clamped, no
    /// wraparound).
    static func weekKey(at y: CGFloat, entries: [(key: String, layout: WeekBarLayout)]) -> String? {
        let bars = entries.sorted { $0.layout.topY < $1.layout.topY }
        guard !bars.isEmpty else { return nil }

        for index in bars.indices {
            let bar = bars[index]
            guard index + 1 < bars.count else { return bar.key }
            let next = bars[index + 1]
            let boundary = (bar.layout.bottomY + next.layout.topY) / 2
            if y < boundary {
                return bar.key
            }
        }
        return bars.last?.key
    }
}
