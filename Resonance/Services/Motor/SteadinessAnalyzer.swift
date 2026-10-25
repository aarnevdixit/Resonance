//
//  SteadinessAnalyzer.swift
//  Resonance
//
//  Steadiness hold (PLAN.pdf Section 10). The phone records user acceleration
//  (gravity removed) about 100 times a second while it is held at arm's length.
//    steadyRMS    = overall shakiness in milli-g (lower = steadier)
//    fatigueRatio = shakiness in the last 4 s / first 4 s (above 1 = shakier as the arm tires)
//    tremorBand   = share of movement energy between 3 and 12 Hz (typical tremor range)
//

import Foundation

struct MotionSample: Equatable {
    var t: Double      // seconds
    var x: Double      // acceleration in g, gravity removed
    var y: Double
    var z: Double
}

struct SteadinessResult: Equatable {
    var steadyRMS: Double
    var fatigueRatio: Double?
    var tremorBand: Double?

    var metrics: [String: Double] {
        var m: [String: Double] = [MetricKey.steadyRMS: steadyRMS]
        if let fatigueRatio { m[MetricKey.fatigueRatio] = fatigueRatio }
        if let tremorBand { m[MetricKey.tremorBand] = tremorBand }
        return m
    }
}

enum SteadinessAnalyzer {
    static let settleSeconds = 2.0
    static let windowSeconds = 4.0

    static func analyze(_ raw: [MotionSample]) -> SteadinessResult? {
        guard let t0 = raw.first?.t else { return nil }
        let samples = raw.filter { $0.t - t0 >= settleSeconds }
        guard samples.count >= 50, let start = samples.first?.t, let end = samples.last?.t else { return nil }

        let rms = rmsMilliG(samples)

        let first = samples.filter { $0.t - start < windowSeconds }
        let last = samples.filter { end - $0.t < windowSeconds }
        let firstRMS = rmsMilliG(first)
        let fatigue: Double? = firstRMS > 0 ? rmsMilliG(last) / firstRMS : nil

        let duration = end - start
        let sampleRate = duration > 0 ? Double(samples.count - 1) / duration : 100
        let tremor = bandPowerRatio(samples, sampleRate: sampleRate, low: 3, high: 12)

        return SteadinessResult(steadyRMS: rms, fatigueRatio: fatigue, tremorBand: tremor)
    }

    /// sqrt(mean(x^2 + y^2 + z^2)) in milli-g.
    static func rmsMilliG(_ samples: [MotionSample]) -> Double {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(0) { $0 + $1.x * $1.x + $1.y * $1.y + $1.z * $1.z }
        return sqrt(sum / Double(samples.count)) * 1000
    }

    /// Fraction of movement power between `low` and `high` Hz, summed over the three axes.
    /// Uses a direct Fourier transform on up to 1024 samples, which is fast enough here.
    static func bandPowerRatio(_ samples: [MotionSample], sampleRate: Double, low: Double, high: Double) -> Double? {
        let n = min(samples.count, 1024)
        guard n >= 64, sampleRate > 0 else { return nil }
        let window = Array(samples.suffix(n))
        let axes: [[Double]] = [window.map(\.x), window.map(\.y), window.map(\.z)]

        var bandPower = 0.0
        var totalPower = 0.0
        for axis in axes {
            let mean = axis.reduce(0, +) / Double(n)
            let centered = axis.map { $0 - mean }
            for k in 1...(n / 2) {
                var re = 0.0, im = 0.0
                let w = 2 * Double.pi * Double(k) / Double(n)
                for (i, v) in centered.enumerated() {
                    re += v * cos(w * Double(i))
                    im -= v * sin(w * Double(i))
                }
                let power = re * re + im * im
                let frequency = Double(k) * sampleRate / Double(n)
                totalPower += power
                if frequency >= low && frequency <= high { bandPower += power }
            }
        }
        return totalPower > 0 ? bandPower / totalPower : nil
    }
}
