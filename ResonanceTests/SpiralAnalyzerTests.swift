//
//  SpiralAnalyzerTests.swift
//  ResonanceTests
//
//  Spiral tracing: perfect traces, offset traces, shaky traces and partial traces.
//

import Testing
import Foundation
@testable import Resonance

struct SpiralAnalyzerTests {

    /// A trace along the guide, with an optional radial offset and wiggle.
    func trace(fraction: Double = 1, offset: Double = 0, wiggle: Double = 0,
               seconds: Double = 10, count: Int = 600) -> [SpiralSample] {
        (0..<count).map { i in
            let t = Double(i) / Double(count - 1)
            let theta = SpiralAnalyzer.thetaMax * fraction * t
            // Wiggle alternates each sample: a fast shake on top of the line.
            let r = SpiralAnalyzer.guideRadius(theta: theta) + offset + (i % 2 == 0 ? wiggle : -wiggle)
            return SpiralSample(time: seconds * t, x: r * cos(theta), y: r * sin(theta))
        }
    }

    @Test func perfectTraceHasTinyErrorAndNoTremor() throws {
        let result = try #require(SpiralAnalyzer.analyze(trace()))
        #expect(result.meanError < 0.5)
        #expect(result.tremor < 0.01)
        #expect(result.coverage > 0.95)
    }

    @Test func offsetTraceShowsTheOffset() throws {
        let result = try #require(SpiralAnalyzer.analyze(trace(offset: 6)))
        #expect(result.meanError > 5 && result.meanError < 7)
    }

    @Test func shakyTraceHasMoreTremor() throws {
        let smooth = try #require(SpiralAnalyzer.analyze(trace()))
        let shaky = try #require(SpiralAnalyzer.analyze(trace(wiggle: 3)))
        #expect(shaky.tremor > smooth.tremor + 0.1)
    }

    @Test func speedIsLengthOverTime() throws {
        let fast = try #require(SpiralAnalyzer.analyze(trace(seconds: 5)))
        let slow = try #require(SpiralAnalyzer.analyze(trace(seconds: 10)))
        #expect(abs(fast.speed / slow.speed - 2) < 0.05)
    }

    @Test func partialTraceIsRejected() {
        #expect(SpiralAnalyzer.analyze(trace(fraction: 0.3)) == nil)
        #expect(SpiralAnalyzer.analyze(Array(trace().prefix(5))) == nil)
    }

    @Test func distanceIsMeasuredToTheNearestTurn() {
        // A point exactly on the second turn.
        let theta = 2 * .pi + 1.0
        let r = SpiralAnalyzer.guideRadius(theta: theta)
        #expect(SpiralAnalyzer.distanceToGuide(x: r * cos(theta), y: r * sin(theta)) < 0.001)
    }
}
