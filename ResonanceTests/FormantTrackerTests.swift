//
//  FormantTrackerTests.swift
//  ResonanceTests
//
//  Checks the formant tracker against the Python reference and against a synthetic
//  vowel whose formants are known.
//

import Testing
import Foundation
@testable import Resonance

struct FormantTrackerTests {

    /// Python reference for the synthetic "eee" below (Scripts/ml/formants.py) -> (0.355, 2.29).
    @Test func matchesPythonReference() throws {
        let a = try #require(VoiceFeatures.analyze(Self.syntheticEee()))
        let (f1, f2) = FormantTracker.formants(signal: a.signal, frameStarts: a.frameStarts)
        let f1v = try #require(f1), f2v = try #require(f2)
        #expect(abs(f1v - 0.355) <= 0.006)      // one 5 Hz grid step of slack
        #expect(abs(f2v - 2.29) <= 0.006)
    }

    /// A 120 Hz pulse train through two resonators at 300 Hz and 2300 Hz (like "eee").
    static func syntheticEee(seconds: Double = 2.0) -> [Float] {
        syntheticVowel(f1: 300, f2: 2300, seconds: seconds)
    }

    /// A 120 Hz pulse train through two resonators (bandwidths 80 and 120 Hz).
    static func syntheticVowel(f1 formant1: Double, f2 formant2: Double, seconds: Double = 2.0) -> [Float] {
        let sr = 44_100.0
        let n = Int(sr * seconds)
        var x = [Double](repeating: 0, count: n)
        let period = Int(sr / 120)
        for i in stride(from: 0, to: n, by: period) { x[i] = 1 }
        for (f, bw) in [(formant1, 80.0), (formant2, 120.0)] {
            let r = exp(-Double.pi * bw / sr)
            let c = 2 * r * cos(2 * Double.pi * f / sr)
            var y1 = 0.0, y2 = 0.0
            for i in 0..<n {
                let y = x[i] + c * y1 - r * r * y2
                y2 = y1; y1 = y
                x[i] = y
            }
        }
        let peak = x.map(abs).max() ?? 1
        return x.map { Float(0.5 * $0 / peak) }
    }

    @Test func findsKnownFormants() throws {
        let a = try #require(VoiceFeatures.analyze(Self.syntheticEee()))
        let (f1, f2) = FormantTracker.formants(signal: a.signal, frameStarts: a.frameStarts)
        let f1v = try #require(f1), f2v = try #require(f2)
        #expect(abs(f1v - 0.30) < 0.08)
        #expect(abs(f2v - 2.30) < 0.15)
    }

    @Test func levinsonOfWhiteNoiseIsFlat() throws {
        // Autocorrelation of white noise: r[0] = 1, everything else 0 -> all coefficients 0.
        var r = [Double](repeating: 0, count: FormantTracker.order + 1)
        r[0] = 1
        let a = try #require(FormantTracker.levinson(r))
        #expect(a[0] == 1)
        #expect(a.dropFirst().allSatisfy { abs($0) < 1e-12 })
    }

    @Test func twoVowelInputsAreNamed() throws {
        let eee = try #require(VowelAnalysis.analyze(Self.syntheticEee()))
        let ahh = try #require(VowelAnalysis.analyze(Self.syntheticVowel(f1: 700, f2: 1200)))
        let d = SpeechChangeInput.named(ahh: ahh, eee: eee)
        #expect(d["jitter_a"] != nil && d["jitter_i"] != nil)
        let ratio = try #require(d["F2ratio"])
        #expect(ratio > 1.5)                     // "eee" F2 is far above "ahh" F2
        #expect((d["vowelSpace"] ?? 0) > 0.8)    // the two vowels are far apart
    }
}
