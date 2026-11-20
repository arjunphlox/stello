import Foundation
import CoreGraphics
import SwiftUI

/// Layer 2: what you add yourself (web `L2`). Links keep the server's kind names
/// (`maybe` is the web's "related": a maybe-related pair you kept).
nonisolated enum L2Kind: String, CaseIterable, Sendable {
    case influence, contrast, partOf = "part_of", question, maybe

    var label: String {
        switch self {
        case .influence: "Influence"
        case .contrast: "Contrast"
        case .partOf: "Part of"
        case .question: "Question"
        case .maybe: "Accepted"
        }
    }
    /// The card menu entry that starts a link of this kind.
    var action: String {
        switch self {
        case .influence: "Inspired…"
        case .contrast: "Vs…"
        case .partOf: "Part of…"
        case .question: "Ask…"
        case .maybe: "Link…"
        }
    }
    /// What to pick next, shown while connecting.
    var hint: String {
        switch self {
        case .influence: "Choose the item it inspired"
        case .contrast: "Choose the item it contrasts with"
        case .partOf: "Choose a set, or tap empty canvas to make one"
        case .question: "Choose a question, or tap empty canvas to ask one"
        case .maybe: "Choose the item it relates to"
        }
    }
    var hex: String {
        switch self {
        case .influence: "#d6336c"
        case .contrast: "#e8890c"
        case .partOf: "#5c6b84"
        case .question: "#d9a400"
        case .maybe: "#868e96"
        }
    }
    var dash: [CGFloat] {
        switch self {
        case .contrast: [3, 4]
        case .maybe: [2, 4]
        default: []
        }
    }
    /// Arrow heads: influence points both ways, part of / question at the end.
    var arrowStart: Bool { self == .influence }
    var arrowEnd: Bool { self == .influence || self == .partOf || self == .question }
    /// The note kind made when you tap empty canvas while connecting.
    var noteOnEmpty: String? {
        switch self {
        case .partOf: "set"
        case .question: "question"
        default: nil
        }
    }
    /// Influence and contrast ask for a short label once linked.
    var asksLabel: Bool { self == .influence || self == .contrast }
    var labelPrompt: String { self == .influence ? "What carried over?" : "What’s the contrast?" }

    /// The line label, as the web writes it.
    func text(_ label: String?) -> String? {
        let l = (label ?? "").trimmingCharacters(in: .whitespaces)
        switch self {
        case .influence: return l.isEmpty ? "inspired" : "inspired: \(l)"
        case .contrast: return l.isEmpty ? "vs" : "vs · \(l)"
        case .partOf: return "part of"
        case .maybe: return l.isEmpty ? nil : "maybe: \(l)"
        case .question: return nil
        }
    }
}

/// Use / Rejected marks on a card (web `setMark`). `Card.note` holds the reason.
nonisolated enum CanvasMark: String, Sendable {
    case use, rejected
    var label: String { self == .use ? "Use" : "Rejected" }
    var hex: String { self == .use ? "#2b8a3e" : "#e03131" }
}

/// Free notes on the canvas (web `renderNotes`).
nonisolated enum CanvasNoteKind: String, CaseIterable, Sendable {
    case question, note, set, region

    var label: String {
        switch self {
        case .question: "Question"
        case .note: "Note"
        case .set: "Set"
        case .region: "Region note"
        }
    }
    var placeholder: String {
        switch self {
        case .question: "Ask something about these saves"
        case .set: "Name this set"
        default: "Write a note"
        }
    }
    /// World size, for lines and hit tests (web measures the note; these match its CSS).
    var width: CGFloat { self == .note || self == .region ? 200 : 220 }
    static let height: CGFloat = 80
}

/// Picking the second end of a link, or the spot on an image for a region note.
nonisolated enum CanvasPick: Equatable, Sendable {
    case link(from: String, kind: L2Kind)
    case region(slug: String)

    var hint: String {
        switch self {
        case .link(_, let kind): kind.hint
        case .region: "Tap the spot on the image for this note"
        }
    }
}

extension L2Kind {
    var color: Color { Color(hex: hex) }
}

extension CanvasMark {
    var color: Color { Color(hex: hex) }
}
