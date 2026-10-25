//
//  FunctionCheck.swift
//  Resonance
//
//  One Daily Function Check (PLAN.pdf Sections 8 and 11).
//  Eight answers from 0 (unable) to 4 (normal), so the total is 0 to 32.
//

import Foundation
import SwiftData

@Model
final class FunctionCheck {
    var date: Date
    var answers: [Int]      // 8 answers, each 0...4 (4 = normal)
    var mood: Int           // 1...5
    var note: String?
    var isDemo: Bool = false

    /// Total score, 0...32. Computed, not stored.
    var total: Int { answers.reduce(0, +) }

    init(date: Date, answers: [Int], mood: Int) {
        self.date = date
        self.answers = answers
        self.mood = mood
    }
}
