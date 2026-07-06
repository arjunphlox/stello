import SwiftUI

enum TimelineMetrics {
    static let interactionStripWidth: CGFloat = 44
    static let barWidth: CGFloat = 3
    static let barCornerRadius: CGFloat = barWidth / 2
    static let barMinHeight: CGFloat = 6
    static let barGap: CGFloat = 4
    static let scrollSpyThreshold: CGFloat = 16
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
        ZStack(alignment: .topLeading) {
            ForEach(weekGroups) { group in
                if let layout = weekBarLayouts[group.key] {
                    timelineBar(for: group, layout: layout)
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

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: TimelineMetrics.barCornerRadius, style: .continuous)
                .fill(color)
                .frame(width: TimelineMetrics.barWidth, height: barHeight)
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
