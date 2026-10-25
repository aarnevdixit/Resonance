//
//  PitchTracker.swift
//  Resonance
//
//  Finds the pitch (fundamental frequency, F0) of one short frame of voice using a
//  simplified version of the YIN method (PLAN.pdf Section 9).
//
//  How it works, in plain words: a voiced sound repeats itself every pitch period.
//  We slide a copy of the frame against itself and measure how different it is at each
//  delay ("lag"). The first lag where the frame looks almost the same as itself is one
//  pitch period, and F0 = sampleRate / period.
//
//  Change from the plan: no Hann window is applied. Windowing changes the shape of the
//  difference function YIN relies on, and the method works better on the raw frame.
//

import Foundation
import Accelerate

enum PitchTracker {
    static let frameLength = 1764      // 40 ms at 44.1 kHz
    static let minF0: Double = 75      // lowest pitch we search for (Hz)
    static let maxF0: Double = 400     // highest pitch we search for (Hz)
    static let threshold: Float = 0.15 // how "self-similar" a frame must be to count as voiced

    /// Returns F0 in Hz, or nil when the frame is not clearly voiced.
    static func pitch(of frame: [Float], sampleRate: Double = DSP.sampleRate) -> Double? {
        let minLag = Int(sampleRate / maxF0)          // 110 at 44.1 kHz
        let maxLag = Int(sampleRate / minF0)          // 588 at 44.1 kHz
        // Lags run up to maxLag + 1, so leave room for that many samples past the window.
        let window = frame.count - maxLag - 1         // samples compared at every lag
        guard window > maxLag / 2, minLag > 1 else { return nil }

        // Skip near-silent frames: there is no pitch to find.
        guard DSP.rms(frame) > 1e-4 else { return nil }

        // Step 1: difference function d(tau) = sum_j (x[j] - x[j + tau])^2
        var d = [Float](repeating: 0, count: maxLag + 2)
        var scratch = [Float](repeating: 0, count: window)
        frame.withUnsafeBufferPointer { buf in
            guard let x = buf.baseAddress else { return }
            scratch.withUnsafeMutableBufferPointer { sbuf in
                guard let s = sbuf.baseAddress else { return }
                for tau in 1...(maxLag + 1) {
                    // s = x[tau...] - x[0...]
                    vDSP_vsub(x, 1, x + tau, 1, s, 1, vDSP_Length(window))
                    var sum: Float = 0
                    vDSP_svesq(s, 1, &sum, vDSP_Length(window))
                    d[tau] = sum
                }
            }
        }

        // Step 2: cumulative mean normalized difference d'(tau) = d(tau) * tau / sum_{k=1..tau} d(k)
        var dPrime = [Float](repeating: 1, count: maxLag + 2)
        var runningSum: Float = 0
        for tau in 1...(maxLag + 1) {
            runningSum += d[tau]
            dPrime[tau] = runningSum > 0 ? d[tau] * Float(tau) / runningSum : 1
        }

        // Step 3: the first lag in range that drops below the threshold, then walk down to its local minimum.
        var tau = minLag
        var found: Int?
        while tau <= maxLag {
            if dPrime[tau] < threshold {
                while tau + 1 <= maxLag && dPrime[tau + 1] < dPrime[tau] { tau += 1 }
                found = tau
                break
            }
            tau += 1
        }
        guard let best = found else { return nil }

        // Step 4: parabolic interpolation around the minimum for sub-sample accuracy.
        var refined = Double(best)
        if best > 1 && best < maxLag + 1 {
            let a = Double(dPrime[best - 1])
            let b = Double(dPrime[best])
            let c = Double(dPrime[best + 1])
            let denominator = a - 2 * b + c
            if abs(denominator) > 1e-12 {
                let shift = 0.5 * (a - c) / denominator
                if abs(shift) < 1 { refined += shift }
            }
        }

        // Step 5: F0 = sampleRate / period
        let f0 = sampleRate / refined
        return (minF0...maxF0).contains(f0) ? f0 : nil
    }
}
