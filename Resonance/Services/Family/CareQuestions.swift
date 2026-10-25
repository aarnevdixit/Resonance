//
//  CareQuestions.swift
//  Resonance
//
//  Questions the person wants to ask at their next clinic visit. Speaking takes effort with
//  ALS, so questions can be written (or saved from the Talk board) whenever they come up,
//  then shown on the Care Report or read out at the visit. Stored on this iPhone only.
//  The list logic is plain Swift, unit tested in CareQuestionsTests.
//

import Foundation
import SwiftData

@Model
final class CareQuestion {
    var text: String
    var createdAt: Date = Date()
    var asked: Bool = false

    init(text: String, createdAt: Date = Date()) {
        self.text = text
        self.createdAt = createdAt
    }
}

enum CareQuestions {
    static let maxLength = 240
    /// How many open questions fit on the one-page Care Report.
    static let reportLimit = 5

    /// Tidies typed text: trims, collapses spaces and line breaks, limits the length.
    /// Returns nil when nothing is left.
    static func clean(_ text: String) -> String? {
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        guard !words.isEmpty else { return nil }
        let joined = words.joined(separator: " ")
        if joined.count <= maxLength { return joined }
        return String(joined.prefix(maxLength - 1)) + "…"
    }

    /// Adds a question mark when the text has no ending punctuation ("Can I drive" → "Can I drive?").
    static func asQuestion(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let last = trimmed.last, !".?!…".contains(last) else { return trimmed }
        return trimmed + "?"
    }

    /// True when the same question (ignoring case and end punctuation) is already on the list.
    static func isDuplicate(_ text: String, of existing: [String]) -> Bool {
        let key = normalized(text)
        return existing.contains { normalized($0) == key }
    }

    /// Questions not asked yet, oldest first (the order they came up), for the report.
    static func open(_ items: [(text: String, createdAt: Date, asked: Bool)]) -> [String] {
        items.filter { !$0.asked }
            .sorted { $0.createdAt < $1.createdAt }
            .map(\.text)
    }

    /// One block of text to read out or share: "Questions for my care team:\n1. …".
    static func shareText(_ open: [String]) -> String? {
        guard !open.isEmpty else { return nil }
        let lines = open.enumerated().map { "\($0.offset + 1). \($0.element)" }
        return (["Questions for my care team:"] + lines).joined(separator: "\n")
    }

    private static func normalized(_ text: String) -> String {
        (clean(text) ?? "")
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "?.! "))
    }
}
