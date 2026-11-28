import Foundation
import CryptoKit

/// Folder ingest (folder engine plan 4b, part 3): the person's own files in a folder (not
/// Stello item files) turned into items. Pure: no file access, no network.
/// Web twin: src/lib/folder-ingest.js. Both are checked against the same expected output
/// (test/fixtures/folder-ingest.json → FolderIngestFixtures, regenerate with
/// `node scripts/make-folder-ingest-fixtures.mjs`).
///
/// What each file gives (plan doc, "What the engine takes from it"):
/// - Markdown, plain text: every link; the rest of its line as a note; the headings above it as tags
/// - .webloc, .url: the one link; the file name as its title
/// - CSV: the URL column, plus title, tags, notes, folder and date columns when found
/// - Bookmarks HTML: every link, with its folders as tags and the saved date
/// Images and PDFs come in the next chunk.
///
/// Collections are retired, so headings and bookmark folders become subject tags. Nothing
/// here calls AI or reads a page (import speed rule): a new link is a plain link
/// (`awaiting_classify`) that the background pass sorts, as for any web save.
nonisolated enum FolderIngest {
    static let maxFileBytes = 20 * 1024 * 1024
    static let tagWeight = 0.6
    static let maxTags = 8

    struct Link: Equatable, Sendable {
        var url: String
        var key: String
        var title: String?
        var note: String?
        var summary: String?
        var tags: [String]
        var added: String?
    }

    // MARK: - Which files

    private static let types = ["md": "markdown", "markdown": "markdown", "txt": "markdown", "webloc": "webloc",
                                "url": "url", "csv": "csv", "html": "bookmarks", "htm": "bookmarks"]

    /// The kind of file Stello reads links from, by its name, or nil.
    static func ingestType(_ path: String) -> String? {
        let name = path.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? ""
        if name.isEmpty || name.hasPrefix(".") { return nil }
        guard let m = first(extRE, name), let ext = group(m, 1, name) else { return nil }
        return types[ext.lowercased()]
    }
    private static let extRE = re("\\.([a-z0-9]+)$", ci: true)

    // MARK: - Regex helpers

    private static func re(_ p: String, ci: Bool = false, lines: Bool = false) -> NSRegularExpression {
        var o: NSRegularExpression.Options = []
        if ci { o.insert(.caseInsensitive) }
        if lines { o.insert(.anchorsMatchLines) }
        return try! NSRegularExpression(pattern: p, options: o)
    }
    private static func first(_ r: NSRegularExpression, _ s: String) -> NSTextCheckingResult? {
        r.firstMatch(in: s, range: NSRange(s.startIndex..., in: s))
    }
    private static func all(_ r: NSRegularExpression, _ s: String) -> [NSTextCheckingResult] {
        r.matches(in: s, range: NSRange(s.startIndex..., in: s))
    }
    private static func group(_ m: NSTextCheckingResult, _ i: Int, _ s: String) -> String? {
        guard i < m.numberOfRanges, m.range(at: i).location != NSNotFound, let r = Range(m.range(at: i), in: s) else { return nil }
        return String(s[r])
    }
    private static func sub(_ s: String, _ r: NSRegularExpression, _ with: String) -> String {
        r.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: with)
    }
    /// Replace each match with what `f` returns (JS `String.replace` with a function).
    private static func sub(_ s: String, _ r: NSRegularExpression, _ f: (NSTextCheckingResult) -> String) -> String {
        var out = ""
        var last = s.startIndex
        for m in all(r, s) {
            guard let range = Range(m.range, in: s) else { continue }
            out += s[last..<range.lowerBound]
            out += f(m)
            last = range.upperBound
        }
        return out + s[last...]
    }

    /// JS `\s`-style trim (Unicode spaces, line ends, BOM).
    private static let space = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}"))
    private static let spaces = re("\\s+")
    static func squash(_ s: String?) -> String { sub(s ?? "", spaces, " ").trimmingCharacters(in: space) }

    // MARK: - Small helpers

    private static let entityRE = re("&(#x[0-9a-f]+|#\\d+|[a-z]+\\d*);", ci: true)
    private static let named = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ", "#39": "'"]
    static func decodeEntities(_ s: String) -> String {
        sub(s, entityRE) { m in
            let all = group(m, 0, s) ?? ""
            let e = group(m, 1, s) ?? ""
            if e.hasPrefix("#") {
                let hexed = e.dropFirst().first == "x" || e.dropFirst().first == "X"
                let n = hexed ? Int(e.dropFirst(2), radix: 16) : Int(e.dropFirst())
                if let n, n > 0, n < 0x110000, let u = Unicode.Scalar(n) { return String(Character(u)) }
                return all
            }
            return named[e.lowercased()] ?? all
        }
    }

    private static let nonAlnum = re("[^a-z0-9]+")
    private static let edgeDashes = re("^-+|-+$")
    private static let trailingDashes = re("-+$")
    /// "Type & Lettering" → "type-lettering".
    static func tagSlug(_ s: String) -> String {
        let folded = String(String.UnicodeScalarView(s.lowercased().decomposedStringWithCompatibilityMapping.unicodeScalars
            .filter { !(0x300...0x36F).contains($0.value) }))
        let slug = sub(sub(folded, nonAlnum, "-"), edgeDashes, "")
        return sub(String(slug.prefix(40)), trailingDashes, "")
    }

    private static func addTags(_ list: inout [String], _ names: [String]) {
        for n in names {
            let t = tagSlug(n)
            if !t.isEmpty, !list.contains(t) { list.append(t) }
        }
    }

    private static let trailingPunct = re("[.,;:!?'\"*_~]+$")
    private static let validURL = re("^https?://[^\\s/?#]+\\.[^\\s/?#]", ci: true)
    private static let angle = re("^<|>$")
    /// An http(s) link with its trailing punctuation removed, or nil.
    static func cleanURL(_ raw: String) -> String? {
        var u = sub(raw.trimmingCharacters(in: space), angle, "")
        while true {
            let before = u
            u = sub(u, trailingPunct, "")
            if u.hasSuffix(")"), u.filter({ $0 == "(" }).count < u.filter({ $0 == ")" }).count { u.removeLast() }
            if u.hasSuffix("]"), !u.contains("[") { u.removeLast() }
            if u == before { break }
        }
        guard first(validURL, u) != nil, URL(string: u) != nil || URL(string: u, encodingInvalidCharacters: true) != nil else { return nil }
        return u
    }

    private static let extTail = re("\\.[a-z0-9]+$", ci: true)
    private static let underscores = re("[_]+")
    private static func fileTitle(_ path: String) -> String? {
        let name = path.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? ""
        let t = squash(sub(sub(name, extTail, ""), underscores, " "))
        return t.isEmpty ? nil : t
    }

    private static let isoOut: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
    static func iso(_ d: Date) -> String { isoOut.string(from: d) }

    private static let unixRE = re("^\\d{9,13}(\\.\\d+)?$")
    /// A date from a sheet or bookmark: unix seconds or ms, or ISO-8601 / a plain day. ISO, or nil.
    /// (The web also reads other date texts its browser understands; those rare ones fall
    /// back to the file's date here.)
    static func toISO(_ v: String?) -> String? {
        let s = (v ?? "").trimmingCharacters(in: space)
        if s.isEmpty { return nil }
        if first(unixRE, s) != nil, let n = Double(s) {
            return iso(Date(timeIntervalSince1970: (n > 1e11 ? n : n * 1000) / 1000))
        }
        let full = ISO8601DateFormatter()
        full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = full.date(from: s) { return iso(d) }
        full.formatOptions = [.withInternetDateTime]
        if let d = full.date(from: s) { return iso(d) }
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = TimeZone(identifier: "UTC")
        day.dateFormat = "yyyy-MM-dd"
        if let d = day.date(from: s) { return iso(d) }
        day.timeZone = .current
        day.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let d = day.date(from: s) { return iso(d) }
        return nil
    }

    /// Links collected from one file, one per link key (first sighting wins, tags combine).
    private struct Collector {
        var order: [String] = []
        var byKey: [String: Link] = [:]
        mutating func add(url raw: String?, title: String? = nil, note: String? = nil, summary: String? = nil,
                          tags: [String] = [], added: String?) {
            guard let raw, let url = cleanURL(raw) else { return }
            let key = FolderIngest.normaliseURL(url)
            if var old = byKey[key] {
                FolderIngest.addTags(&old.tags, tags)
                if old.title == nil, let t = title, !squash(t).isEmpty { old.title = squash(t) }
                if old.note == nil, let n = note, !squash(n).isEmpty { old.note = squash(n) }
                byKey[key] = old
                return
            }
            var list: [String] = []
            FolderIngest.addTags(&list, tags)
            func nz(_ s: String?) -> String? { let t = squash(s); return t.isEmpty ? nil : t }
            byKey[key] = Link(url: url, key: key, title: nz(title), note: nz(note), summary: nz(summary),
                              tags: Array(list.prefix(maxTags)), added: added)
            order.append(key)
        }
        var list: [Link] { order.compactMap { k in byKey[k].map { var l = $0; l.tags = Array(l.tags.prefix(maxTags)); return l } } }
    }

    // MARK: - Link keys (twin of normaliseUrl in src/lib/folder-v2.js)

    private static let dropParams: Set<String> = ["fbclid", "gclid", "mc_cid", "mc_eid", "ref", "ref_src"]
    private static let slashes = re("/+$")
    /// One key per link: no fragment, no www., no tracking parameters, no trailing slash, https.
    static func normaliseURL(_ url: String) -> String {
        let raw = url.trimmingCharacters(in: space)
        guard let parsed = URL(string: raw) ?? URL(string: raw, encodingInvalidCharacters: true),
              var c = URLComponents(url: parsed, resolvingAgainstBaseURL: false),
              let scheme = c.scheme?.lowercased(), let host = c.host, !host.isEmpty else { return raw.lowercased() }
        var h = host.lowercased()
        if h.hasPrefix("www.") { h = String(h.dropFirst(4)) }
        let port = c.port.flatMap { p -> String? in
            (scheme == "https" && p == 443) || (scheme == "http" && p == 80) ? nil : ":\(p)"
        } ?? ""
        var query = ""
        if let q = c.percentEncodedQuery, !q.isEmpty {
            let pairs = q.split(separator: "&", omittingEmptySubsequences: false).map(String.init)
            let keep = pairs.filter { pair in
                let name = (pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? "")
                let k = (name.removingPercentEncoding ?? name).lowercased()
                return !(k.hasPrefix("utm_") || dropParams.contains(k))
            }
            if keep.count == pairs.count { query = "?" + q }
            else { query = keep.filter { !$0.isEmpty }.isEmpty ? "" : "?" + keep.filter { !$0.isEmpty }.joined(separator: "&") }
        }
        c.fragment = nil
        let path = sub(c.percentEncodedPath, slashes, "")
        let s = "\(scheme)://\(h)\(port)\(path)\(query)"
        return scheme == "http" ? "https" + s.dropFirst(4) : s
    }

    // MARK: - Markdown and plain text

    private static let mdImage = re("!\\[[^\\]]*\\]\\([^)]*\\)")
    private static let mdLink = re("\\[([^\\]]*)\\]\\(\\s*<?(https?://[^)\\s>]+)>?(?:\\s+\"[^\"]*\")?\\s*\\)", ci: true)
    private static let mdAnyLink = re("\\[([^\\]]*)\\]\\([^)]*\\)")
    private static let autoLink = re("<(https?://[^>\\s]+)>", ci: true)
    private static let bareURL = re("https?://[^\\s<>\"'`\\[\\]{}|\\\\^]+", ci: true)
    private static let emphasis = re("[*_`~]+")
    private static let htmlTag = re("<[^>]+>")
    private static let quotePrefix = re("^\\s*(?:>\\s*)*")
    private static let listPrefix = re("^\\s*(?:[-*+]|\\d+[.)])\\s+")
    private static let checkbox = re("^\\s*\\[[ xX]\\]\\s+")
    private static let emptyParens = re("\\(\\s*\\)")
    private static let loneOpen = re("(^|\\s)[(\\[](?=\\s|$)")
    private static let loneClose = re("(^|\\s)[)\\]](?=\\s|$)")
    private static let noteEdges = re("^[\\s\\-–—:|,;·•]+|[\\s\\-–—:|,;·•(]+$")
    private static let fenceRE = re("^\\s*(```|~~~)")
    private static let headingRE = re("^(#{1,6})\\s+(.*?)\\s*#*\\s*$")
    private static let hasLink = re("https?://", ci: true)

    private static func stripInline(_ s: String) -> String {
        sub(sub(sub(sub(s, mdImage, ""), mdAnyLink, "$1"), emphasis, ""), htmlTag, "")
    }

    /// What's left of a line once its links are taken out: the link's note.
    private static func lineNote(_ line: String) -> String? {
        var s = line
        for r in [mdImage, mdLink, autoLink, bareURL] { s = sub(s, r, " ") }
        s = sub(sub(sub(sub(s, quotePrefix, ""), listPrefix, ""), checkbox, ""), emphasis, "")
        s = squash(sub(sub(sub(s, emptyParens, " "), loneOpen, "$1"), loneClose, "$1"))
        s = sub(s, noteEdges, "").trimmingCharacters(in: space)
        return s.utf16.count >= 3 ? s : nil
    }

    private static func lines(_ text: String) -> [String] {
        var t = text
        if t.hasPrefix("\u{FEFF}") { t.removeFirst() }
        // Split on \n by scalars ("\r\n" is one Character in Swift), dropping the \r of \r\n.
        var out: [String] = []
        var cur = String.UnicodeScalarView()
        for u in t.unicodeScalars {
            if u == "\n" {
                if cur.last == "\r" { cur.removeLast() }
                out.append(String(cur)); cur = .init()
            } else { cur.append(u) }
        }
        out.append(String(cur))
        return out
    }

    private static func readMarkdown(_ text: String, added: String?) -> [Link] {
        var out = Collector()
        var ls = lines(text)
        // A front-matter block (Obsidian and others) holds no saves.
        if ls.first == "---", let end = ls.dropFirst().firstIndex(of: "---") { ls = Array(ls[(end + 1)...]) }
        var heads: [(level: Int, name: String)] = []
        var fence: String?
        for line in ls {
            if let f = first(fenceRE, line), let mark = group(f, 1, line) {
                fence = fence == mark ? nil : (fence ?? mark)
                continue
            }
            if fence != nil { continue }
            let h = first(headingRE, line)
            if let h, let hashes = group(h, 1, line) {
                let level = hashes.count
                while let last = heads.last, last.level >= level { heads.removeLast() }
                let name = squash(stripInline(group(h, 2, line) ?? ""))
                if !name.isEmpty { heads.append((level, name)) }
            }
            guard first(hasLink, line) != nil else { continue }
            let tags = heads.suffix(3).map(\.name)
            let note = h != nil ? nil : lineNote(line)
            var found: [(url: String, title: String?)] = []
            let noImages = sub(line, mdImage, " ")
            let noLinks = sub(noImages, mdLink) { m in
                let title = squash(stripInline(group(m, 1, noImages) ?? ""))
                let isURL = title.range(of: "^https?://", options: [.regularExpression, .caseInsensitive]) != nil
                found.append((group(m, 2, noImages) ?? "", title.isEmpty || isURL ? nil : title))
                return " "
            }
            let rest = sub(noLinks, autoLink) { m in found.append((group(m, 1, noLinks) ?? "", nil)); return " " }
            for m in all(bareURL, rest) { if let u = group(m, 0, rest) { found.append((u, nil)) } }
            // Several links on one line share no single note.
            for l in found { out.add(url: l.url, title: l.title, note: found.count == 1 ? note : nil, tags: tags, added: added) }
        }
        return out.list
    }

    // MARK: - .webloc and .url

    private static let weblocString = re("<string>\\s*(https?://[^<\\s]+)\\s*</string>", ci: true)
    private static let weblocBytes = re("(https?://[\\x21-\\x7e]+)")
    private static let urlLine = re("^\\s*URL\\s*=\\s*(\\S+)\\s*$", ci: true, lines: true)

    private static func readWebloc(_ text: String, path: String, added: String?) -> [Link] {
        // XML plists hold the link in <string>; binary plists keep it as plain ASCII bytes.
        guard let m = first(weblocString, text) ?? first(weblocBytes, text), let u = group(m, 1, text) else { return [] }
        var out = Collector()
        out.add(url: decodeEntities(u), title: fileTitle(path), added: added)
        return out.list
    }

    private static func readURLFile(_ text: String, path: String, added: String?) -> [Link] {
        guard let m = first(urlLine, text), let u = group(m, 1, text) else { return [] }
        var out = Collector()
        out.add(url: u, title: fileTitle(path), added: added)
        return out.list
    }

    // MARK: - CSV

    /// RFC 4180 rows: quoted fields, doubled quotes, newlines inside quotes.
    static func parseCSV(_ text: String, delim: Unicode.Scalar = ",") -> [[String]] {
        var t = text
        if t.hasPrefix("\u{FEFF}") { t.removeFirst() }
        let s = Array(t.unicodeScalars)
        var rows: [[String]] = []
        var row: [String] = []
        var field = String.UnicodeScalarView()
        var quoted = false
        var i = 0
        func endRow() {
            row.append(String(field)); field = .init()
            if row.count > 1 || row[0] != "" { rows.append(row) }
            row = []
        }
        while i < s.count {
            let c = s[i]
            if quoted {
                if c == "\"" {
                    if i + 1 < s.count, s[i + 1] == "\"" { field.append("\""); i += 1 } else { quoted = false }
                } else { field.append(c) }
            } else if c == "\"", field.isEmpty { quoted = true }
            else if c == delim { row.append(String(field)); field = .init() }
            else if c == "\n" || c == "\r" {
                if c == "\r", i + 1 < s.count, s[i + 1] == "\n" { i += 1 }
                endRow()
            } else { field.append(c) }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { endRow() }
        return rows
    }

    private static func delimiter(_ text: String) -> Unicode.Scalar {
        let firstLine = lines(text).first ?? ""
        let counts: [(Unicode.Scalar, Int)] = [(",", 0), (";", 0), ("\t", 0)].map { d in
            (d.0, firstLine.unicodeScalars.filter { $0 == d.0 }.count)
        }
        // Stable: on a tie the earlier one (comma) wins, as in the web's sort.
        var best = counts[0]
        for c in counts.dropFirst() where c.1 > best.1 { best = c }
        return best.1 > 0 ? best.0 : ","
    }

    private static let cols: [String: [String]] = [
        "url": ["url", "link", "href", "source url", "source_url", "uri", "address", "website", "web address", "page url"],
        "title": ["title", "name", "page title", "bookmark"],
        "note": ["note", "notes", "comment", "comments", "highlights", "annotation", "annotations"],
        "summary": ["excerpt", "description", "summary"],
        "tags": ["tags", "tag", "labels", "label", "keywords"],
        "folder": ["folder", "collection", "category", "list", "group"],
        "date": ["created", "created_at", "created at", "date added", "added", "added_at", "added at", "time_added", "saved", "saved at", "date", "timestamp"],
    ]
    private static let notFolders: Set<String> = ["unsorted", "uncategorized", "uncategorised", "none", "default"]
    private static let startsHTTP = re("^\\s*https?://", ci: true)
    private static let tagSplit = CharacterSet(charactersIn: ",;|")

    private static func readCSV(_ text: String, added: String?) -> [Link] {
        let rows = parseCSV(text, delim: delimiter(text))
        guard rows.count >= 2 else { return [] }
        let head = rows[0].map { squash($0).lowercased() }
        func col(_ key: String) -> Int { for n in cols[key]! { if let i = head.firstIndex(of: n) { return i } }; return -1 }
        var url = col("url")
        if url < 0 {
            // No named column: the one whose values are mostly links.
            var best = -1, bestShare = 0.5
            for c in 0..<head.count {
                let vals = rows.dropFirst().prefix(40).compactMap { c < $0.count ? $0[c] : nil }
                    .filter { !$0.trimmingCharacters(in: space).isEmpty }
                let share = vals.isEmpty ? 0 : Double(vals.filter { first(startsHTTP, $0) != nil }.count) / Double(vals.count)
                if share > bestShare { best = c; bestShare = share }
            }
            url = best
        }
        guard url >= 0 else { return [] }
        let at = (title: col("title"), note: col("note"), summary: col("summary"), tags: col("tags"), folder: col("folder"), date: col("date"))
        var out = Collector()
        for r in rows.dropFirst() {
            func get(_ i: Int) -> String { i >= 0 && i < r.count ? r[i] : "" }
            let tags = get(at.tags).components(separatedBy: tagSplit).map { $0.trimmingCharacters(in: space) }.filter { !$0.isEmpty }
            let folder = get(at.folder).components(separatedBy: "/").map { $0.trimmingCharacters(in: space) }
                .filter { !$0.isEmpty && !notFolders.contains($0.lowercased()) }
            out.add(url: get(url).trimmingCharacters(in: space), title: get(at.title), note: get(at.note),
                    summary: get(at.summary), tags: folder + tags, added: toISO(get(at.date)) ?? added)
        }
        return out.list
    }

    // MARK: - Browser bookmarks (Netscape bookmark file)

    private static let rootFolders: Set<String> = ["bookmarks bar", "bookmarks menu", "bookmarks toolbar", "other bookmarks",
        "mobile bookmarks", "favorites", "favourites", "favorites bar", "bookmarks", "imported", "reading list"]
    private static let netscape = re("NETSCAPE-Bookmark-file", ci: true)
    private static let bookmarkToken = re("<h3\\b[^>]*>([\\s\\S]*?)</h3>|<dl\\b[^>]*>|</dl>|<a\\b([^>]*)>([\\s\\S]*?)</a>|<dd>([^<]*)", ci: true)

    private static func attr(_ attrs: String, _ name: String) -> String? {
        let r = re("\\b\(name)\\s*=\\s*(\"([^\"]*)\"|'([^']*)'|([^\\s>]+))", ci: true)
        guard let m = first(r, attrs) else { return nil }
        return decodeEntities(group(m, 2, attrs) ?? group(m, 3, attrs) ?? group(m, 4, attrs) ?? "")
    }

    private static func readBookmarks(_ text: String, added: String?) -> [Link] {
        guard first(netscape, text) != nil else { return [] }
        var out = Collector()
        var stack: [String?] = []
        var pending: String?
        var last: (url: String?, title: String, tags: [String], added: String?)?
        for m in all(bookmarkToken, text) {
            let whole = group(m, 0, text) ?? ""
            let tag = String(whole.prefix(4)).lowercased()
            if let h3 = group(m, 1, text) {
                pending = squash(decodeEntities(sub(h3, htmlTag, "")))
                last = nil
            } else if tag.hasPrefix("<dl") { stack.append(pending); pending = nil }
            else if tag.hasPrefix("</dl") { if !stack.isEmpty { stack.removeLast() }; pending = nil }
            else if let attrs = group(m, 2, text) {
                let folders = stack.compactMap { $0 }.filter { !$0.isEmpty && !rootFolders.contains($0.lowercased()) }
                let own = (attr(attrs, "tags") ?? "").components(separatedBy: ",").map { $0.trimmingCharacters(in: space) }.filter { !$0.isEmpty }
                let l = (url: attr(attrs, "href"), title: squash(decodeEntities(sub(group(m, 3, text) ?? "", htmlTag, ""))),
                         tags: Array(folders.suffix(3)) + own, added: toISO(attr(attrs, "add_date")) ?? added)
                last = l
                out.add(url: l.url, title: l.title, tags: l.tags, added: l.added)
            } else if let dd = group(m, 4, text), let l = last {
                // <DD> right after a link is its description.
                let note = squash(decodeEntities(dd))
                if !note.isEmpty { out.add(url: l.url, title: l.title, note: note, tags: l.tags, added: l.added) }
                last = nil
            }
        }
        return out.list
    }

    // MARK: - Entry points

    /// Links in one file. `modified` dates links that carry no date of their own.
    static func readLinks(path: String, text: String, modified: Date?) -> [Link] {
        let added = modified.map(iso)
        switch ingestType(path) {
        case "markdown": return readMarkdown(text, added: added)
        case "webloc": return readWebloc(text, path: path, added: added)
        case "url": return readURLFile(text, path: path, added: added)
        case "csv": return readCSV(text, added: added)
        case "bookmarks": return readBookmarks(text, added: added)
        default: return []
        }
    }

    /// Link key → UUID (SHA-256, version 8), so every device makes the same id for one link.
    static func linkItemID(_ key: String) -> UUID {
        var b = Array(SHA256.hash(data: Data("stello-link\n\(key)".utf8)).prefix(16))
        b[6] = (b[6] & 0x0f) | 0x80
        b[8] = (b[8] & 0x3f) | 0x80
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }

    /// "Future-facing fonts" → "future-facing-fonts-4c9f18".
    static func linkSlug(_ title: String, id: UUID) -> String {
        let base = sub(String(tagSlug(title).prefix(60)), trailingDashes, "")
        return "\(base.isEmpty ? "item" : base)-\(id.uuidString.lowercased().prefix(6))"
    }

    static func domain(_ url: String) -> String? {
        guard let h = URLComponents(string: url)?.host?.lowercased(), !h.isEmpty else { return nil }
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }

    /// A new item's fields (wire names, as the web's linkChange): a plain link waiting for
    /// the background pass to sort it.
    struct NewItem: Equatable {
        var id: UUID
        var slug: String
        var title: String
        var sourceURL: String
        var domain: String?
        var summary: String?
        var body: String?
        var addedAt: String
        var tags: [String]
    }

    static func newItem(_ link: Link, id: UUID, now: String) -> NewItem {
        let dom = domain(link.url)
        let title = String((link.title ?? dom ?? link.url).prefix(300))
        return NewItem(id: id, slug: linkSlug(title, id: id), title: title, sourceURL: link.url, domain: dom,
                       summary: link.summary.map { String($0.prefix(300)) }, body: link.note,
                       addedAt: link.added ?? now, tags: link.tags)
    }
}

// MARK: - Written notes (folder-ingest.js "Written notes")
// A Markdown note with about 50 words or more of the person's own writing (links, headings
// and code not counted) is an item itself (Arjun, Nov 28 2026). Stello adds its details at
// the top of that same file; the text and any details already there are kept. Its links
// still become their own items. A note that is mostly a list of links stays hidden.

extension FolderIngest {
    typealias JSON = FolderWriter.JSON
    static let noteWords = 50
    static let noteTagWeight = 0.9

    private static let frontRE: NSRegularExpression = try! NSRegularExpression(
        pattern: "^---\\r?\\n([\\s\\S]*?)\\r?\\n---[ \\t]*(?:\\r?\\n|$)", options: [])
    private static let headingLine = re("^\\s*#{1,6}\\s")
    private static let wordRE = re("[\\p{L}\\p{N}][\\p{L}\\p{N}'’-]*")
    private static let noteExt = re("\\.(md|markdown)$", ci: true)

    /// A Markdown file → its front-matter lines (nil when it has none) and the text after them.
    static func splitFront(_ text: String) -> (front: [String]?, body: String) {
        var src = text
        if src.hasPrefix("\u{FEFF}") { src.removeFirst() }
        let ns = src as NSString
        guard let m = frontRE.firstMatch(in: src, range: NSRange(location: 0, length: ns.length)) else { return (nil, src) }
        let inner = ns.substring(with: m.range(at: 1))
        let body = ns.substring(from: m.range.location + m.range.length)
        return (lines(inner), body)
    }

    /// Words of the person's own writing in a Markdown file.
    static func ownWords(_ text: String) -> Int {
        let body = splitFront(text).body
        var n = 0
        var fence: String?
        for line in lines(body) {
            if let f = first(fenceRE, line), let mark = group(f, 1, line) {
                fence = fence == mark ? nil : (fence ?? mark)
                continue
            }
            if fence != nil || first(headingLine, line) != nil { continue }
            var rest = sub(line, mdImage, " ")
            rest = sub(rest, mdLink, " ")
            rest = sub(rest, autoLink, " ")
            rest = sub(rest, bareURL, " ")
            n += all(wordRE, rest).count
        }
        return n
    }

    /// Only Markdown notes: a .txt file can't hold Stello's details at its top.
    static func isWrittenNote(path: String, text: String) -> Bool {
        first(noteExt, path) != nil && ownWords(text) >= noteWords
    }

    static func noteItemID(_ path: String) -> UUID {
        var b = Array(SHA256.hash(data: Data("stello-note\n\(path)".utf8)).prefix(16))
        b[6] = (b[6] & 0x0f) | 0x80
        b[8] = (b[8] & 0x3f) | 0x80
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }

    private static let dq = re("^\"(?:[^\"\\\\]|\\\\.)*\"$")
    private static let yes = re("^(true|yes)$", ci: true)
    private static let no = re("^(false|no)$", ci: true)
    private static let nul = re("^(null|~)$", ci: true)
    private static let num = re("^-?\\d+(\\.\\d+)?$")

    static func yamlScalar(_ raw: String) -> JSON {
        let s = raw.trimmingCharacters(in: space)
        if first(dq, s) != nil { return FolderWriter.parse(s) ?? .string(String(s.dropFirst().dropLast())) }
        if s.count >= 2, s.hasPrefix("'"), s.hasSuffix("'") {
            return .string(String(s.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'"))
        }
        if first(yes, s) != nil { return .bool(true) }
        if first(no, s) != nil { return .bool(false) }
        if first(nul, s) != nil { return .null }
        if first(num, s) != nil, s.count < 16, let d = Double(s) { return .number(d) }
        return .string(s)
    }

    private static func splitFlow(_ s: String) -> [String] {
        var out: [String] = []
        var cur = ""
        var q: Character?
        for ch in s {
            if let open = q { cur.append(ch); if ch == open { q = nil }; continue }
            if ch == "\"" || ch == "'" { q = ch; cur.append(ch); continue }
            if ch == "," { out.append(cur); cur = ""; continue }
            cur.append(ch)
        }
        if !cur.trimmingCharacters(in: space).isEmpty || !out.isEmpty { out.append(cur) }
        return out.map { $0.trimmingCharacters(in: space) }.filter { !$0.isEmpty }
    }

    private static let listItem = re("^\\s*-\\s+(.*)$")
    private static let mapInList = re("^[A-Za-z0-9_ .-]+:\\s")
    private static let keyValue = re("^([A-Za-z0-9_][A-Za-z0-9_.-]*(?: [A-Za-z0-9_.-]+)*)\\s*:(?:\\s+(.*))?$")
    private static let blockStart = re("^[|>{&*!]")
    private static let flowList = re("^\\[.*\\]$")
    private static let bracket = re("[\\[\\]{}]")
    private static let trailingSpace = re("\\s+$")

    /// Simple YAML front matter (key: value, [a, b] lists, "- a" lists) → ordered details, or
    /// nil when it holds anything more (nested maps, multi-line text): then the file is left alone.
    static func readFront(_ lines: [String]) -> FolderWriter.Obj? {
        var out = FolderWriter.Obj()
        var list: String?
        var items: [String: [JSON]] = [:]
        for raw in lines {
            let line = sub(raw, trailingSpace, "")
            if line.trimmingCharacters(in: space).isEmpty || line.trimmingCharacters(in: .whitespaces).hasPrefix("#") { continue }
            if let m = first(listItem, line), let v = group(m, 1, line) {
                let t = v.trimmingCharacters(in: space)
                guard let key = list, !(t.hasPrefix("[") || t.hasPrefix("{")), first(mapInList, v) == nil else { return nil }
                items[key, default: []].append(yamlScalar(v))
                out[key] = .array(items[key]!)
                continue
            }
            guard let kv = first(keyValue, line), let key = group(kv, 1, line), out[key] == nil else { return nil }
            let v = (group(kv, 2, line) ?? "").trimmingCharacters(in: space)
            list = nil
            if v.isEmpty { out[key] = .array([]); items[key] = []; list = key; continue }
            if first(blockStart, v) != nil { return nil }
            if first(flowList, v) != nil {
                let inner = String(v.dropFirst().dropLast())
                if first(bracket, inner) != nil { return nil }
                out[key] = .array(splitFlow(inner).map(yamlScalar))
                continue
            }
            if v.hasPrefix("[") { return nil }
            out[key] = yamlScalar(v)
        }
        for (k, v) in out.pairs { if case .array(let a) = v, a.isEmpty { out[k] = .null } }
        return out
    }

    private static let stelloKeys: Set<String> = ["id", "url", "kind", "site", "summary", "status", "added", "analyzed",
        "opened", "open_count", "cover", "cover_aspect", "review", "enrichment", "people", "places",
        "sources", "meta", "snippets", "images", "name"]
    private static let noteTagKeys: Set<String> = ["tags", "tag", "keywords"]
    private static let noteDateKeys: Set<String> = ["created", "date", "created_at", "creation date"]
    private static let tagSplit = re("[,\\s]+")

    /// A written note's item: `extra` is the note's own details kept in its header,
    /// `text` its text exactly as written (`body` the item's notes, trailing space trimmed).
    struct NoteItem: Equatable, Sendable {
        var id: UUID
        var slug: String
        var title: String
        var body: String?
        var addedAt: String
        var subjects: [String]
        var text: String
        var extra: FolderWriter.Obj
    }

    /// JS `String(v)` for a front-matter value.
    private static func plain(_ v: JSON) -> String {
        switch v {
        case .string(let s): return s
        case .null: return "null"
        case .array(let a): return a.map { $0 == .null ? "" : plain($0) }.joined(separator: ",")
        default: return FolderWriter.stringify(v)
        }
    }

    /// A written note → its item, or nil when its details can't be kept safely (the file is
    /// then never touched; its links still become items).
    static func noteItem(path: String, text: String, id: UUID, modified: Date?, now: String) -> NoteItem? {
        let (front, body) = splitFront(text)
        guard let fm = front.map(readFront) ?? FolderWriter.Obj() else { return nil }
        var extra = FolderWriter.Obj()
        var tags: [String] = []
        var title: String?
        var added: String?
        for (k, v) in fm.pairs {
            let low = k.lowercased()
            if low == "title", title == nil, v != .null, v.array == nil, v.object == nil { title = squash(plain(v)); continue }
            if noteTagKeys.contains(low) {
                let names: [String]
                if case .array(let a) = v { names = a.map { $0 == .null ? "" : plain($0) } }
                else { names = splitOn(v == .null ? "" : plain(v), tagSplit) }
                addTags(&tags, names.map { $0.hasPrefix("#") ? String($0.dropFirst()) : $0 })
                continue
            }
            if stelloKeys.contains(low) { return nil }
            if noteDateKeys.contains(low), added == nil { added = toISO(v == .null ? "" : plain(v)) }
            extra[k] = v
        }
        let name = String((title.flatMap { $0.isEmpty ? nil : $0 } ?? fileTitle(path) ?? "Note").prefix(300))
        let trimmed = sub(body, trailingSpace, "")
        return NoteItem(id: id, slug: linkSlug(name, id: id), title: name, body: trimmed.isEmpty ? nil : trimmed,
                        addedAt: added ?? modified.map(iso) ?? now,
                        subjects: Array(tags.filter { $0 != "note" }.prefix(maxTags)), text: body, extra: extra)
    }

    private static func splitOn(_ s: String, _ r: NSRegularExpression) -> [String] {
        let ns = s as NSString
        var out: [String] = []
        var last = 0
        for m in r.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out.append(ns.substring(with: NSRange(location: last, length: m.range.location - last)))
            last = m.range.location + m.range.length
        }
        out.append(ns.substring(from: last))
        return out
    }
}
