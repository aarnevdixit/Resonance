//
//  SpiralAnalyzer.swift
//  Resonance
//
//  Spiral tracing (Motor Lab). The guide is an Archimedean spiral r = R * θ / θmax,
//  drawn at a fixed size so results are comparable week to week on the same phone.
//  From the finger path it measures:
//  - spiralError: mean distance (pt) from the finger to the spiral line.
//  - spiralSpeed: path length per second (pt/s).
//  - spiralTremor: extra path length caused by small wiggles, compared with a smoothed
//    version of the same path (0 = perfectly smooth; 0.05 = 5% extra wiggle).
//  Plain Swift, no UI, unit tested in SpiralAnalyzerTests.
//

import Foundation

struct SpiralSample: Equatable {
    var time: Double     // seconds since start
    var x: Double        // pt, relative to the spiral centre (y grows downward)
    var y: Double
}

struct SpiralResult: Equatable {
    var meanError: Double
    var speed: Double
    var tremor: Double
    var coverage: Double // 0...1, how much of the spiral was traced

    var metrics: [String: Double] {
        [MetricKey.spiralError: meanError, MetricKey.spiralSpeed: speed, MetricKey.spiralTremor: tremor]
    }
}

enum SpiralAnalyzer {
    /// Outer radius of the guide (pt). Fixed so every week uses the same spiral.
    static let radius = 135.0
    /// Number of turns.
    static let turns = 3.0
    static var thetaMax: Double { turns * 2 * .pi }
    /// At least half the spiral must be traced for a result.
    static let minCoverage = 0.5
    static let minSamples = 20
    static let smoothingWindow = 7

    /// Guide radius at angle θ (clamped to the spiral).
    static func guideRadius(theta: Double) -> Double {
        radius * min(max(theta, 0), thetaMax) / thetaMax
    }

    /// Points along the guide, for drawing.
    static func guidePoints(count: Int = 400) -> [(x: Double, y: Double)] {
        (0...count).map { i in
            let theta = thetaMax * Double(i) / Double(count)
            let r = guideRadius(theta: theta)
            return (r * cos(theta), r * sin(theta))
        }
    }

    /// Distance from a point to the nearest part of the spiral (radial distance on each turn).
    static func distanceToGuide(x: Double, y: Double) -> Double {
        let r = (x * x + y * y).squareRoot()
        var phi = atan2(y, x)
        if phi < 0 { phi += 2 * .pi }
        var best = Double.infinity
        var k = 0.0
        while phi + 2 * .pi * k <= thetaMax + 2 * .pi {
            let theta = phi + 2 * .pi * k
            best = min(best, abs(r - guideRadius(theta: theta)))
            k += 1
        }
        return best
    }

    static func pathLength(_ pts: [(x: Double, y: Double)]) -> Double {
        guard pts.count > 1 else { return 0 }
        var total = 0.0
        for i in 1..<pts.count {
            let dx = pts[i].x - pts[i - 1].x, dy = pts[i].y - pts[i - 1].y
            total += (dx * dx + dy * dy).squareRoot()
        }
        return total
    }

    /// Centred moving average of the path.
    static func smoothed(_ pts: [(x: Double, y: Double)], window: Int) -> [(x: Double, y: Double)] {
        guard pts.count > window else { return pts }
        let half = window / 2
        var out: [(x: Double, y: Double)] = []
        out.reserveCapacity(pts.count)
        for i in 0..<pts.count {
            let lo = max(0, i - half), hi = min(pts.count - 1, i + half)
            var sx = 0.0, sy = 0.0
            for j in lo...hi { sx += pts[j].x; sy += pts[j].y }
            let n = Double(hi - lo + 1)
            out.append((sx / n, sy / n))
        }
        return out
    }

    /// How far around the spiral the trace went (0...1), from the unwrapped angle.
    static func coverage(_ samples: [SpiralSample]) -> Double {
        guard samples.count > 1 else { return 0 }
        var unwrapped = 0.0, minAngle = 0.0, maxAngle = 0.0
        var previous = atan2(samples[0].y, samples[0].x)
        for s in samples.dropFirst() {
            // Points very close to the centre have unreliable angles.
            guard (s.x * s.x + s.y * s.y) > 9 else { continue }
            let a = atan2(s.y, s.x)
            var d = a - previous
            if d > .pi { d -= 2 * .pi }
            if d < -.pi { d += 2 * .pi }
            unwrapped += d
            previous = a
            minAngle = min(minAngle, unwrapped)
            maxAngle = max(maxAngle, unwrapped)
        }
        return min((maxAngle - minAngle) / thetaMax, 1)
    }

    static func analyze(_ samples: [SpiralSample]) -> SpiralResult? {
        guard samples.count >= minSamples else { return nil }
        let cover = coverage(samples)
        guard cover >= minCoverage else { return nil }
        let pts = samples.map { (x: $0.x, y: $0.y) }
        let error = samples.map { distanceToGuide(x: $0.x, y: $0.y) }.reduce(0, +) / Double(samples.count)
        let length = pathLength(pts)
        let duration = (samples.last?.time ?? 0) - (samples.first?.time ?? 0)
        guard duration > 0.2, length > 0 else { return nil }
        let smoothLength = pathLength(smoothed(pts, window: smoothingWindow))
        let tremor = smoothLength > 0 ? max(length / smoothLength - 1, 0) : 0
        return SpiralResult(meanError: error, speed: length / duration, tremor: tremor, coverage: cover)
    }
}
