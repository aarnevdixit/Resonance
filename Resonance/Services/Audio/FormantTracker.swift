//
//  FormantTracker.swift
//  Resonance
//
//  Vowel formants F1 and F2 (tongue and jaw position) from an LPC spectral envelope.
//  Exact port of Scripts/ml/formants.py, which the Speech Change model was trained with.
//
//  Why it matters: in bulbar ALS the tongue moves less, so "eee" loses its high second
//  formant (F2) and "ahh" and "eee" sound more alike (Vashkevich & Rushkevich, 2021).
//
//  Method:
//  1. Downsample 44.1 kHz -> 11,025 Hz by averaging blocks of 4 samples.
//  2. For each analysis frame: 1024 samples, pre-emphasis 0.97, Hann window,
//     autocorrelation LPC of order 12 (Levinson-Durbin).
//  3. Evaluate the envelope 1/|A(f)|^2 every 5 Hz from 150 to 4000 Hz and take local maxima
//     narrower than 500 Hz at half power.
//     F1 = first peak in 200-1000 Hz; F2 = first peak at least 200 Hz above F1, in 700-3200 Hz.
//  4. Report the median over frames, in kHz.
//

import Foundation

enum FormantTracker {
    static let decimation = 4
    static let sampleRate = 44_100.0 / 4
    static let order = 12
    static let frameLength = 1024
    /// Real formants are sharp; broad LPC bumps (wider than this at half power) are fitting artifacts.
    static let maxBandwidth = 500.0
    static let grid = 5.0

    /// Median F1 and F2 in kHz over the given frames, or nil when no frame gives a value.
    /// - Parameters:
    ///   - signal: the level-normalized 44.1 kHz signal from `VoiceFeatures.analyze`.
    ///   - frameStarts: frame starts at 44.1 kHz, also from `VoiceFeatures.analyze`.
    static func formants(signal: [Double], frameStarts: [Int]) -> (f1: Double?, f2: Double?) {
        let n = signal.count / decimation
        guard n > 0 else { return (nil, nil) }
        var x = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let b = i * decimation
            x[i] = (signal[b] + signal[b + 1] + signal[b + 2] + signal[b + 3]) / 4
        }
        var f1s: [Double] = [], f2s: [Double] = []
        for s in frameStarts {
            let s4 = s / decimation
            guard s4 >= 0, s4 + frameLength <= x.count else { continue }
            let (f1, f2) = frameFormants(Array(x[s4..<(s4 + frameLength)]))
            if let f1 { f1s.append(f1) }
            if let f2 { f2s.append(f2) }
        }
        return (f1s.isEmpty ? nil : VoiceFeatures.median(f1s) / 1000,
                f2s.isEmpty ? nil : VoiceFeatures.median(f2s) / 1000)
    }

    /// F1 and F2 in Hz for one 1024-sample frame at 11,025 Hz.
    static func frameFormants(_ raw: [Double]) -> (Double?, Double?) {
        let n = raw.count
        guard n == frameLength else { return (nil, nil) }
        // Pre-emphasis and Hann window.
        var s = [Double](repeating: 0, count: n)
        s[0] = raw[0]
        for i in 1..<n { s[i] = raw[i] - 0.97 * raw[i - 1] }
        for i in 0..<n { s[i] *= 0.5 - 0.5 * cos(2 * Double.pi * Double(i) / Double(n)) }

        // Autocorrelation r[0...order].
        var r = [Double](repeating: 0, count: order + 1)
        for k in 0...order {
            var acc = 0.0
            for i in 0..<(n - k) { acc += s[i] * s[i + k] }
            r[k] = acc
        }
        guard let a = levinson(r) else { return (nil, nil) }

        // LPC envelope on a 5 Hz grid and its local maxima.
        let freqs = stride(from: 150.0, through: 4000.0, by: 5.0).map { $0 }
        var env = [Double](repeating: 0, count: freqs.count)
        for (j, f) in freqs.enumerated() {
            let om = 2 * Double.pi * f / sampleRate
            var re = 0.0, im = 0.0
            for k in 0...order {
                re += a[k] * cos(om * Double(k))
                im -= a[k] * sin(om * Double(k))
            }
            env[j] = 1 / (re * re + im * im + 1e-18)
        }
        var peaks: [Double] = []
        if env.count > 2 {
            for j in 1..<(env.count - 1)
            where env[j] > env[j - 1] && env[j] >= env[j + 1] && halfPowerWidth(env, j) <= maxBandwidth {
                peaks.append(freqs[j])
            }
        }
        guard let f1 = peaks.first(where: { $0 >= 200 && $0 <= 1000 }) else { return (nil, nil) }
        let f2 = peaks.first(where: { $0 >= f1 + 200 && $0 >= 700 && $0 <= 3200 })
        return (f1, f2)
    }

    /// Width in Hz of the envelope peak at grid index i where it falls to half power.
    /// A side that never falls to half power inside the grid counts up to the grid edge.
    static func halfPowerWidth(_ env: [Double], _ i: Int) -> Double {
        let half = env[i] / 2
        var lo = i
        while lo > 0 && env[lo] > half { lo -= 1 }
        var hi = i
        while hi < env.count - 1 && env[hi] > half { hi += 1 }
        return Double(hi - lo) * grid
    }

    /// Levinson-Durbin recursion: LPC coefficients a[0...order] with a[0] = 1.
    static func levinson(_ r: [Double]) -> [Double]? {
        var a = [Double](repeating: 0, count: order + 1)
        a[0] = 1
        var e = r[0]
        guard e > 0 else { return nil }
        for i in 1...order {
            var acc = r[i]
            if i > 1 { for j in 1..<i { acc += a[j] * r[i - j] } }
            let k = -acc / e
            var next = a
            if i > 1 { for j in 1..<i { next[j] = a[j] + k * a[i - j] } }
            next[i] = k
            a = next
            e *= (1 - k * k)
            guard e > 0 else { return nil }
        }
        return a
    }
}
