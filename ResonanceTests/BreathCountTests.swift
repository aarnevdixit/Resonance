//
//  BreathCountTests.swift
//  ResonanceTests
//
//  The breath test's number reading and breath-length measurement.
//

import Testing
import Foundation
@testable import Resonance

struct BreathCountTests {

    @Test func digitsCount() {
        #expect(BreathCountAnalyzer.count(in: "1 2 3 4 5 6 7 8 9 10 11 12") == 12)
    }

    @Test func wordsAndCompoundNumbers() {
        #expect(BreathCountAnalyzer.numbers(in: "nineteen twenty twenty-one twenty two") == [19, 20, 21, 22])
        #expect(BreathCountAnalyzer.count(in: "one two three four five") == 5)
    }

    @Test func toleratesOneMissedNumber() {
        // The recognizer dropped "4".
        #expect(BreathCountAnalyzer.count(in: "1 2 3 5 6 7") == 7)
    }

    @Test func picksTheLongestUpwardRun() {
        // A restart after a new breath: the longest run wins.
        #expect(BreathCountAnalyzer.count(in: "1 2 3 4 5 6 7 8 1 2 3") == 8)
    }

    @Test func noNumbersMeansNoCount() {
        #expect(BreathCountAnalyzer.count(in: "hello there") == nil)
        #expect(BreathCountAnalyzer.count(in: "7") == nil)
    }

    private func tone(_ seconds: Double, amplitude: Float = 0.3) -> [Float] {
        let n = Int(seconds * DSP.sampleRate)
        return (0..<n).map { amplitude * Float(sin(2 * Double.pi * 180 * Double($0) / DSP.sampleRate)) }
    }
    private func silence(_ seconds: Double) -> [Float] {
        [Float](repeating: 0, count: Int(seconds * DSP.sampleRate))
    }

    @Test func shortGapsBetweenNumbersStayOneBreath() {
        // Six 0.4 s "numbers" with 0.2 s gaps: one breath of about 3.4 s.
        var s = silence(0.5)
        for _ in 0..<6 { s += tone(0.4) + silence(0.2) }
        s += silence(1)
        let seconds = BreathCountAnalyzer.breathSeconds(s)
        #expect(seconds > 3.0 && seconds < 3.8)
    }

    @Test func aLongPauseSplitsTheBreath() {
        let s = silence(0.5) + tone(2) + silence(1.5) + tone(1) + silence(0.5)
        let seconds = BreathCountAnalyzer.breathSeconds(s)
        #expect(seconds > 1.8 && seconds < 2.3)
    }

    @Test func silenceSavesNothing() {
        let r = BreathCountAnalyzer.analyze(transcript: "1 2 3", samples: silence(3))
        #expect(r.metrics.isEmpty)
        #expect(r.flags.contains(QualityFlag.noSpeech))
    }
}
