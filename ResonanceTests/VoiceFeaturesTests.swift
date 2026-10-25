//
//  VoiceFeaturesTests.swift
//  ResonanceTests
//
//  Parity test: the Swift feature extractor must match the Python code the model was
//  trained with (Scripts/ml/features.py). Expected values come from Scripts/ml/parity.py,
//  which builds exactly the same test vowel.
//

import Testing
import Foundation
@testable import Resonance

struct VoiceFeaturesTests {

    /// Same signal as parity.py: a 140 Hz vowel with 5 Hz vibrato, 4 Hz loudness wobble,
    /// 5 harmonics, a little deterministic noise, and 0.3 s of near-silence at each end.
    static func testSignal() -> [Float] {
        let sr = 44_100.0
        let n = Int(sr * 3.0)
        var noise = [Double](repeating: 0, count: n)
        var state: Int64 = 12345
        for i in 0..<n {
            state = (1_103_515_245 * state + 12345) % 2_147_483_648
            noise[i] = Double(state) / 2_147_483_648 - 0.5
        }
        var x = [Double](repeating: 0, count: n)
        var cumulative = 0.0
        for i in 0..<n {
            let t = Double(i) / sr
            let f0 = 140 + 2.0 * sin(2 * Double.pi * 5 * t)
            cumulative += f0
            let phase = 2 * Double.pi * cumulative / sr
            var v = 0.0
            for h in 1...5 { v += (0.6 / Double(h)) * sin(Double(h) * phase) }
            v *= 0.5 * (1 + 0.1 * sin(2 * Double.pi * 4 * t))
            x[i] = v + 0.01 * noise[i]
        }
        let pad = Int(0.3 * sr)
        let silence = (0..<pad).map { 0.001 * noise[$0] }
        return (silence + x + silence).map { Float($0) }
    }

    // Printed by `python3 parity.py`.
    static let expected: [String: Double] = [
        "f0StdSemi": 0.16902620859629683,
        "jitter": 0.27714924608302993,
        "shimmer": 1.4633536142912071,
        "aperiodicity": 0.0006358026050218185,
        "voicedRatio": 1.0,
        "f0Tremor": 0.9983183349229399,
        "ampTremor": 0.9775999780438978,
        "ampStdDb": 0.6198931107765268,
        "cpp": 0.6180991237823574,
        "spectralTilt": 47.547059140561146,
    ]

    @Test func matchesPythonReference() throws {
        let f = try #require(VoiceFeatures.extract(Self.testSignal()))
        for (name, value) in zip(VoiceFeatureVector.names, f.values) {
            let want = try #require(Self.expected[name])
            let tolerance = max(1e-6, abs(want) * 1e-3)   // 0.1%
            #expect(abs(value - want) <= tolerance, "\(name): Swift \(value), Python \(want)")
        }
    }

    @Test func silenceGivesNoFeatures() {
        #expect(VoiceFeatures.extract([Float](repeating: 0, count: 44_100)) == nil)
    }

    @Test func faintBackgroundNoiseIsNotAVoice() {
        // Hiss around -70 dBFS must be refused, not amplified into fake voice features.
        var state: UInt64 = 7
        let hiss = (0..<88_200).map { _ -> Float in
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Float(Double(state >> 33) / Double(1 << 31) - 0.5) * 0.001
        }
        #expect(VoiceFeatures.extract(hiss) == nil)
    }

    @Test func percentileMatchesNumPy() {
        // numpy.percentile([1, 2, 3, 4], 25) == 1.75
        #expect(abs(VoiceFeatures.percentile([4, 1, 3, 2], 25) - 1.75) < 1e-12)
    }

    @Test func bandRatioFindsTremor() {
        // A pure 6 Hz wobble sampled at 100 Hz puts nearly all its power in the 3-12 Hz band.
        let s = (0..<300).map { sin(2 * Double.pi * 6 * Double($0) / 100) }
        #expect(VoiceFeatures.bandRatio(s, rate: 100) > 0.95)
    }
}
