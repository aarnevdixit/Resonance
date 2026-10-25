//
//  DSPTests.swift
//  ResonanceTests
//
//  Unit tests for DSP.swift (PLAN.pdf Sections 16 T03 and 18).
//  They use synthetic signals, so no audio files are needed.
//  Run them in Xcode with Product > Test (Command-U) on any simulator.
//

import Testing
import Foundation
@testable import Resonance

struct DSPTests {

    /// A pure sine wave at 44.1 kHz.
    private func sine(frequency: Float, amplitude: Float, seconds: Double) -> [Float] {
        let count = Int(seconds * DSP.sampleRate)
        let step = 2 * Float.pi * frequency / Float(DSP.sampleRate)
        return (0..<count).map { amplitude * sin(Float($0) * step) }
    }

    @Test func sineAtHalfAmplitudeIsAboutMinus9dB() {
        // RMS of a sine = amplitude / sqrt(2) = 0.3536, which is -9.03 dBFS.
        let signal = sine(frequency: 220, amplitude: 0.5, seconds: 1)
        let frames = DSP.frameRMSdB(signal)
        #expect(!frames.isEmpty)
        let median = DSP.percentile(frames, 50)
        #expect(abs(median - (-9.03)) < 0.3)
    }

    @Test func silenceIsBelowMinus80dB() {
        let silence = [Float](repeating: 0, count: 44_100)
        let frames = DSP.frameRMSdB(silence)
        #expect(frames.allSatisfy { $0 < -80 })
    }

    @Test func frameCountMatchesHop() {
        // 1 s of audio, 1102-sample frames every 441 samples -> (44100 - 1102) / 441 + 1 = 98 frames.
        let signal = sine(frequency: 220, amplitude: 0.5, seconds: 1)
        #expect(DSP.frameRMSdB(signal).count == 98)
    }

    @Test func shortSignalGivesOneFrame() {
        let signal = sine(frequency: 220, amplitude: 0.5, seconds: 0.01)
        #expect(DSP.frameRMSdB(signal).count == 1)
    }

    @Test func percentileInterpolates() {
        let values: [Float] = [1, 2, 3, 4, 5]
        #expect(DSP.percentile(values, 50) == 3)
        #expect(DSP.percentile(values, 0) == 1)
        #expect(DSP.percentile(values, 100) == 5)
        #expect(abs(DSP.percentile(values, 25) - 2) < 0.0001)
    }

    @Test func movingAverageKeepsConstantSignal() {
        let flat = [Float](repeating: 7, count: 20)
        #expect(DSP.movingAverage(flat, width: 5) == flat)
    }

    @Test func movingAverageSmoothsSpike() {
        var signal = [Float](repeating: 0, count: 9)
        signal[4] = 9
        let smoothed = DSP.movingAverage(signal, width: 3)
        #expect(abs(smoothed[4] - 3) < 0.0001)
        #expect(abs(smoothed[3] - 3) < 0.0001)
        #expect(smoothed[0] == 0)
    }

    @Test func voicedMaskFillsShortGaps() {
        // Noise floor -60, margin 15: frames above -45 dB are voiced.
        // 20 loud, 5 quiet (short gap), 20 loud, 30 quiet (long gap), 10 loud.
        let db: [Float] = Array(repeating: -20, count: 20)
            + Array(repeating: -70, count: 5)
            + Array(repeating: -20, count: 20)
            + Array(repeating: -70, count: 30)
            + Array(repeating: -20, count: 10)
        let mask = DSP.voicedMask(db, noiseFloor: -60)
        #expect(DSP.longestTrueRun(mask) == 45)     // 20 + 5 filled + 20
        #expect(mask[50] == false)                  // inside the long gap
        #expect(mask.suffix(10).allSatisfy { $0 })
    }

    @Test func voicedMaskDoesNotFillEdges() {
        let db: [Float] = Array(repeating: -70, count: 3) + Array(repeating: -20, count: 10)
        let mask = DSP.voicedMask(db, noiseFloor: -60)
        #expect(mask.prefix(3).allSatisfy { !$0 })
    }

    @Test func secondsFromFrames() {
        // 100 frames x 441 samples = 44,100 samples = 1 second.
        #expect(abs(DSP.seconds(frames: 100) - 1.0) < 0.0001)
    }
}
