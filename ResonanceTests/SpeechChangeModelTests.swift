//
//  SpeechChangeModelTests.swift
//  ResonanceTests
//
//  The Swift model must give the same output as the scikit-learn model it was exported from.
//  Reference inputs and outputs come from Scripts/ml/model_reference.json (first three speakers
//  of the Minsk2020 database), written by export_speaker_model.py. The second speaker has missing
//  "eee" formants, which tests the median fill.
//

import Testing
import Foundation
@testable import Resonance

struct SpeechChangeModelTests {

    static let rows: [[String: Double]] = [
        ["f0StdSemi_a": 0.1542912717818875, "jitter_a": 0.1865502456774165, "shimmer_a": 1.2142586961726822, "aperiodicity_a": 0.0018297270516267, "voicedRatio_a": 1.0, "f0Tremor_a": 0.621974531322452, "ampTremor_a": 0.3117210503995499, "ampStdDb_a": 0.6193394495117674, "cpp_a": 1.4618969733643397, "spectralTilt_a": 10.254376793302988, "F1_a": 0.3275, "F2_a": 1.0775, "F1_i": 0.285, "F2_i": 3.07, "F2ratio": 2.849187935034803, "vowelSpace": 1.9929532106901051],
        ["f0StdSemi_a": 0.2187323856298841, "jitter_a": 0.188283410004367, "shimmer_a": 1.5592448893481283, "aperiodicity_a": 0.008563476787655, "voicedRatio_a": 1.0, "f0Tremor_a": 0.2565679551551059, "ampTremor_a": 0.2770498037666175, "ampStdDb_a": 0.7840307555411326, "cpp_a": 0.8533854950036949, "spectralTilt_a": 23.772624098999746, "F1_a": 0.345, "F1_i": 0.355],
        ["f0StdSemi_a": 0.1441321059924722, "jitter_a": 0.1844668748733833, "shimmer_a": 0.7076747898508152, "aperiodicity_a": 0.0147783848058112, "voicedRatio_a": 1.0, "f0Tremor_a": 0.3271015716108641, "ampTremor_a": 0.2550297071703496, "ampStdDb_a": 0.768769122579045, "cpp_a": 0.8558117034997366, "spectralTilt_a": 19.296634861256862, "F1_a": 0.555, "F2_a": 1.455, "F1_i": 0.29, "F2_i": 2.19, "F2ratio": 1.5051546391752575, "vowelSpace": 0.7813129974600447],
    ]
    static let expected: [Double] = [0.0012919915781901092, 0.48616371078169907, 0.1711794705552226]

    @Test(arguments: 0..<3)
    func matchesScikitLearn(_ i: Int) throws {
        let p = try #require(SpeechChangeModel.probability(named: Self.rows[i]))
        #expect(abs(p - Self.expected[i]) < 1e-6)
    }

    @Test func missingVoiceFeatureGivesNoScore() {
        var row = Self.rows[0]
        row["jitter_a"] = nil
        #expect(SpeechChangeModel.probability(named: row) == nil)
    }

    @Test func rejectsNaN() {
        var row = Self.rows[0]
        row["cpp_a"] = .nan
        #expect(SpeechChangeModel.probability(named: row) == nil)
    }

    @Test func lessTongueReachRaisesTheScore() throws {
        // Same person, but a lower "eee" F2: the model should move toward the ALS recordings.
        var row = Self.rows[2]
        let base = try #require(SpeechChangeModel.probability(named: row))
        row["F2_i"] = (row["F2_i"] ?? 2.2) - 0.4
        let lower = try #require(SpeechChangeModel.probability(named: row))
        #expect(lower > base)
    }

    @Test func scoreFromRecordingsIsZeroToHundred() throws {
        let ahh = try #require(VowelAnalysis.analyze(VoiceFeaturesTests.testSignal()))
        let eee = try #require(VowelAnalysis.analyze(FormantTrackerTests.syntheticEee()))
        let s = try #require(SpeechChangeModel.score(ahh: ahh, eee: eee))
        #expect((0...100).contains(s))
    }

    @Test func needsTheAhhRecording() throws {
        let eee = try #require(VowelAnalysis.analyze(FormantTrackerTests.syntheticEee()))
        #expect(SpeechChangeModel.score(ahh: nil, eee: eee) == nil)
    }

    @Test func requiredWordingIsExact() {
        #expect(SpeechChangeModel.explanation == "How much this recording resembles voice recordings from people with ALS in a research dataset. It is not a diagnosis and is most useful as a trend over time.")
    }
}
