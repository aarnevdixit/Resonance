//
//  KeyboardPanel.swift
//  Resonance
//
//  Large alphabetical keyboard with word predictions (PLAN.pdf Section 13).
//  Alphabetical order is easier than QWERTY when choosing with the head pointer.
//  Every key reports its frame, so it works by touch AND by dwell.
//

import SwiftUI
import UIKit

struct KeyboardPanel: View {
    let text: String
    let predictions: [String]
    /// Whether a key is highlighted (head pointer or switch scanning), and its progress ring.
    let highlight: (String) -> HighlightState
    let activate: (String) -> Void

    static let rows: [[String]] = [
        ["A", "B", "C", "D", "E", "F", "G"],
        ["H", "I", "J", "K", "L", "M", "N"],
        ["O", "P", "Q", "R", "S", "T", "U"],
        ["V", "W", "X", "Y", "Z", "'", "?"],
    ]

    var body: some View {
        VStack(spacing: 8) {
            Text(text.isEmpty ? "Type a message…" : text)
                .font(.title3)
                .foregroundStyle(text.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, minHeight: AppTheme.minTapSize, alignment: .leading)
                .padding(.horizontal, 14)
                .surfaceStyle(radius: AppTheme.controlRadius)
                .accessibilityLabel(text.isEmpty ? "Empty message" : "Message: \(text)")

            HStack(spacing: 6) {
                ForEach(predictions, id: \.self) { word in
                    key("pred.\(word)", label: word, color: AppTheme.violetSoft, textColor: AppTheme.accent)
                }
                if predictions.isEmpty {
                    Text("Word suggestions appear here")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            // Fixed height so the keys never jump when suggestions appear (important for head control).
            .frame(height: 52)

            ForEach(Self.rows, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(row, id: \.self) { letter in
                        key("key.\(letter)", label: letter, color: AppTheme.accent)
                    }
                }
            }

            HStack(spacing: 6) {
                key("key.space", label: "Space", color: AppTheme.violetSoft, textColor: AppTheme.accent)
                    .frame(maxWidth: .infinity)
                key("key.delete", label: "Delete", systemImage: "delete.left.fill",
                    color: AppTheme.violetSoft, textColor: AppTheme.accent)
                    .frame(width: 96)
                key("key.clear", label: "Clear", color: AppTheme.violetSoft, textColor: AppTheme.accent)
                    .frame(width: 84)
            }
            HStack(spacing: 6) {
                key("key.save", label: "Save", systemImage: "plus.square.on.square",
                    color: AppTheme.violetDeep)
                key("key.ask", label: "Ask later", systemImage: "questionmark.bubble.fill",
                    color: AppTheme.amber)
                key("key.speak", label: "Speak", systemImage: "speaker.wave.2.fill", color: AppTheme.mint)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func key(_ id: String, label: String, systemImage: String? = nil,
                     color: Color, textColor: Color = .white) -> some View {
        Button { activate(id) } label: {
            Group {
                if let systemImage {
                    Label(label, systemImage: systemImage)
                } else {
                    Text(label)
                }
            }
            .font(.system(.title3, design: .rounded).weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(textColor)
            // Keys grow to fill the space they have (up to 60 pt) and shrink on small iPhones.
            .frame(maxWidth: .infinity, minHeight: 40, maxHeight: AppTheme.minTapSize)
            .background(color, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .highlight(highlight(id))
        }
        .buttonStyle(PressableStyle())
        .reportFrame(id)
        .accessibilityLabel(accessibilityName(id, label))
    }

    /// The rows switch scanning steps through, top to bottom.
    static func scanGroups(predictions: [String]) -> [[String]] {
        var groups: [[String]] = []
        if !predictions.isEmpty { groups.append(predictions.map { "pred.\($0)" }) }
        groups.append(["key.speak", "key.save", "key.ask"])
        groups += rows.map { $0.map { "key.\($0)" } }
        groups.append(["key.space", "key.delete", "key.clear"])
        return groups
    }

    private func accessibilityName(_ id: String, _ label: String) -> String {
        switch id {
        case "key.delete": return "Delete"
        case "key.space": return "Space"
        case "key.ask": return "Save as a question for my care team"
        case "key.save": return "Save as my phrase"
        default: return label
        }
    }
}

/// Word completions from the system dictionary.
enum Predictions {
    private static let checker = UITextChecker()

    /// Up to three completions for the word being typed.
    static func complete(_ text: String) -> [String] {
        guard let partial = text.split(separator: " ", omittingEmptySubsequences: false).last,
              partial.count >= 1 else { return [] }
        let nsText = text as NSString
        let range = NSRange(location: nsText.length - (String(partial) as NSString).length,
                            length: (String(partial) as NSString).length)
        let words = checker.completions(forPartialWordRange: range, in: text, language: "en_US") ?? []
        return Array(words.prefix(3))
    }

    /// Replaces the partial last word with the chosen word and adds a space.
    static func apply(_ word: String, to text: String) -> String {
        var parts = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        if parts.isEmpty { return word + " " }
        parts[parts.count - 1] = word
        return parts.joined(separator: " ") + " "
    }
}
