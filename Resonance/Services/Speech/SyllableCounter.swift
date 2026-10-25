//
//  SyllableCounter.swift
//  Resonance
//
//  Estimates the number of syllables in an English word (PLAN.pdf Section 9).
//  Rule of thumb: count groups of vowels, then adjust for silent endings.
//  It is not perfect, but it is consistent from week to week, which is what matters for trends.
//

import Foundation

enum SyllableCounter {
    private static let vowels: Set<Character> = ["a", "e", "i", "o", "u", "y"]

    static func count(_ word: String) -> Int {
        let letters = word.lowercased().filter { $0.isLetter }
        guard !letters.isEmpty else { return 0 }
        let chars = Array(letters)

        // 1. Count groups of consecutive vowels.
        var groups = 0
        var previousWasVowel = false
        for c in chars {
            let isVowel = vowels.contains(c)
            if isVowel && !previousWasVowel { groups += 1 }
            previousWasVowel = isVowel
        }

        let n = chars.count
        // 2. Silent final "e" ("bake", "more"), but not "-le" after a consonant ("table", "little").
        if n >= 3, chars[n - 1] == "e", !vowels.contains(chars[n - 2]) {
            let isConsonantLe = chars[n - 2] == "l" && !vowels.contains(chars[n - 3])
            if !isConsonantLe { groups -= 1 }
        }
        // 3. Silent "-ed" ("walked", "played"), except after t or d ("wanted", "needed").
        if n >= 3, chars[n - 2] == "e", chars[n - 1] == "d" {
            let before = chars[n - 3]
            if before != "t" && before != "d" && !vowels.contains(before) { groups -= 1 }
        }
        // 4. "-es" after most consonants is silent too ("makes"), but not after s, x, z, ch, sh.
        if n >= 4, chars[n - 2] == "e", chars[n - 1] == "s" {
            let before = chars[n - 3]
            let sibilant = "sxz".contains(before) || (chars[n - 3] == "h" && "cs".contains(chars[n - 4]))
            if !sibilant && !vowels.contains(before) { groups -= 1 }
        }

        return max(1, groups)
    }

    static func count(words: [String]) -> Int {
        words.reduce(0) { $0 + count($1) }
    }
}
