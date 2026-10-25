//
//  PainPhrase.swift
//  Resonance
//
//  Turns "where it hurts" and "how bad" into one clear sentence to speak and send:
//  "I'm in pain. My lower back hurts. It's a 7 out of 10, bad."
//  Plain Swift, unit tested in PainPhraseTests.
//

import Foundation

enum PainArea: String, CaseIterable, Identifiable {
    case head, eyes, mouth, throat, neck, chest, stomach, back, shoulders, arms, hands, hips, legs, feet, allOver

    var id: String { rawValue }

    /// Name on the button.
    var label: String {
        switch self {
        case .head: return "Head"
        case .eyes: return "Eyes"
        case .mouth: return "Mouth"
        case .throat: return "Throat"
        case .neck: return "Neck"
        case .chest: return "Chest"
        case .stomach: return "Stomach"
        case .back: return "Back"
        case .shoulders: return "Shoulders"
        case .arms: return "Arms"
        case .hands: return "Hands"
        case .hips: return "Hips"
        case .legs: return "Legs"
        case .feet: return "Feet"
        case .allOver: return "All over"
        }
    }

    var icon: String {
        switch self {
        case .head: return "brain.head.profile"
        case .eyes: return "eye.fill"
        case .mouth: return "mouth.fill"
        case .throat: return "waveform"            // voice and swallowing
        case .neck: return "person.bust.fill"
        case .chest: return "lungs.fill"
        case .stomach: return "fork.knife"
        case .back: return "figure.stand"
        case .shoulders, .arms: return "figure.arms.open"
        case .hands: return "hand.raised.fill"
        case .hips, .legs: return "figure.walk"
        case .feet: return "shoeprints.fill"
        case .allOver: return "figure.wave"
        }
    }

    /// The sentence part: "My back hurts." / "My feet hurt." / "I hurt all over."
    var sentence: String {
        switch self {
        case .allOver: return "I hurt all over."
        case .eyes, .shoulders, .arms, .hands, .hips, .legs, .feet:
            return "My \(rawValue) hurt."
        default:
            return "My \(label.lowercased()) hurts."
        }
    }

    /// The areas shown on the board (12 fit as a 3 x 4 grid).
    static let board: [PainArea] = [.head, .mouth, .throat, .neck, .chest, .stomach,
                                    .back, .arms, .hands, .legs, .feet, .allOver]
}

enum PainPhrase {
    static let opening = "I'm in pain."

    /// Plain word for a 0-10 level.
    static func word(for level: Int) -> String {
        switch level {
        case ...0: return "no pain"
        case 1...3: return "mild"
        case 4...5: return "moderate"
        case 6...7: return "bad"
        case 8...9: return "very bad"
        default: return "the worst"
        }
    }

    /// "It's a 7 out of 10, bad."
    static func levelSentence(_ level: Int) -> String {
        let clamped = min(max(level, 0), 10)
        let article = clamped == 8 ? "an" : "a"
        return "It's \(article) \(clamped) out of 10, \(word(for: clamped))."
    }

    /// The whole message. Either part can be missing.
    static func sentence(area: PainArea?, level: Int?) -> String {
        var parts = [opening]
        if let area { parts.append(area.sentence) }
        if let level { parts.append(levelSentence(level)) }
        return parts.joined(separator: " ")
    }

    /// The levels offered on the board: 2, 4, 6, 8, 10 (fewer, bigger buttons).
    static let boardLevels = [2, 4, 6, 8, 10]
}
