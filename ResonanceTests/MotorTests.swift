//
//  MotorTests.swift
//  ResonanceTests
//
//  Tests for TapAnalyzer and SteadinessAnalyzer (task T08).
//

import Testing
import Foundation
@testable import Resonance

struct MotorTests {

    // MARK: Tapping

    @Test func alternatingTapsAtFivePerSecond() throws {
        // 50 alternating taps, one every 0.2 s, over 10 s.
        let taps = (0..<50).map { TapEvent(time: Double($0) * 0.2, target: $0 % 2) }
        let r = TapAnalyzer.analyze(taps, duration: 10)
        #expect(r.validTaps == 50)
        #expect(abs(r.rate - 5) < 0.0001)
        #expect(r.accuracy == 100)
        let cv = try #require(r.cv)
        #expect(cv < 0.0001)
    }

    @Test func sameTargetTwiceCountsOnce() {
        let taps = [
            TapEvent(time: 0.0, target: 0),
            TapEvent(time: 0.2, target: 0),   // same target again: not valid
            TapEvent(time: 0.4, target: 1),
            TapEvent(time: 0.6, target: nil), // miss
        ]
        let r = TapAnalyzer.analyze(taps, duration: 1)
        #expect(r.validTaps == 2)
        #expect(r.accuracy == 75)
    }

    @Test func hitTesting() {
        let left = CGPoint(x: 100, y: 100), right = CGPoint(x: 260, y: 100)
        #expect(TapAnalyzer.target(at: CGPoint(x: 110, y: 100), leftCenter: left, rightCenter: right, radius: 40) == 0)
        #expect(TapAnalyzer.target(at: CGPoint(x: 250, y: 120), leftCenter: left, rightCenter: right, radius: 40) == 1)
        #expect(TapAnalyzer.target(at: CGPoint(x: 180, y: 100), leftCenter: left, rightCenter: right, radius: 40) == nil)
    }

    // MARK: Steadiness

    private func samples(seconds: Double, rate: Double = 100,
                         x: (Double) -> Double) -> [MotionSample] {
        let n = Int(seconds * rate)
        return (0..<n).map { i in
            let t = Double(i) / rate
            return MotionSample(t: t, x: x(t), y: 0, z: 0)
        }
    }

    @Test func stillPhoneIsVerySteady() throws {
        let r = try #require(SteadinessAnalyzer.analyze(samples(seconds: 15) { _ in 0 }))
        #expect(r.steadyRMS < 0.0001)
    }

    @Test func sineShakeHasExpectedRMSAndTremorBand() throws {
        // 6 Hz shake with 0.05 g amplitude: RMS = 50 / sqrt(2) = 35.4 mg, all power at 6 Hz.
        let r = try #require(SteadinessAnalyzer.analyze(samples(seconds: 15) { 0.05 * sin(2 * .pi * 6 * $0) }))
        #expect(abs(r.steadyRMS - 35.36) < 1.5)
        let tremor = try #require(r.tremorBand)
        #expect(tremor > 0.8)
        let fatigue = try #require(r.fatigueRatio)
        #expect(abs(fatigue - 1) < 0.1)
    }

    @Test func growingShakeShowsFatigue() throws {
        // Amplitude grows from 0.02 g to 0.06 g over 15 s.
        let r = try #require(SteadinessAnalyzer.analyze(samples(seconds: 15) { t in
            (0.02 + 0.04 * t / 15) * sin(2 * .pi * 6 * t)
        }))
        let fatigue = try #require(r.fatigueRatio)
        #expect(fatigue > 1.5)
    }

    @Test func tooLittleDataReturnsNil() {
        #expect(SteadinessAnalyzer.analyze(samples(seconds: 2.2) { _ in 0.01 }) == nil)
    }
}
