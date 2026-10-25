//
//  VoiceAnalyzer.swift
//  Resonance
//
//  Turns Voice Lab recordings into numbers (PLAN.pdf Section 9).
//  - Task A, held "ahh": max phonation time, average pitch, pitch variation,
//    approximate jitter and shimmer.
//  - Task B, "pa-ta-ka": syllables per second and rhythm.
//  Plain Swift, no UI, so every function can be unit tested with synthetic audio.
//

import Foundation
import Accelerate

// MARK: - Results

struct VowelResult: Equatable {
    var mpt: Double             // seconds
    var f0Mean: Double?         // Hz
    var f0StdSemi: Double?      // semitones
    var jitter: Double?         // % (frame-level approximation)
    var shimmer: Double?        // % (frame-level approximation)
    var flags: [String]

    /// Metrics keyed for VoiceSession.metrics. Missing values are left out.
    var metrics: [String: Double] {
        // Under 0.3 s there was no real held vowel (silence or a click): save nothing rather than 0 s.
        guard mpt >= 0.3 else { return [:] }
        var m: [String: Double] = [MetricKey.mpt: mpt]
        if let f0Mean { m[MetricKey.f0Mean] = f0Mean }
        if let f0StdSemi { m[MetricKey.f0StdSemi] = f0StdSemi }
        if let jitter { m[MetricKey.jitter] = jitter }
        if let shimmer { m[MetricKey.shimmer] = shimmer }
        return m
    }
}

struct DDKResult: Equatable {
    var rate: Double?           // syllables per second
    var cv: Double?             // coefficient of variation of the gaps between syllables
    var peakTimes: [Double]     // seconds
    var flags: [String]

    var metrics: [String: Double] {
        var m: [String: Double] = [:]
        if let rate { m[MetricKey.ddkRate] = rate }
        if let cv { m[MetricKey.ddkCV] = cv }
        return m
    }
}

enum QualityFlag {
    static let tooNoisy = "too_noisy"
    static let tooShort = "too_short"
    static let noPitch = "no_pitch"
    static let tooFewSyllables = "too_few_syllables"
    static let noSpeech = "no_speech"
}

// MARK: - Analyzer

enum VoiceAnalyzer {

    /// Noise floor in dBFS: the 10th percentile of frame loudness.
    /// Capped at -50 dBFS so a recording with no silence at all still has a sensible floor.
    static func estimateNoiseFloor(_ frameDB: [Float]) -> Float {
        guard !frameDB.isEmpty else { return -60 }
        return min(DSP.percentile(frameDB, 10), -50)
    }

    /// The 1-second calibration recording counts as "too noisy" above -45 dBFS.
    static func isTooNoisy(calibrationSamples: [Float]) -> Bool {
        let frames = DSP.frameRMSdB(calibrationSamples)
        guard !frames.isEmpty else { return false }
        return DSP.percentile(frames, 10) > -45
    }

    // MARK: Task A: held vowel

    static func analyzeVowel(_ samples: [Float], noiseFloor: Float? = nil,
                             sampleRate: Double = DSP.sampleRate) -> VowelResult {
        let hop = DSP.defaultHop
        let frameDB = DSP.frameRMSdB(samples)
        guard !frameDB.isEmpty else {
            return VowelResult(mpt: 0, f0Mean: nil, f0StdSemi: nil, jitter: nil, shimmer: nil,
                               flags: [QualityFlag.tooShort])
        }

        let floor = noiseFloor ?? estimateNoiseFloor(frameDB)
        let mask = DSP.voicedMask(frameDB, noiseFloor: floor)

        // Longest continuous voiced run.
        var bestStart = 0, bestLength = 0, runStart = 0, runLength = 0
        for (i, voiced) in mask.enumerated() {
            if voiced {
                if runLength == 0 { runStart = i }
                runLength += 1
                if runLength > bestLength { bestLength = runLength; bestStart = runStart }
            } else {
                runLength = 0
            }
        }

        let mpt = DSP.seconds(frames: bestLength, hop: hop, sampleRate: sampleRate)
        var flags: [String] = []
        if mpt < 1 { flags.append(QualityFlag.tooShort) }
        guard bestLength > 0 else {
            return VowelResult(mpt: 0, f0Mean: nil, f0StdSemi: nil, jitter: nil, shimmer: nil, flags: flags)
        }

        // Analyze the middle 80% of the run (onset and offset are unstable).
        let trim = bestLength / 10
        let firstFrame = bestStart + trim
        let lastFrame = bestStart + bestLength - trim - 1
        // Cap the number of pitch frames to keep analysis fast on long vowels.
        let available = max(0, lastFrame - firstFrame + 1)
        let step = max(1, available / 300)

        var f0s: [Double] = []
        var amplitudes: [Float] = []
        var frameIndex = firstFrame
        while frameIndex <= lastFrame {
            let start = frameIndex * hop
            let end = start + PitchTracker.frameLength
            if end <= samples.count {
                let frame = Array(samples[start..<end])
                if let f0 = PitchTracker.pitch(of: frame, sampleRate: sampleRate) {
                    f0s.append(f0)
                    var peak: Float = 0
                    frame.withUnsafeBufferPointer { buf in
                        if let base = buf.baseAddress {
                            vDSP_maxmgv(base, 1, &peak, vDSP_Length(frame.count))
                        }
                    }
                    amplitudes.append(peak)
                }
            }
            frameIndex += step
        }

        // Reject octave errors: drop values more than 20% away from the median.
        let medianF0 = median(f0s)
        var keptF0: [Double] = []
        var keptAmp: [Float] = []
        if let medianF0 {
            for (f0, amp) in zip(f0s, amplitudes) where abs(f0 - medianF0) / medianF0 <= 0.2 {
                keptF0.append(f0)
                keptAmp.append(amp)
            }
        }

        guard keptF0.count >= 3 else {
            flags.append(QualityFlag.noPitch)
            return VowelResult(mpt: mpt, f0Mean: nil, f0StdSemi: nil, jitter: nil, shimmer: nil, flags: flags)
        }

        let f0Mean = keptF0.reduce(0, +) / Double(keptF0.count)
        let semitones = keptF0.map { 12 * log2($0 / f0Mean) }
        let f0StdSemi = standardDeviation(semitones)

        // Approximate jitter: average change in period between frames, as % of the mean period.
        let periods = keptF0.map { 1 / $0 }
        let jitter = meanAbsoluteDifference(periods) / mean(periods) * 100

        // Approximate shimmer: average change in peak amplitude between frames, as % of the mean.
        let amps = keptAmp.map(Double.init)
        let shimmer = mean(amps) > 0 ? meanAbsoluteDifference(amps) / mean(amps) * 100 : nil

        return VowelResult(mpt: mpt, f0Mean: f0Mean, f0StdSemi: f0StdSemi,
                           jitter: jitter, shimmer: shimmer, flags: flags)
    }

    // MARK: Task B: pa-ta-ka (DDK)

    static func analyzeDDK(_ samples: [Float], noiseFloor: Float? = nil,
                           sampleRate: Double = DSP.sampleRate) -> DDKResult {
        let frame = Int(sampleRate * 0.01)   // 10 ms frames, no overlap
        let raw = DSP.frameRMSdB(samples, frame: frame, hop: frame)
        let env = DSP.movingAverage(raw, width: 3)
        guard env.count > 3 else {
            return DDKResult(rate: nil, cv: nil, peakTimes: [], flags: [QualityFlag.tooFewSyllables])
        }

        // The calibration floor can be unrealistically low (digital silence), so never trust a floor
        // below -70 dBFS, and require syllables to be at least -50 dBFS: real speech at 30 cm is far
        // louder, while background hiss is not.
        let floor = max(noiseFloor ?? estimateNoiseFloor(env), -70)
        let minSyllableDB: Float = -50
        let skipFrames = 50                  // ignore the first 0.5 s
        let minSpacing = 7                   // at least 70 ms between syllables
        let minProminence: Float = 6         // dB above the lowest point since the last peak

        var peaks: [Int] = []
        var lowestSinceLastPeak = Float.greatestFiniteMagnitude
        var i = max(1, skipFrames)
        while i < env.count - 1 {
            lowestSinceLastPeak = min(lowestSinceLastPeak, env[i])
            let isLocalMax = env[i] > env[i - 1] && env[i] >= env[i + 1]
            let loudEnough = env[i] > max(floor + 10, minSyllableDB)
            let prominent = env[i] - lowestSinceLastPeak >= minProminence
            let spaced = peaks.last.map { i - $0 >= minSpacing } ?? true
            if isLocalMax && loudEnough && prominent && spaced {
                peaks.append(i)
                lowestSinceLastPeak = env[i]
            }
            i += 1
        }

        let times = peaks.map { Double($0 * frame) / sampleRate }
        guard times.count >= 8, let first = times.first, let last = times.last, last > first else {
            return DDKResult(rate: nil, cv: nil, peakTimes: times, flags: [QualityFlag.tooFewSyllables])
        }

        let rate = Double(times.count - 1) / (last - first)
        let intervals = zip(times.dropFirst(), times).map { $0 - $1 }
        let cv = mean(intervals) > 0 ? standardDeviation(intervals) / mean(intervals) : nil
        return DDKResult(rate: rate, cv: cv, peakTimes: times, flags: [])
    }

    // MARK: Small statistics helpers

    static func mean(_ x: [Double]) -> Double {
        x.isEmpty ? 0 : x.reduce(0, +) / Double(x.count)
    }

    static func median(_ x: [Double]) -> Double? {
        guard !x.isEmpty else { return nil }
        let s = x.sorted()
        let mid = s.count / 2
        return s.count % 2 == 0 ? (s[mid - 1] + s[mid]) / 2 : s[mid]
    }

    static func standardDeviation(_ x: [Double]) -> Double {
        guard x.count > 1 else { return 0 }
        let m = mean(x)
        let variance = x.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(x.count - 1)
        return sqrt(variance)
    }

    static func meanAbsoluteDifference(_ x: [Double]) -> Double {
        guard x.count > 1 else { return 0 }
        let diffs = zip(x.dropFirst(), x).map { abs($0 - $1) }
        return mean(diffs)
    }
}
