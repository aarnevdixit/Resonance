//
//  PhraseLibrary.swift
//  Resonance
//
//  Default Talk board phrases (PLAN.pdf Section 13). Kept in code rather than a
//  Phrases.json file so a missing resource can never stop the app from launching.
//  New defaults are added for existing users too (see `addMissingDefaults`), without
//  touching phrases they recorded or added themselves.
//

import Foundation
import SwiftData

enum PhraseLibrary {
    /// Stored category names. "Custom" is shown as "Mine".
    static let categories = ["Needs", "Feelings", "People", "Replies", "Custom"]

    static func displayName(_ category: String) -> String {
        category == "Custom" ? "Mine" : category
    }

    static let defaults: [(category: String, items: [String])] = [
        ("Needs", ["I'm thirsty", "I'm hungry", "Please reposition me", "I need the bathroom",
                   "I'm too hot", "I'm too cold", "Please call the nurse", "I need my medication",
                   "I need suction", "Please adjust my mask", "Please scratch my face", "Please turn the light off",
                   "I want to sit up", "I want to lie down", "Please wipe my mouth", "Can you open the window?"]),
        ("Feelings", ["I love you", "I'm in pain", "I'm tired", "I'm happy", "I'm frustrated",
                      "Thank you for helping me", "I'm scared", "I'm okay", "I'm uncomfortable",
                      "I feel short of breath", "I'm bored", "I'm proud of you"]),
        ("People", ["Please call my family", "Can we video call?", "I want to see my friends",
                    "Please sit with me", "Please talk to me", "I'd like some time alone",
                    "Please read to me", "Can we watch something together?"]),
        ("Replies", ["Yes", "No", "Maybe", "Please wait", "I don't know", "Please say that again",
                     "Not now, later", "That's funny", "I agree", "I don't agree",
                     "Give me a moment to answer", "Please ask me yes or no questions"]),
    ]

    static let icons: [String: String] = [
        "I'm thirsty": "drop.fill", "I'm hungry": "fork.knife", "Please reposition me": "bed.double.fill",
        "I need the bathroom": "toilet.fill", "I'm too hot": "thermometer.sun.fill",
        "I'm too cold": "thermometer.snowflake", "Please call the nurse": "cross.case.fill",
        "I need my medication": "pills.fill", "I need suction": "wind",
        "Please adjust my mask": "lungs.fill", "Please scratch my face": "hand.point.up.left.fill",
        "Please turn the light off": "lightbulb.slash.fill", "I want to sit up": "figure.seated.side",
        "I want to lie down": "bed.double.fill", "Please wipe my mouth": "mouth.fill",
        "Can you open the window?": "window.casement",
        "I love you": "heart.fill", "I'm in pain": "bandage.fill",
        "I'm tired": "moon.zzz.fill", "I'm happy": "face.smiling", "I'm frustrated": "cloud.bolt.fill",
        "Thank you for helping me": "hands.sparkles.fill", "I'm scared": "exclamationmark.bubble.fill",
        "I'm okay": "hand.thumbsup.fill", "I'm uncomfortable": "figure.wave",
        "I feel short of breath": "lungs.fill", "I'm bored": "hourglass", "I'm proud of you": "star.fill",
        "Please call my family": "phone.fill", "Can we video call?": "video.fill",
        "I want to see my friends": "person.3.fill", "Please sit with me": "chair.fill",
        "Please talk to me": "bubble.left.and.bubble.right.fill", "I'd like some time alone": "person.fill",
        "Please read to me": "book.fill", "Can we watch something together?": "tv.fill",
        "Yes": "checkmark.circle.fill", "No": "xmark.circle.fill",
        "Maybe": "questionmark.circle.fill", "Please wait": "hand.raised.fill",
        "I don't know": "ellipsis.circle.fill", "Please say that again": "arrow.counterclockwise",
        "Not now, later": "clock.fill", "That's funny": "face.smiling.inverse", "I agree": "hand.thumbsup.fill",
        "I don't agree": "hand.thumbsdown.fill", "Give me a moment to answer": "timer",
        "Please ask me yes or no questions": "checkmark.square.fill",
    ]

    static func icon(for text: String) -> String {
        icons[text] ?? "text.bubble.fill"
    }

    /// Adds the default phrases the first time the app runs.
    static func seedIfNeeded(in context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<Phrase>())) ?? 0
        guard count == 0 else {
            addMissingDefaults(in: context)
            return
        }
        for group in defaults {
            for (i, text) in group.items.enumerated() {
                context.insert(Phrase(text: text, category: group.category, order: i))
            }
        }
        try? context.save()
        UserDefaults.standard.set(libraryVersion, forKey: versionKey)
    }

    static let libraryVersion = 2
    private static let versionKey = "phraseLibraryVersion"

    /// Adds phrases introduced in a newer version, after the person's existing ones.
    static func addMissingDefaults(in context: ModelContext) {
        guard UserDefaults.standard.integer(forKey: versionKey) < libraryVersion else { return }
        let existing = (try? context.fetch(FetchDescriptor<Phrase>())) ?? []
        let texts = Set(existing.map(\.text))
        for group in defaults {
            var order = (existing.filter { $0.category == group.category }.map(\.order).max() ?? -1) + 1
            for text in group.items where !texts.contains(text) {
                context.insert(Phrase(text: text, category: group.category, order: order))
                order += 1
            }
        }
        try? context.save()
        UserDefaults.standard.set(libraryVersion, forKey: versionKey)
    }
}
