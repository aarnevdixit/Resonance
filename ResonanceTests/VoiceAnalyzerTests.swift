//
//  VoiceAnalyzerTests.swift
//  ResonanceTests
//
//  Tests for PitchTracker and VoiceAnalyzer (tasks T04 and T05) using synthetic signals.
//

import Testing
import Foundation
@testable import Resonance

struct VoiceAnalyzerTests {

    private func sine(frequency: Double, amplitude: Float = 0.5, seconds: Double) -> [Float] {
        let count = Int(seconds * DSP.sampleRate)
        let step = 2 * Double.pi * frequency / DSP.sampleRate
        return (0..<count).map { amplitude * Float(sin(Double($0) * step)) }
    }

    private func silence(_ seconds: Double) -> [Float] {
        [Float](repeating: 0, count: Int(seconds * DSP.sampleRate))
    }

    // MARK: PitchTracker (T04)

    @Test(arguments: [110.0, 220.0, 330.0])
    func pitchOfSineWithin2Percent(frequency: Double) throws {
        let frame = Array(sine(frequency: frequency, seconds: 0.1).prefix(PitchTracker.frameLength))
        let f0 = try #require(PitchTracker.pitch(of: frame))
        #expect(abs(f0 - frequency) / frequency < 0.02)
    }

    @Test func noPitchInSilence() {
        let frame = [Float](repeating: 0, count: PitchTracker.frameLength)
        #expect(PitchTracker.pitch(of: frame) == nil)
    }

    @Test func noPitchInNoise() {
        var generator = SystemRandomNumberGenerator()
        let frame = (0..<PitchTracker.frameLength).map { _ in Float.random(in: -0.5...0.5, using: &generator) }
        #expect(PitchTracker.pitch(of: frame) == nil)
    }

    // MARK: Held vowel (T04)

    @Test func threeSecondToneGivesMptAboutThree() throws {
        let signal = silence(0.5) + sine(frequency: 220, seconds: 3) + silence(0.5)
        let result = VoiceAnalyzer.analyzeVowel(signal)
        #expect(abs(result.mpt - 3) < 0.15)
        let f0 = try #require(result.f0Mean)
        #expect(abs(f0 - 220) / 220 < 0.02)
        #expect(result.flags.isEmpty)
        // A pure tone is perfectly steady, so pitch variation and jitter are tiny.
        #expect((result.f0StdSemi ?? 1) < 0.1)
        #expect((result.jitter ?? 100) < 1)
    }

    @Test func shortVowelIsFlagged() {
        let signal = silence(0.5) + sine(frequency: 220, seconds: 0.5) + silence(0.5)
        let result = VoiceAnalyzer.analyzeVowel(signal)
        #expect(result.flags.contains(QualityFlag.tooShort))
    }

    @Test func noisyCalibrationIsDetected() {
        let quiet = silence(1)
        let loud = sine(frequency: 300, amplitude: 0.2, seconds: 1)
        #expect(VoiceAnalyzer.isTooNoisy(calibrationSamples: quiet) == false)
        #expect(VoiceAnalyzer.isTooNoisy(calibrationSamples: loud) == true)
    }

    // MARK: Pa-ta-ka (T05)

    @Test func toneBurstsEvery160msGiveAbout6Point25PerSecond() throws {
        // 30 ms bursts every 160 ms, starting after 0.6 s, for 5 s in total.
        var signal = silence(5)
        let burst = sine(frequency: 200, seconds: 0.03)
        var start = 0.6
        while start + 0.03 < 5 {
            let index = Int(start * DSP.sampleRate)
            for (k, value) in burst.enumerated() where index + k < signal.count {
                signal[index + k] = value
            }
            start += 0.16
        }
        let result = VoiceAnalyzer.analyzeDDK(signal)
        let rate = try #require(result.rate)
        #expect(abs(rate - 6.25) < 0.2)
        #expect((result.cv ?? 1) < 0.1)
        #expect(result.flags.isEmpty)
    }

    @Test func tooFewSyllablesIsFlagged() {
        let signal = silence(1) + sine(frequency: 200, seconds: 0.05) + silence(1)
        let result = VoiceAnalyzer.analyzeDDK(signal)
        #expect(result.rate == nil)
        #expect(result.flags.contains(QualityFlag.tooFewSyllables))
    }

    @Test func faintBurstsAreNotSyllables() {
        // The same rhythm as real syllables, but at about -66 dBFS (background noise), with a
        // calibration floor from digital silence: no syllable rate should be reported.
        var signal = silence(5)
        let burst = sine(frequency: 200, seconds: 0.03).map { $0 * 0.001 }
        var start = 0.6
        while start + 0.03 < 5 {
            let index = Int(start * DSP.sampleRate)
            for (k, value) in burst.enumerated() where index + k < signal.count { signal[index + k] = value }
            start += 0.16
        }
        let result = VoiceAnalyzer.analyzeDDK(signal, noiseFloor: -160)
        #expect(result.rate == nil)
    }

    @Test func silentVowelSavesNoMetrics() {
        let result = VoiceAnalyzer.analyzeVowel(silence(2))
        #expect(result.metrics.isEmpty)
    }
}
