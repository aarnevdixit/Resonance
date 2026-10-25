//
//  Phrase.swift
//  Resonance
//
//  A Talk board phrase (PLAN.pdf Sections 8 and 13).
//

import Foundation
import SwiftData

@Model
final class Phrase {
    var text: String
    var category: String    // "Needs", "Feelings", "People", "Replies", "Custom"
    var order: Int
    var clip: BankedClip?   // if set, play the user's own recording instead of a synthesized voice
    var useCount: Int = 0

    init(text: String, category: String, order: Int) {
        self.text = text
        self.category = category
        self.order = order
    }
}
