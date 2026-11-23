import Foundation
import CoreGraphics
import SwiftUI

/// Layer 1: why two items on the canvas belong together, computed from their tags
/// with rules only (a port of canvas.js `buildIndex` / `simFor` / `familiesOf`).
/// Six kinds: same place, same colour, looks alike (top colour + top style), same
/// kind, same idea (subject tags), same style. Rare shared features weigh more; very
/// common ones are skipped.
nonisolated enum SimKind: String, CaseIterable, Sendable {
    case place, colour, looks, kind, idea, style

    var label: String {
        switch self {
        case .place: "Same place"
        case .colour: "Same colour"
        case .looks: "Looks alike"
        case .kind: "Same kind"
        case .idea: "Same idea"
        case .style: "Same style"
        }
    }
    /// Weight (web `SIM[type].w`).
    var weight: Double {
        switch self {
        case .place: 3.0
        case .colour: 1.4
        case .looks: 1.6
        case .kind: 0.8
        case .idea: 1.5
        case .style: 1.0
        }
    }
    /// Line colour (Figma legend); looks-alike uses the text colour, dashed.
    var hex: String? {
        switch self {
        case .place: "#e8590c"
        case .colour: "#3b5bdb"
        case .looks: nil
        case .kind: "#7048e8"
        case .idea: "#2b8a3e"
        case .style: "#1098ad"
        }
    }
    var dashed: Bool { self == .looks }
}

nonisolated struct SimFeature: Hashable, Sendable {
    let key: String
    let kind: SimKind
    let tag: String
}

nonisolated struct SimLink: Sendable {
    let a: String
    let b: String
    let kind: SimKind
    let label: String
    let score: Double
}

nonisolated struct SimNear: Sendable {
    let b: String
    let kind: SimKind
    let label: String
    let score: Double
    let distance: CGFloat
}

/// A family: items that share one telling feature and sit together, or one of
/// your groups. Drawn as a soft tint with pills naming what they share.
nonisolated struct CanvasFamily: Identifiable, Sendable {
    let id: String
    var name: String?
    var kind: SimKind?
    /// Set for your own groups (`doc.groups`).
    var groupID: String?
    var slugs: [String]
    var pills: [String] = []
}

/// What dropping a dragged card would group it with: the dotted "Drop to group"
/// box (web `suggestOf`). `groupID` is set when it joins one of your groups.
nonisolated struct CanvasGroupSuggestion: Equatable, Sendable {
    var groupID: String?
    var members: [String]
    var name: String
    var joining: Bool
    var box: CGRect

    var label: String { joining ? "Drop to add to \(name)" : "Drop to group · \(name)" }
}

nonisolated enum CanvasSimilarity {
    static let skipSubject: Set<String> = ["website", "welcome", "home", "homepage", "introducing", "index", "page",
        "github", "the", "free", "team", "open", "new", "best", "list", "official", "online", "platform", "company",
        "app", "apps", "site", "blog", "about", "get", "your", "make"]

    static func cap(_ s: String) -> String {
        let t = s.replacingOccurrences(of: "[-_]+", with: " ", options: .regularExpression)
        return t.prefix(1).uppercased() + t.dropFirst()
    }

    /// Kind name as the card shows it (web `kindName`).
    static func kindName(kindLine: String?, kind: String, hasURL: Bool) -> String {
        if let line = kindLine, !line.isEmpty { return String(line.components(separatedBy: " · ")[0]) }
        if kind != "link" && !kind.isEmpty { return cap(kind) }
        return hasURL ? "Website" : "Note"
    }

    /// Features for one item (web `buildIndex`).
    static func features(tags: [ItemTag], kindName: String, domain: String?) -> [SimFeature] {
        func top(_ cat: String, _ min: Double) -> [ItemTag] {
            tags.filter { $0.category == cat && $0.weight >= min }.sorted { $0.weight > $1.weight }
        }
        var out: [SimFeature] = []
        let cols = Array(top("color", 0.3).prefix(2))
        cols.forEach { out.append(.init(key: "c:" + $0.name, kind: .colour, tag: $0.name)) }
        let styles = Array(top("style", 0.5).prefix(3))
        styles.forEach { out.append(.init(key: "s:" + $0.name, kind: .style, tag: $0.name)) }
        if let c = cols.first, let s = styles.first {
            out.append(.init(key: "l:\(c.name)|\(s.name)", kind: .looks, tag: "\(c.name), \(s.name)"))
        }
        let fmt = top("format", 0.4).first
        if kindName != "Website" && kindName != "Note" {
            out.append(.init(key: "k:" + kindName, kind: .kind, tag: kindName.lowercased()))
        } else if let fmt, fmt.name != "website" {
            out.append(.init(key: "k:" + fmt.name, kind: .kind, tag: fmt.name))
        }
        if let place = top("location", 0.3).first {
            let p = cap(place.name)
            out.append(.init(key: "p:" + p.lowercased(), kind: .place, tag: p))
        }
        let site = (domain ?? "").components(separatedBy: ".").first ?? ""
        top("subject", 0.6).filter { !skipSubject.contains($0.name) && $0.name != site }.prefix(4)
            .forEach { out.append(.init(key: "i:" + $0.name, kind: .idea, tag: $0.name)) }
        return out
    }

    /// The strongest few neighbours of one item among `set` (web `simFor`).
    static func neighbours(of slug: String, features: [String: [SimFeature]],
                           inverted: [String: [String]], limit: Int = 6) -> [SimLink] {
        let n = Double(max(features.count, 1))
        let capCount = max(40, min(600, n * 0.25))
        var score: [String: (total: Double, best: SimFeature, bw: Double)] = [:]
        for f in features[slug] ?? [] {
            guard let post = inverted[f.key], post.count >= 2, Double(post.count) <= capCount else { continue }
            let w = f.kind.weight * log(1 + n / Double(post.count))
            for b in post where b != slug {
                var s = score[b] ?? (0, f, 0)
                s.total += w
                if w > s.bw { s.bw = w; s.best = f }
                score[b] = s
            }
        }
        return score.filter { $0.value.total >= 1.8 }
            .sorted { $0.value.total > $1.value.total }
            .prefix(limit)
            .map { SimLink(a: slug, b: $0.key, kind: $0.value.best.kind, label: $0.value.best.tag, score: $0.value.total) }
    }

    static func invert(_ features: [String: [SimFeature]]) -> [String: [String]] {
        var inv: [String: [String]] = [:]
        for (slug, fs) in features { for f in fs { inv[f.key, default: []].append(slug) } }
        return inv
    }

    /// Shared features of a and b, strongest first (web `similarityScore`).
    static func shared(_ a: [SimFeature], _ b: [SimFeature]) -> (score: Double, tags: [SimFeature]) {
        let keys = Set(b.map(\.key))
        let both = a.filter { keys.contains($0.key) }.sorted { $0.kind.weight > $1.kind.weight }
        return (both.reduce(0) { $0 + $1.kind.weight }, both)
    }

    /// Families on the canvas. Your groups first; then a greedy cover by the most
    /// telling shared feature, keeping only members that sit together (within 90
    /// world units), as the web does once cards stay where you drop them.
    static func families(groups: [CanvasDoc.Group], rects: [String: CGRect],
                         features: [String: [SimFeature]], inverted: [String: [String]]) -> [CanvasFamily] {
        let n = Double(max(features.count, 1))
        var taken = Set<String>()
        var out: [CanvasFamily] = []
        for g in groups {
            let part = g.slugs.filter { rects[$0] != nil && !taken.contains($0) }
            guard part.count >= 2 else { continue }
            part.forEach { taken.insert($0) }
            out.append(CanvasFamily(id: "g:" + g.id, name: g.name.isEmpty ? "Group" : g.name, groupID: g.id, slugs: part))
        }
        let cands = inverted.compactMap { key, slugs -> (SimFeature, [String], Double)? in
            guard slugs.count >= 2, Double(slugs.count) < max(3, n * 0.9),
                  let f = features[slugs[0]]?.first(where: { $0.key == key }) else { return nil }
            let score = f.kind.weight * log(1 + n / Double(slugs.count)) * log2(1 + Double(min(slugs.count, 12)))
            return (f, slugs, score)
        }.sorted { $0.2 > $1.2 || ($0.2 == $1.2 && $0.0.key < $1.0.key) }
        for (f, slugs, _) in cands {
            let free = slugs.filter { !taken.contains($0) }
            guard free.count >= 2 else { continue }
            let together = largestCluster(free, rects: rects, gap: 90)
            guard together.count >= 2 else { continue }
            together.forEach { taken.insert($0) }
            out.append(CanvasFamily(id: "f:" + f.key, name: nil, kind: f.kind, slugs: together))
        }
        // Pills: your group's name, then up to four traits every member shares.
        for i in out.indices {
            var common: [SimFeature]? = nil
            for s in out[i].slugs {
                let fs = features[s] ?? []
                common = common.map { c in c.filter { x in fs.contains { $0.key == x.key } } } ?? fs
            }
            var traits = (common ?? []).sorted { $0.kind.weight > $1.kind.weight }
            if out[i].groupID == nil, let k = out[i].kind,
               let lead = traits.firstIndex(where: { $0.kind == k }) {
                traits.insert(traits.remove(at: lead), at: 0)
            }
            var pills: [String] = []
            if let name = out[i].name { pills.append(cap(name)) }
            for t in traits where pills.count < 4 {
                let p = cap(t.tag)
                if !pills.contains(where: { $0.lowercased() == p.lowercased() }) { pills.append(p) }
            }
            out[i].pills = pills.isEmpty ? ["Group"] : pills
        }
        return out
    }

    /// A dragged card at `rect`: the closest other card within `snap` and what dropping
    /// would group it with (web `suggestOf`). Nil when that card already shares its family.
    static func suggestion(for slug: String, at rect: CGRect, rects: [String: CGRect],
                           families: [CanvasFamily], features: [String: [SimFeature]],
                           snap: CGFloat = 56) -> CanvasGroupSuggestion? {
        var best: (slug: String, gap: CGFloat)?
        for (b, m) in rects where b != slug {
            let gx = max(0, m.minX - rect.maxX, rect.minX - m.maxX)
            let gy = max(0, m.minY - rect.maxY, rect.minY - m.maxY)
            let g = hypot(gx, gy)
            guard g <= snap else { continue }
            if let cur = best, g > cur.gap || (g == cur.gap && b > cur.slug) { continue }
            best = (b, g)
        }
        guard let target = best?.slug else { return nil }
        let fam = families.first { $0.slugs.contains(target) }
        if let fam, fam.slugs.contains(slug) { return nil }
        let members = fam.map { $0.slugs.filter { $0 != slug } } ?? [target]
        let box = members.compactMap { rects[$0] }.reduce(rect) { $0.union($1) }
        let name = fam?.pills.first
            ?? shared(features[slug] ?? [], features[target] ?? []).tags.first.map { cap($0.tag) }
            ?? "New group"
        return .init(groupID: fam?.groupID, members: members, name: name, joining: fam != nil, box: box)
    }

    /// Dropped clear of its group: the card's centre is more than `pad` outside the
    /// box of the other members (web `refamily`).
    static func leaves(_ rect: CGRect, others: [CGRect], pad: CGFloat = 60) -> Bool {
        guard let first = others.first else { return false }
        let box = others.dropFirst().reduce(first) { $0.union($1) }.insetBy(dx: -pad, dy: -pad)
        return !box.contains(CGPoint(x: rect.midX, y: rect.midY))
    }

    /// While dragging: related cards within `reach`, nearer and stronger first (web `nearOf`).
    static func near(_ slug: String, at rect: CGRect, rects: [String: CGRect],
                     features: [String: [SimFeature]], reach: CGFloat = 720) -> [SimNear] {
        let mine = features[slug] ?? []
        guard !mine.isEmpty else { return [] }
        var out: [SimNear] = []
        for (b, m) in rects where b != slug {
            let d = max(0, hypot(m.midX - rect.midX, m.midY - rect.midY) - rect.width)
            guard d <= reach else { continue }
            let both = shared(mine, features[b] ?? [])
            guard both.score >= 1.4, let top = both.tags.first else { continue }
            out.append(.init(b: b, kind: top.kind, label: top.tag, score: both.score, distance: d))
        }
        return Array(out.sorted {
            let l = $0.score - $0.distance / 300, r = $1.score - $1.distance / 300
            return l != r ? l > r : $0.b < $1.b
        }.prefix(10))
    }

    /// The biggest set of slugs chained together by gaps of at most `gap`.
    static func largestCluster(_ slugs: [String], rects: [String: CGRect], gap: CGFloat) -> [String] {
        var left = Set(slugs), best: [String] = []
        while let first = left.first {
            left.remove(first)
            var comp = [first], queue = [first]
            while let s = queue.popLast() {
                guard let r = rects[s]?.insetBy(dx: -gap, dy: -gap) else { continue }
                for o in left where rects[o].map(r.intersects) == true {
                    left.remove(o); comp.append(o); queue.append(o)
                }
            }
            if comp.count > best.count { best = comp }
        }
        return best.sorted()
    }

    /// Lines are straight runs with 90° bends (web `route`), or one segment when the
    /// two ends are close.
    static func route(from a: CGRect, to b: CGRect, straightBelow: CGFloat = 230) -> [CGPoint] {
        let ca = CGPoint(x: a.midX, y: a.midY), cb = CGPoint(x: b.midX, y: b.midY)
        let dx = cb.x - ca.x, dy = cb.y - ca.y
        if hypot(dx, dy) < straightBelow + a.width / 2 {
            return [edgePoint(a, toward: cb), edgePoint(b, toward: ca)]
        }
        if abs(dx) >= abs(dy) {
            let p0 = CGPoint(x: dx > 0 ? a.maxX : a.minX, y: a.midY)
            let p3 = CGPoint(x: dx > 0 ? b.minX : b.maxX, y: b.midY)
            let mx = (p0.x + p3.x) / 2
            return [p0, CGPoint(x: mx, y: p0.y), CGPoint(x: mx, y: p3.y), p3]
        } else {
            let p0 = CGPoint(x: a.midX, y: dy > 0 ? a.maxY : a.minY)
            let p3 = CGPoint(x: b.midX, y: dy > 0 ? b.minY : b.maxY)
            let my = (p0.y + p3.y) / 2
            return [p0, CGPoint(x: p0.x, y: my), CGPoint(x: p3.x, y: my), p3]
        }
    }

    static func edgePoint(_ r: CGRect, toward p: CGPoint) -> CGPoint {
        let c = CGPoint(x: r.midX, y: r.midY)
        let dx = p.x - c.x, dy = p.y - c.y
        guard dx != 0 || dy != 0 else { return c }
        let sx = dx == 0 ? CGFloat.infinity : (r.width / 2) / abs(dx)
        let sy = dy == 0 ? CGFloat.infinity : (r.height / 2) / abs(dy)
        let s = min(sx, sy)
        return CGPoint(x: c.x + dx * s, y: c.y + dy * s)
    }
}

extension SimKind {
    func color(text: Color) -> Color { hex.map { Color(hex: $0) } ?? text }
}

// MARK: - Gaps: one maybe-related save per group

/// One library item, reduced to what the "+ Maybe" scan reads (web `featuresLoose`).
nonisolated struct MaybeEntry: Sendable {
    let slug: String
    let title: String
    let features: [SimFeature]
}

/// The save a group's dashed "+ Maybe" pill offers (web `famMeta` ghost).
nonisolated struct MaybePick: Equatable, Sendable {
    let slug: String
    let title: String
    let shared: [String]
}

/// What the snapshot reads from an item on the main actor; features are built off it.
nonisolated struct MaybeRaw: Sendable {
    let slug: String
    let title: String
    let domain: String?
    let tagsJSON: String?
    let kind: String
    let metadataJSON: String?
    let hasURL: Bool
}

extension CanvasSimilarity {
    /// Loose features for the library scan (web `featuresLoose`): top two colours, top
    /// three styles, the place, up to four ideas, and the kind unless Website / Note.
    static func looseFeatures(tags: [ItemTag], kindName: String) -> [SimFeature] {
        func top(_ cat: String, _ min: Double) -> [ItemTag] {
            tags.filter { $0.category == cat && $0.weight >= min }.sorted { $0.weight > $1.weight }
        }
        var out: [SimFeature] = []
        top("color", 0.3).prefix(2).forEach { out.append(.init(key: "c:" + $0.name, kind: .colour, tag: $0.name)) }
        top("style", 0.5).prefix(3).forEach { out.append(.init(key: "s:" + $0.name, kind: .style, tag: $0.name)) }
        if let place = top("location", 0.3).first {
            let p = cap(place.name)
            out.append(.init(key: "p:" + p.lowercased(), kind: .place, tag: p))
        }
        top("subject", 0.6).filter { !skipSubject.contains($0.name) }.prefix(4)
            .forEach { out.append(.init(key: "i:" + $0.name, kind: .idea, tag: $0.name)) }
        if kindName != "Website" && kindName != "Note" {
            out.append(.init(key: "k:" + kindName, kind: .kind, tag: kindName.lowercased()))
        }
        return out
    }

    /// Builds the scan entries off the main actor (tag JSON decode, kind line).
    static func maybeEntries(_ raws: [MaybeRaw]) -> [MaybeEntry] {
        raws.map { r in
            let line = kindLine(kind: r.kind, metadataJSON: r.metadataJSON)
            let k = kindName(kindLine: line, kind: r.kind, hasURL: r.hasURL)
            return MaybeEntry(slug: r.slug, title: r.title.isEmpty ? (r.domain ?? "Untitled") : r.title,
                              features: looseFeatures(tags: ItemTag.decode(r.tagsJSON), kindName: k))
        }
    }

    /// `Item.cardKindLine` from the stored fields, so it can run off the main actor.
    static func kindLine(kind: String, metadataJSON: String?) -> String? {
        guard let data = metadataJSON?.data(using: .utf8) else { return nil }
        let d = JSONDecoder()
        switch kind {
        case "product": return (try? d.decode(ProductMeta.self, from: data))?.cardKindLine
        case "post": return (try? d.decode(PostMeta.self, from: data))?.cardKindLine
        case "tool": return (try? d.decode(ToolMeta.self, from: data))?.cardKindLine
        case "resource": return (try? d.decode(ResourceMeta.self, from: data))?.cardKindLine
        case "book": return (try? d.decode(BookMeta.self, from: data))?.cardKindLine
        case "course": return (try? d.decode(CourseMeta.self, from: data))?.cardKindLine
        case "article": return (try? d.decode(ArticleMeta.self, from: data))?.cardKindLine
        default: return nil
        }
    }

    /// The one save from the rest of the library that best fits a group (web `famMeta`):
    /// members' features weighted by kind, the best scorer not on the canvas and not
    /// dismissed, kept only when it shares two traits and scores at least
    /// max(3, members × 0.35).
    static func maybe(members: [[SimFeature]], memberCount: Int, library: [MaybeEntry],
                      exclude: Set<String>) -> MaybePick? {
        guard memberCount >= 2 else { return nil }
        var want: [String: Double] = [:]
        for fs in members.prefix(24) { for f in fs { want[f.key, default: 0] += f.kind.weight } }
        guard !want.isEmpty else { return nil }
        var best: (e: MaybeEntry, s: Double, shared: [String])?
        for e in library where !exclude.contains(e.slug) {
            var s = 0.0
            var shared: [String] = []
            for f in e.features { if let w = want[f.key] { s += w; shared.append(f.tag) } }
            if best == nil || s > best!.s { best = (e, s, shared) }
        }
        guard let best, best.shared.count >= 2, best.s >= max(3, Double(memberCount) * 0.35) else { return nil }
        var seen = Set<String>()
        let shared = best.shared.filter { seen.insert($0).inserted }.prefix(3)
        return MaybePick(slug: best.e.slug, title: best.e.title, shared: Array(shared))
    }

    /// Web `shortTitle`: the part before " | " / " – " etc., cut to about 24 characters.
    static func shortTitle(_ t: String) -> String {
        let base = (t.range(of: #"\s[|•·–—-]\s"#, options: .regularExpression).map { String(t[..<$0.lowerBound]) } ?? t)
            .trimmingCharacters(in: .whitespaces)
        guard base.count > 24 else { return base }
        let cut = String(base.prefix(24))
        if let sp = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: sp) > 10 {
            return String(cut[..<sp]) + "…"
        }
        return cut + "…"
    }
}
