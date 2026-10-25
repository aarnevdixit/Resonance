//
//  TextAlignerTests.swift
//  ResonanceTests
//
//  Tests for TextAligner, SyllableCounter and ReadingAnalyzer (task T06).
//

import Testing
import Foundation
@testable import Resonance

struct TextAlignerTests {

    @Test func identicalTextIs100Percent() {
        let r = TextAligner.align(reference: "The air was cool.", hypothesis: "the air was cool")
        #expect(r.intelligibility == 100)
        #expect(r.missedWords.isEmpty)
    }

    @Test func oneDroppedWordOutOfTenIs90Percent() {
        let reference = "one two three four five six seven eight nine ten"
        let hypothesis = "one two three four six seven eight nine ten"
        let r = TextAligner.align(reference: reference, hypothesis: hypothesis)
        #expect(r.intelligibility == 90)
        #expect(r.missedWords == ["five"])
    }

    @Test func substitutionAndInsertionAreHandled() {
        let r = TextAligner.align(reference: "we bought fresh bread", hypothesis: "we brought fresh fresh bread")
        #expect(r.matches == 3)              // "bought" was misheard as "brought"
        #expect(r.missedWords == ["bought"])
    }

    @Test func punctuationAndApostrophesAreIgnored() {
        #expect(TextAligner.normalize("I'm here, okay?") == ["im", "here", "okay"])
    }

    @Test func emptyHypothesisIsZero() {
        let r = TextAligner.align(reference: "hello there", hypothesis: "")
        #expect(r.intelligibility == 0)
    }

    @Test(arguments: [
        ("honey", 2), ("walked", 1), ("the", 1), ("table", 2), ("peaches", 2),
        ("cinnamon", 3), ("wanted", 2), ("saturday", 3), ("puppy", 2),
    ])
    func syllableCounts(word: String, expected: Int) {
        #expect(SyllableCounter.count(word) == expected)
    }

    @Test func readingMetricsFromSegments() throws {
        // 4 words over 2 seconds with one 0.5 s pause.
        let segments = [
            WordSegment(word: "the", start: 0.0, duration: 0.3),
            WordSegment(word: "air", start: 0.3, duration: 0.3),
            WordSegment(word: "was", start: 1.1, duration: 0.3),   // 0.5 s gap before this word
            WordSegment(word: "cool", start: 1.5, duration: 0.5),
        ]
        let r = ReadingAnalyzer.analyze(segments: segments, passage: "The air was cool.")
        let wpm = try #require(r.wpm)
        #expect(abs(wpm - 120) < 0.01)                  // 4 words / 2 s * 60
        let pause = try #require(r.pauseRatio)
        #expect(abs(pause - 25) < 0.01)                 // 0.5 s of 2 s
        #expect(r.intelligibility == 100)
        #expect(r.flags.isEmpty)
    }

    @Test func noSegmentsIsFlagged() {
        let r = ReadingAnalyzer.analyze(segments: [])
        #expect(r.wpm == nil)
        #expect(r.flags.contains(QualityFlag.noSpeech))
        #expect(r.metrics.isEmpty)   // nothing saved, so Trends never shows a fake 0%
    }
}
