//
//  GazeTests.swift
//  ResonanceTests
//
//  Tests for GazeMapper, PointerSmoother and DwellSelector (task T14).
//

import Testing
import Foundation
import CoreGraphics
@testable import Resonance

struct GazeTests {

    @Test func mapperRecoversKnownMapping() throws {
        // True mapping: x = 800u + 50v + 200, y = -30u + 600v + 400
        let truth = GazeMapper(ax: 800, bx: 50, cx: 200, ay: -30, by: 600, cy: 400)
        let raw = [CGPoint(x: 0, y: 0), CGPoint(x: -0.2, y: 0.25), CGPoint(x: 0.2, y: 0.25),
                   CGPoint(x: -0.2, y: -0.25), CGPoint(x: 0.2, y: -0.25)]
        let screen = raw.map(truth.map)
        let fitted = try #require(GazeMapper.fit(raw: raw, screen: screen))
        let probe = CGPoint(x: 0.1, y: -0.1)
        let a = fitted.map(probe), b = truth.map(probe)
        #expect(abs(a.x - b.x) < 1)
        #expect(abs(a.y - b.y) < 1)
    }

    @Test func mapperRejectsPointsThatDontSpread() {
        let raw = Array(repeating: CGPoint(x: 0.1, y: 0.1), count: 5)
        let screen = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 0, y: 10),
                      CGPoint(x: 10, y: 10), CGPoint(x: 5, y: 5)]
        #expect(GazeMapper.fit(raw: raw, screen: screen) == nil)
    }

    @Test func mapperRejectsTinyHeadMovement() {
        // The head barely moved (less than 0.05 in raw units): a fit would wildly exaggerate it.
        let raw = [CGPoint(x: 0, y: 0), CGPoint(x: -0.01, y: 0.01), CGPoint(x: 0.01, y: 0.012),
                   CGPoint(x: -0.012, y: -0.01), CGPoint(x: 0.011, y: -0.01)]
        let screen = [CGPoint(x: 200, y: 400), CGPoint(x: 40, y: 80), CGPoint(x: 360, y: 80),
                      CGPoint(x: 40, y: 720), CGPoint(x: 360, y: 720)]
        #expect(GazeMapper.fit(raw: raw, screen: screen) == nil)
    }

    @Test func smootherReducesJitter() {
        var smoother = PointerSmoother()
        _ = smoother.add(CGPoint(x: 100, y: 100))
        let next = smoother.add(CGPoint(x: 200, y: 100))
        #expect(abs(next.x - 125) < 0.001)   // 0.25 * 200 + 0.75 * 100
    }

    @Test func dwellSelectsAfterDwellTime() {
        var d = DwellSelector(dwell: 1.0)
        var selected: String?
        var t = 0.0
        while t <= 1.2 {
            let r = d.update(tile: "yes", now: t)
            if let s = r.selected { selected = s; break }
            t += 1.0 / 30
        }
        #expect(selected == "yes")
        #expect(t >= 1.0)
    }

    @Test func briefJitterDoesNotReset() {
        var d = DwellSelector(dwell: 1.0)
        _ = d.update(tile: "yes", now: 0.0)
        _ = d.update(tile: "yes", now: 0.5)
        _ = d.update(tile: nil, now: 0.55)          // 50 ms off the tile
        let r = d.update(tile: "yes", now: 0.6)
        #expect(r.progress > 0.5)
    }

    @Test func movingAwayResets() {
        var d = DwellSelector(dwell: 1.0)
        _ = d.update(tile: "yes", now: 0.0)
        _ = d.update(tile: "yes", now: 0.5)
        _ = d.update(tile: nil, now: 0.8)           // 300 ms off: reset
        let r = d.update(tile: "yes", now: 0.9)
        #expect(r.progress < 0.1)
    }

    @Test func cooldownBlocksImmediateSecondSelection() {
        var d = DwellSelector(dwell: 0.5)
        _ = d.update(tile: "a", now: 0.0)
        let first = d.update(tile: "a", now: 0.6)
        #expect(first.selected == "a")
        _ = d.update(tile: "a", now: 0.7)
        let blocked = d.update(tile: "a", now: 1.3)
        #expect(blocked.selected == nil)           // still within the 1 s cooldown
    }
}
