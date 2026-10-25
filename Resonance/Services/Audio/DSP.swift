//
//  DSP.swift
//  Resonance
//
//  Basic signal math used by the Voice Lab (PLAN.pdf Section 9, "Framing").
//  Plain Swift + Accelerate, no UI, so it can be unit tested.
//
//  Defaults assume 44,100 samples per second:
//    frame = 25 ms = 1102 samples, hop = 10 ms = 441 samples.
//

import Foundation
import Accelerate

enum DSP {
    static let sampleRate: Double = 44_100
    static let defaultFrame = 1102   // 25 ms
    static let defaultHop = 441      // 10 ms

    /// Converts an RMS amplitude (0...1) to decibels relative to full scale (dBFS).
    /// A full-scale sine is about -3 dBFS; silence is about -180 dBFS.
    static func toDB(_ rms: Float) -> Float {
        20 * log10(rms + 1e-9)
    }

    /// Root-mean-square of a whole signal.
    static func rms(_ x: [Float]) -> Float {
        guard !x.isEmpty else { return 0 }
        var result: Float = 0
        x.withUnsafeBufferPointer { buf in
            if let base = buf.baseAddress {
                vDSP_rmsqv(base, 1, &result, vDSP_Length(x.count))
            }
        }
        return result
    }

    /// Loudness of each short frame, in dBFS.
    /// For each frame: rms = sqrt(mean(x^2)), dB = 20 * log10(rms).
    static func frameRMSdB(_ x: [Float], frame: Int = defaultFrame, hop: Int = defaultHop) -> [Float] {
        guard !x.isEmpty, frame > 0, hop > 0 else { return [] }
        // A signal shorter than one frame is treated as a single frame.
        if x.count < frame { return [toDB(rms(x))] }

        var out: [Float] = []
        out.reserveCapacity((x.count - frame) / hop + 1)
        x.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            var start = 0
            while start + frame <= x.count {
                var r: Float = 0
                vDSP_rmsqv(base + start, 1, &r, vDSP_Length(frame))
                out.append(toDB(r))
                start += hop
            }
        }
        return out
    }

    /// Centered moving average. Edges average over the values that exist.
    static func movingAverage(_ x: [Float], width: Int) -> [Float] {
        guard width > 1, !x.isEmpty else { return x }
        let half = width / 2
        // prefix[i] = sum of x[0..<i]
        var prefix = [Float](repeating: 0, count: x.count + 1)
        for i in 0..<x.count { prefix[i + 1] = prefix[i] + x[i] }
        var out = [Float](repeating: 0, count: x.count)
        for i in 0..<x.count {
            let lo = max(0, i - half)
            let hi = min(x.count - 1, i + half)
            out[i] = (prefix[hi + 1] - prefix[lo]) / Float(hi - lo + 1)
        }
        return out
    }

    /// p-th percentile (0...100) with linear interpolation between sorted values.
    static func percentile(_ x: [Float], _ p: Float) -> Float {
        guard !x.isEmpty else { return .nan }
        let sorted = x.sorted()
        let clamped = min(max(p, 0), 100)
        let position = clamped / 100 * Float(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = min(lower + 1, sorted.count - 1)
        let fraction = position - Float(lower)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction
    }

    /// Marks each frame as voiced when it is `margin` dB louder than the noise floor,
    /// then fills short unvoiced gaps (fewer than `minGap` frames, 100 ms by default)
    /// that sit between voiced frames, so one held "ahh" is not split by a tiny dip.
    static func voicedMask(_ db: [Float], noiseFloor: Float, margin: Float = 15, minGap: Int = 10) -> [Bool] {
        var mask = db.map { $0 > noiseFloor + margin }
        guard mask.count > 2 else { return mask }

        var i = 0
        while i < mask.count {
            if mask[i] { i += 1; continue }
            // Start of an unvoiced run.
            let start = i
            while i < mask.count && !mask[i] { i += 1 }
            let end = i // exclusive
            let length = end - start
            let hasVoiceBefore = start > 0
            let hasVoiceAfter = end < mask.count
            if hasVoiceBefore && hasVoiceAfter && length < minGap {
                for j in start..<end { mask[j] = true }
            }
        }
        return mask
    }

    /// Length (in frames) of the longest run of `true` values.
    static func longestTrueRun(_ mask: [Bool]) -> Int {
        var best = 0
        var current = 0
        for value in mask {
            current = value ? current + 1 : 0
            best = max(best, current)
        }
        return best
    }

    /// Converts a frame count to seconds for a given hop size.
    static func seconds(frames: Int, hop: Int = defaultHop, sampleRate: Double = sampleRate) -> Double {
        Double(frames * hop) / sampleRate
    }
}
