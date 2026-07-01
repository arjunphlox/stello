import SwiftUI

enum TimelineMetrics {
    static let interactionStripWidth: CGFloat = 44
    static let lineHeight: CGFloat = 2
    static let lineGap: CGFloat = 8
    static let defaultLineWidth: CGFloat = 20
    static let expandedLineWidth: CGFloat = 36
    static let scrollSpyThreshold: CGFloat = 16
}

struct TimelineOverlay: View {
    let weekGroups: [WeekGroup]
    let activeWeekKey: String?
    let interactionWeekKey: String?
    let onWeekSelected: (String) -> Void
    let onInteractionChanged: (String?) -> Void

    @Environment(\.appTheme) private var theme
    @State private var lineCenters: [String: CGFloat] = [:]

    var body: some View {
        ZStack(alignment: .leading) {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                VStack(spacing: TimelineMetrics.lineGap) {
                    ForEach(weekGroups) { group in
                        timelineLine(for: group)
                    }
                }
                Spacer(minLength: 0)
            }
            .allowsHitTesting(false)

            interactionStrip
        }
        .coordinateSpace(name: "timelineStack")
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .onPreferenceChange(TimelineLineCenterKey.self) { lineCenters = $0 }
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
                    onWeekSelected(key)
                }
            }
            #endif
    }

    @ViewBuilder
    private func timelineLine(for group: WeekGroup) -> some View {
        let isInteraction = interactionWeekKey == group.key
        let isScrollSpy = activeWeekKey == group.key && !isInteraction
        let isHighlighted = isInteraction || isScrollSpy
        let width = isInteraction ? TimelineMetrics.expandedLineWidth : TimelineMetrics.defaultLineWidth
        let color: Color = isHighlighted
            ? theme.accentColor
            : theme.textSecondary.opacity(0.5)

        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(color)
                .frame(width: width, height: TimelineMetrics.lineHeight)
                .animation(.easeOut(duration: 0.2), value: width)
                .animation(.easeOut(duration: 0.2), value: isHighlighted)

            if isInteraction {
                Text(group.label)
                    .font(.karst(size: 11, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(theme.backgroundSubtle, in: Capsule())
                    .fixedSize()
                    .offset(x: width + 6)
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
        .frame(height: TimelineMetrics.lineHeight, alignment: .leading)
        .background {
            GeometryReader { geo in
                Color.clear.preference(
                    key: TimelineLineCenterKey.self,
                    value: [group.key: geo.frame(in: .named("timelineStack")).midY]
                )
            }
        }
    }

    #if os(iOS)
    private var touchScrubGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("timelineStack"))
            .onChanged { value in
                onInteractionChanged(weekKey(at: value.location.y))
            }
            .onEnded { value in
                if let key = weekKey(at: value.location.y) {
                    onWeekSelected(key)
                }
                onInteractionChanged(nil)
            }
    }
    #endif

    private func weekKey(at y: CGFloat) -> String? {
        guard !weekGroups.isEmpty else { return nil }
        var best: (key: String, distance: CGFloat)?
        for group in weekGroups {
            guard let center = lineCenters[group.key] else { continue }
            let distance = abs(center - y)
            if best == nil || distance < best!.distance {
                best = (group.key, distance)
            }
        }
        return best?.key ?? weekGroups.first?.key
    }
}

private struct TimelineLineCenterKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}
