//
//  TapAnalyzer.swift
//  Resonance
//
//  Alternating finger-tapping test (PLAN.pdf Section 10).
//  A tap is "valid" when it lands inside a target AND on the opposite target
//  from the previous valid tap. Plain Swift so it can be unit tested.
//

import Foundation

struct TapEvent: Equatable {
    var time: Double     // seconds since the test started
    var target: Int?     // 0 = left circle, 1 = right circle, nil = missed both
}

struct TapResult: Equatable {
    var validTaps: Int
    var totalTaps: Int
    var rate: Double         // valid taps per second
    var accuracy: Double     // % of taps inside a target
    var cv: Double?          // rhythm: std / mean of intervals between valid taps
}

enum TapAnalyzer {
    static func analyze(_ taps: [TapEvent], duration: Double) -> TapResult {
        var valid: [TapEvent] = []
        var lastTarget: Int?
        for tap in taps {
            guard let target = tap.target else { continue }
            if target != lastTarget {
                valid.append(tap)
                lastTarget = target
            }
        }

        let hits = taps.filter { $0.target != nil }.count
        let accuracy = taps.isEmpty ? 0 : Double(hits) / Double(taps.count) * 100
        let rate = duration > 0 ? Double(valid.count) / duration : 0

        let intervals = zip(valid.dropFirst(), valid).map { $0.time - $1.time }
        var cv: Double?
        if intervals.count >= 2 {
            let mean = intervals.reduce(0, +) / Double(intervals.count)
            if mean > 0 {
                let variance = intervals.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(intervals.count - 1)
                cv = sqrt(variance) / mean
            }
        }

        return TapResult(validTaps: valid.count, totalTaps: taps.count, rate: rate, accuracy: accuracy, cv: cv)
    }

    /// Which target (if any) a point hits. Targets are circles of `radius` around the two centers.
    static func target(at point: CGPoint, leftCenter: CGPoint, rightCenter: CGPoint, radius: CGFloat) -> Int? {
        if hypot(point.x - leftCenter.x, point.y - leftCenter.y) <= radius { return 0 }
        if hypot(point.x - rightCenter.x, point.y - rightCenter.y) <= radius { return 1 }
        return nil
    }
}
