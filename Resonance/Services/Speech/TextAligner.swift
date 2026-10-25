//
//  TextAligner.swift
//  Resonance
//
//  Compares what the speech recognizer heard with the reading passage, word by word
//  (PLAN.pdf Section 9, "Word clarity"). Uses word-level edit distance (Levenshtein):
//  the fewest word insertions, deletions and substitutions that turn one into the other.
//
//  Word clarity = matched passage words / all passage words x 100.
//  This is an automatic estimate of how understandable speech is, not a clinical score.
//

import Foundation

struct AlignmentResult: Equatable {
    var matches: Int
    var referenceCount: Int
    var missedWords: [String]          // passage words the recognizer did not hear exactly

    var intelligibility: Double {
        referenceCount == 0 ? 0 : Double(matches) / Double(referenceCount) * 100
    }
}

enum TextAligner {

    /// Lowercase, remove punctuation (apostrophes too, so "I'm" -> "im"), split into words.
    static func normalize(_ text: String) -> [String] {
        let cleaned = text.lowercased().unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) { return Character(scalar) }
            if scalar == "'" || scalar == "\u{2019}" { return "\u{0}" }   // drop apostrophes
            return " "
        }
        let joined = String(cleaned).replacingOccurrences(of: "\u{0}", with: "")
        return joined.split(whereSeparator: { $0 == " " || $0.isNewline }).map(String.init)
    }

    static func align(reference: String, hypothesis: String) -> AlignmentResult {
        align(referenceWords: normalize(reference), hypothesisWords: normalize(hypothesis))
    }

    static func align(referenceWords ref: [String], hypothesisWords hyp: [String]) -> AlignmentResult {
        let n = ref.count, m = hyp.count
        if n == 0 { return AlignmentResult(matches: 0, referenceCount: 0, missedWords: []) }

        // dp[i][j] = edits to turn ref[0..<i] into hyp[0..<j]
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 0...n { dp[i][0] = i }
        for j in 0...m { dp[0][j] = j }
        if n > 0 && m > 0 {
            for i in 1...n {
                for j in 1...m {
                    let substitution = dp[i - 1][j - 1] + (ref[i - 1] == hyp[j - 1] ? 0 : 1)
                    let deletion = dp[i - 1][j] + 1      // passage word missed
                    let insertion = dp[i][j - 1] + 1     // extra word heard
                    dp[i][j] = min(substitution, deletion, insertion)
                }
            }
        }

        // Backtrack to find which passage words were matched exactly.
        var i = n, j = m
        var matched = Set<Int>()
        while i > 0 || j > 0 {
            if i > 0 && j > 0 {
                let same = ref[i - 1] == hyp[j - 1]
                if dp[i][j] == dp[i - 1][j - 1] + (same ? 0 : 1) {
                    if same { matched.insert(i - 1) }
                    i -= 1; j -= 1
                    continue
                }
            }
            if i > 0 && dp[i][j] == dp[i - 1][j] + 1 {
                i -= 1
            } else {
                j -= 1
            }
        }

        let missed = ref.indices.filter { !matched.contains($0) }.map { ref[$0] }
        return AlignmentResult(matches: matched.count, referenceCount: n, missedWords: missed)
    }
}
