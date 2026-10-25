//
//  Feeling.swift
//  Resonance
//
//  Saying how you feel with one choice: a face, and optionally "a little" or "very".
//  "I feel very sad." Each choice is also kept (FeelingEntry) so family can see how the
//  week has felt, in the daily update and on the Family tab.
//  Plain Swift, unit tested in FeelingTests.
//

import Foundation
import SwiftData

enum Feeling: String, CaseIterable, Identifiable {
    case happy, okay, loved, grateful, tired, sad, lonely, worried, scared, frustrated, angry, bored

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .happy: return "😊"
        case .okay: return "🙂"
        case .loved: return "🥰"
        case .grateful: return "🙏"
        case .tired: return "😴"
        case .sad: return "😢"
        case .lonely: return "🥺"
        case .worried: return "😟"
        case .scared: return "😨"
        case .frustrated: return "😤"
        case .angry: return "😠"
        case .bored: return "😐"
        }
    }

    var label: String { rawValue.capitalized }

    /// Pleasant feelings are shown first and counted as good moments in the weekly summary.
    var isPleasant: Bool {
        switch self {
        case .happy, .okay, .loved, .grateful: return true
        default: return false
        }
    }

    /// What a helper might do next, said after the feeling when it helps.
    var followUp: String? {
        switch self {
        case .sad, .lonely: return "Please sit with me."
        case .worried, .scared: return "Please stay with me."
        case .bored: return "Can we do something together?"
        default: return nil
        }
    }

    /// The 9 faces on the Talk board (a 3 x 3 grid).
    static let board: [Feeling] = [.happy, .okay, .loved, .tired, .sad, .lonely, .worried, .scared, .frustrated]
}

enum FeelingIntensity: Int, CaseIterable {
    case aLittle = 1, plain = 2, very = 3

    var label: String {
        switch self {
        case .aLittle: return "A little"
        case .plain: return "Just say it"
        case .very: return "Very"
        }
    }
}

enum FeelingPhrase {
    /// "I feel sad." / "I feel a little tired." / "I feel very scared." / "I'm grateful."
    static func sentence(_ feeling: Feeling, intensity: FeelingIntensity = .plain) -> String {
        let word: String
        switch intensity {
        case .aLittle: word = "a little \(feeling.rawValue)"
        case .plain: word = feeling.rawValue
        case .very: word = "very \(feeling.rawValue)"
        }
        // "I feel loved" and "I feel grateful" read naturally; "I'm okay" reads better than "I feel okay".
        if feeling == .okay { return intensity == .plain ? "I'm okay." : "I feel \(word)." }
        return "I feel \(word)."
    }

    /// The sentence plus a helpful follow-up, when there is one.
    static func full(_ feeling: Feeling, intensity: FeelingIntensity = .plain) -> String {
        [sentence(feeling, intensity: intensity), feeling.followUp].compactMap { $0 }.joined(separator: " ")
    }
}

/// A feeling chosen on the Talk board.
@Model
final class FeelingEntry {
    var date: Date
    var feeling: String      // Feeling.rawValue
    var intensity: Int       // FeelingIntensity.rawValue

    init(feeling: Feeling, intensity: FeelingIntensity, date: Date = Date()) {
        self.date = date
        self.feeling = feeling.rawValue
        self.intensity = intensity.rawValue
    }
}

/// How the last few days have felt, for family.
enum FeelingSummary {
    struct Count: Equatable {
        var feeling: Feeling
        var times: Int
    }

    /// Feelings in the last `days` days, most frequent first (ties: most recent first).
    static func recent(_ entries: [(date: Date, feeling: String)], now: Date, days: Double = 7) -> [Count] {
        let cutoff = now.addingTimeInterval(-days * 86_400)
        var counts: [Feeling: (times: Int, last: Date)] = [:]
        for entry in entries where entry.date >= cutoff && entry.date <= now {
            guard let feeling = Feeling(rawValue: entry.feeling) else { continue }
            let current = counts[feeling] ?? (0, .distantPast)
            counts[feeling] = (current.times + 1, max(current.last, entry.date))
        }
        return counts
            .sorted { $0.value.times != $1.value.times ? $0.value.times > $1.value.times : $0.value.last > $1.value.last }
            .map { Count(feeling: $0.key, times: $0.value.times) }
    }

    /// "Feelings this week: tired (3), happy (2), sad (1)" or nil when none were shared.
    static func line(_ counts: [Count], limit: Int = 4) -> String? {
        guard !counts.isEmpty else { return nil }
        let parts = counts.prefix(limit).map { "\($0.feeling.rawValue) (\($0.times))" }
        return "Feelings shared this week: \(parts.joined(separator: ", "))"
    }
}
