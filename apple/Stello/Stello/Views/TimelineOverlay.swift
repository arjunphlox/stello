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
        // Hover feedback for the narrower strip: the nearest/active line thickens
        // by +2pt on its width (its cross-axis). Center-anchored via a compensating
        // negative x-offset so the extra width grows outward symmetrically instead
        // of shifting the bar's leading edge (and the strip/gutter it sits in).
        let barThickness = isInteraction ? TimelineMetrics.barHoverWidth : TimelineMetrics.barWidth
        let thicknessOffset = (TimelineMetrics.barWidth - barThickness) / 2

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: TimelineMetrics.barCornerRadius, style: .continuous)
                .fill(color)
                .frame(width: barThickness, height: barHeight)
                .offset(x: thicknessOffset)
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
        var best: (key: String, distance: CGFloat)?
        for group in weekGroups {
            guard let layout = weekBarLayouts[group.key] else { continue }
            let distance = abs(layout.midY - y)
            if best == nil || distance < best!.distance {
                best = (group.key, distance)
            }
        }
        return best?.key ?? weekGroups.first?.key
    }
}
