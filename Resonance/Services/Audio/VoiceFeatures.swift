//
//  VoiceFeatures.swift
//  Resonance
//
//  The 10 voice features used by the Speech Change Score model (PLAN.pdf Section 9, task T21).
//
//  This is an exact port of Scripts/ml/features.py, the Python code the model was
//  trained with. Every frame size, threshold and step matches, so the trained model sees
//  the same numbers on the iPhone that it saw during training. VoiceFeaturesTests checks
//  the two against each other on a test signal.
//
//  All math is in Double, like NumPy, so results agree to many decimal places.
//

import Foundation
import Accelerate

struct VoiceFeatureVector: Equatable {
    /// Feature names in the order the model expects them.
    static let names = ["f0StdSemi", "jitter", "shimmer", "aperiodicity", "voicedRatio",
                        "f0Tremor", "ampTremor", "ampStdDb", "cpp", "spectralTilt"]

    var f0StdSemi: Double      // pitch variation (semitones)
    var jitter: Double         // frame-to-frame period change (%)
    var shimmer: Double        // frame-to-frame amplitude change (%)
    var aperiodicity: Double   // YIN dip at the chosen lag, 0 = perfectly periodic
    var voicedRatio: Double    // share of analyzed frames with a clear pitch
    var f0Tremor: Double       // share of pitch-contour power at 3-12 Hz
    var ampTremor: Double      // share of loudness-contour power at 3-12 Hz
    var ampStdDb: Double       // loudness steadiness (dB)
    var cpp: Double            // cepstral peak prominence (dB)
    var spectralTilt: Double   // energy below 1 kHz vs 1-4 kHz (dB)

    var values: [Double] {
        [f0StdSemi, jitter, shimmer, aperiodicity, voicedRatio,
         f0Tremor, ampTremor, ampStdDb, cpp, spectralTilt]
    }
}

enum VoiceFeatures {
    static let sampleRate = 44_100.0
    static let frameDB = 1102          // 25 ms
    static let hop = 441               // 10 ms
    static let pitchFrame = 1764       // 40 ms
    static let minLag = 110            // 400 Hz
    static let maxLag = 588            // 75 Hz
    static let yinThreshold = 0.15
    static let maxFrames = 600
    static let cppN = 2048
    static let cppFrames = 20
    /// The loud part of a real vowel is far above this (quietest training recording: about -38 dBFS).
    static let minLoudDB = -55.0

    // MARK: - Entry point

    /// Returns the features of a sustained vowel, or nil if there isn't enough clear voice.
    static func extract(_ input: [Float]) -> VoiceFeatureVector? {
        analyze(input)?.features
    }

    /// The features plus the level-normalized signal and the analysis frame starts
    /// (the formant tracker reuses the same frames, like features.py with return_frames=True).
    static func analyze(_ input: [Float]) -> (features: VoiceFeatureVector, signal: [Double], frameStarts: [Int])? {
        var x = input.map(Double.init)
        guard x.count >= pitchFrame else { return nil }

        // Level normalization: the loud part of the vowel (95th percentile frame) -> -20 dBFS.
        let db0 = frameRMSdB(x)
        // Near-silence is not a voice: refuse it rather than amplifying background hiss.
        guard percentile(db0, 95) > minLoudDB else { return nil }
        let gain = pow(10, (-20 - percentile(db0, 95)) / 20)
        guard gain.isFinite else { return nil }
        vDSP.multiply(gain, x, result: &x)

        let db = frameRMSdB(x)
        let floor = min(percentile(db, 10), -50)
        let mask = voicedMask(db, floor: floor)

        // Longest voiced run.
        var bestStart = 0, bestLen = 0, runStart = 0, runLen = 0
        for (i, v) in mask.enumerated() {
            if v {
                if runLen == 0 { runStart = i }
                runLen += 1
                if runLen > bestLen { bestLen = runLen; bestStart = runStart }
            } else {
                runLen = 0
            }
        }
        guard bestLen >= 30 else { return nil }

        let trim = bestLen / 10
        var first = bestStart + trim
        var last = bestStart + bestLen - trim - 1
        let available = last - first + 1
        if available > maxFrames {
            first += (available - maxFrames) / 2
            last = first + maxFrames - 1
        }

        var f0s: [Double] = [], aps: [Double] = [], amps: [Double] = [], dbs: [Double] = []
        var keptIdx: [Int] = []
        var analyzed = 0
        guard first <= last else { return nil }
        for i in first...last {
            let s = i * hop, e = s + pitchFrame
            if e > x.count { break }
            analyzed += 1
            let frame = Array(x[s..<e])
            if let pitch = yin(frame) {
                f0s.append(pitch.0)
                aps.append(pitch.1)
                amps.append(vDSP.maximumMagnitude(frame))
                dbs.append(toDB(rms(frame)))
                keptIdx.append(i)
            }
        }
        guard f0s.count >= 10, analyzed > 0 else { return nil }

        // Octave-error guard: keep frames within 20% of the median pitch.
        let med = median(f0s)
        var f0k: [Double] = [], apk: [Double] = [], ampk: [Double] = [], dbk: [Double] = []
        var idxk: [Int] = []
        for j in f0s.indices where abs(f0s[j] - med) / med <= 0.2 {
            f0k.append(f0s[j]); apk.append(aps[j]); ampk.append(amps[j])
            dbk.append(dbs[j]); idxk.append(keptIdx[j])
        }
        guard f0k.count >= 10 else { return nil }

        let meanF0 = mean(f0k)
        let semis = f0k.map { 12 * log2($0 / meanF0) }
        let periods = f0k.map { 1 / $0 }

        let jitter = mean(absDiff(periods)) / mean(periods) * 100
        let shimmer = mean(absDiff(ampk)) / mean(ampk) * 100

        // Cepstral features over up to 20 evenly spaced kept frames.
        let K = idxk.count
        let m = min(cppFrames, K)
        let sel: [Int] = m > 1 ? (0..<m).map { idxk[($0 * (K - 1)) / (m - 1)] } : [idxk[0]]
        let starts = sel.map { $0 * hop }
        let (cpp, tilt) = cppAndTilt(x, starts: starts)

        let vector = VoiceFeatureVector(
            f0StdSemi: std(semis),
            jitter: jitter,
            shimmer: shimmer,
            aperiodicity: mean(apk),
            voicedRatio: Double(f0k.count) / Double(analyzed),
            f0Tremor: bandRatio(semis, rate: 100),
            ampTremor: bandRatio(dbk, rate: 100),
            ampStdDb: std(dbk),
            cpp: cpp,
            spectralTilt: tilt
        )
        return (vector, x, starts)
    }

    // MARK: - Framing

    static func toDB(_ r: Double) -> Double { 20 * log10(r + 1e-9) }

    static func rms(_ v: [Double]) -> Double {
        guard !v.isEmpty else { return 0 }
        return sqrt(vDSP.sumOfSquares(v) / Double(v.count))
    }

    static func frameRMSdB(_ x: [Double]) -> [Double] {
        if x.count < frameDB { return [toDB(rms(x))] }
        let n = (x.count - frameDB) / hop + 1
        return x.withUnsafeBufferPointer { buf -> [Double] in
            guard let base = buf.baseAddress else { return [] }
            return (0..<n).map { i in
                var sum = 0.0
                vDSP_svesqD(base + i * hop, 1, &sum, vDSP_Length(frameDB))
                return toDB(sqrt(sum / Double(frameDB)))
            }
        }
    }

    /// Linear-interpolated percentile, same as NumPy's default.
    static func percentile(_ v: [Double], _ p: Double) -> Double {
        let s = v.sorted()
        guard !s.isEmpty else { return 0 }
        let pos = p / 100 * Double(s.count - 1)
        let lo = Int(pos.rounded(.down))
        let hi = min(lo + 1, s.count - 1)
        return s[lo] + (s[hi] - s[lo]) * (pos - Double(lo))
    }

    static func voicedMask(_ db: [Double], floor: Double, margin: Double = 15, minGap: Int = 10) -> [Bool] {
        var mask = db.map { $0 > floor + margin }
        var i = 0
        let n = mask.count
        while i < n {
            if mask[i] { i += 1; continue }
            let start = i
            while i < n && !mask[i] { i += 1 }
            if start > 0 && i < n && (i - start) < minGap {
                for k in start..<i { mask[k] = true }
            }
        }
        return mask
    }

    // MARK: - Pitch (YIN)

    /// Returns (F0 in Hz, aperiodicity at the chosen lag), or nil when not clearly voiced.
    static func yin(_ frame: [Double]) -> (Double, Double)? {
        guard rms(frame) > 1e-4 else { return nil }
        let w = frame.count - maxLag - 1
        guard w > 0 else { return nil }
        var d = [Double](repeating: 0, count: maxLag + 2)
        var scratch = [Double](repeating: 0, count: w)
        frame.withUnsafeBufferPointer { buf in
            guard let x = buf.baseAddress else { return }
            scratch.withUnsafeMutableBufferPointer { sbuf in
                guard let s = sbuf.baseAddress else { return }
                for tau in 1...(maxLag + 1) {
                    vDSP_vsubD(x, 1, x + tau, 1, s, 1, vDSP_Length(w))   // s = x[tau...] - x[0...]
                    var sum = 0.0
                    vDSP_svesqD(s, 1, &sum, vDSP_Length(w))
                    d[tau] = sum
                }
            }
        }
        var dp = [Double](repeating: 1, count: maxLag + 2)
        var running = 0.0
        for tau in 1...(maxLag + 1) {
            running += d[tau]
            dp[tau] = running > 0 ? d[tau] * Double(tau) / running : 1
        }

        var tau = minLag
        var found: Int?
        while tau <= maxLag {
            if dp[tau] < yinThreshold {
                while tau + 1 <= maxLag && dp[tau + 1] < dp[tau] { tau += 1 }
                found = tau
                break
            }
            tau += 1
        }
        guard let found else { return nil }

        var refined = Double(found)
        if found > 1 && found < maxLag + 1 {
            let a = dp[found - 1], b = dp[found], c = dp[found + 1]
            let den = a - 2 * b + c
            if abs(den) > 1e-12 {
                let shift = 0.5 * (a - c) / den
                if abs(shift) < 1 { refined += shift }
            }
        }
        let f0 = sampleRate / refined
        guard f0 >= 75, f0 <= 400 else { return nil }
        return (f0, dp[found])
    }

    // MARK: - Tremor

    /// Share of contour power between 3 and 12 Hz, out of 1-25 Hz, after removing a linear trend.
    static func bandRatio(_ series: [Double], rate: Double,
                          low: Double = 3, high: Double = 12,
                          totalLow: Double = 1, totalHigh: Double = 25) -> Double {
        let n = series.count
        guard n >= 32 else { return 0 }
        let t = (0..<n).map(Double.init)
        let tm = mean(t), sm = mean(series)
        var sxx = 0.0, sxy = 0.0
        for i in 0..<n {
            sxx += (t[i] - tm) * (t[i] - tm)
            sxy += (t[i] - tm) * (series[i] - sm)
        }
        let slope = sxx > 0 ? sxy / sxx : 0
        let resid = (0..<n).map { series[$0] - (sm + slope * (t[$0] - tm)) }

        var band = 0.0, total = 0.0
        for k in 1...(n / 2) {
            let f = Double(k) * rate / Double(n)
            guard f >= totalLow && f <= totalHigh else { continue }
            let w = 2 * Double.pi * Double(k) / Double(n)
            var re = 0.0, im = 0.0
            for i in 0..<n {
                re += resid[i] * cos(w * t[i])
                im -= resid[i] * sin(w * t[i])
            }
            let p = re * re + im * im
            total += p
            if f >= low && f <= high { band += p }
        }
        return total > 0 ? band / total : 0
    }

    // MARK: - Cepstral peak prominence and spectral tilt

    static func cppAndTilt(_ x: [Double], starts: [Int]) -> (Double, Double) {
        let n = cppN
        guard let setup = vDSP_DFT_zop_CreateSetupD(nil, vDSP_Length(n), .FORWARD) else { return (0, 0) }
        defer { vDSP_DFT_DestroySetupD(setup) }

        let window = (0..<n).map { 0.5 - 0.5 * cos(2 * Double.pi * Double($0) / Double(n)) }
        let fitLo = 44, fitHi = n / 2
        var cpps: [Double] = [], tilts: [Double] = []

        var re = [Double](repeating: 0, count: n), im = [Double](repeating: 0, count: n)
        var outRe = [Double](repeating: 0, count: n), outIm = [Double](repeating: 0, count: n)
        let zeros = [Double](repeating: 0, count: n)

        // Precompute the regression x-values for the cepstral baseline.
        let q = (fitLo...fitHi).map(Double.init)
        let qm = mean(q)
        let qss = q.reduce(0) { $0 + ($1 - qm) * ($1 - qm) }

        for s in starts {
            guard s >= 0, s + n <= x.count else { continue }
            // Spectrum of the windowed frame.
            for i in 0..<n { re[i] = x[s + i] * window[i] }
            vDSP_DFT_ExecuteD(setup, re, zeros, &outRe, &outIm)
            var power = [Double](repeating: 0, count: n)
            var logPower = [Double](repeating: 0, count: n)
            for k in 0..<n {
                power[k] = outRe[k] * outRe[k] + outIm[k] * outIm[k]
                logPower[k] = 10 * log10(power[k] + 1e-12)
            }
            // Cepstrum: real part of the DFT of the log spectrum, divided by N.
            for i in 0..<n { im[i] = 0 }
            vDSP_DFT_ExecuteD(setup, logPower, im, &outRe, &outIm)
            let c = outRe.map { $0 / Double(n) }

            var cm = 0.0
            for k in fitLo...fitHi { cm += c[k] }
            cm /= Double(fitHi - fitLo + 1)
            var sxy = 0.0
            for (j, k) in (fitLo...fitHi).enumerated() { sxy += (q[j] - qm) * (c[k] - cm) }
            let slope = sxy / qss

            var peakQ = minLag
            for k in minLag...maxLag where c[k] > c[peakQ] { peakQ = k }
            let line = cm + slope * (Double(peakQ) - qm)
            cpps.append(c[peakQ] - line)

            var lowP = 0.0, highP = 0.0
            for k in 0..<n {
                let f = Double(k) * sampleRate / Double(n)
                if f > 0 && f <= 1000 { lowP += power[k] }
                else if f > 1000 && f <= 4000 { highP += power[k] }
            }
            tilts.append(10 * log10((lowP + 1e-12) / (highP + 1e-12)))
        }
        guard !cpps.isEmpty else { return (0, 0) }
        return (mean(cpps), mean(tilts))
    }

    // MARK: - Small statistics helpers

    static func mean(_ v: [Double]) -> Double { v.isEmpty ? 0 : vDSP.mean(v) }

    /// Sample standard deviation (n - 1), like NumPy's std(ddof=1).
    static func std(_ v: [Double]) -> Double {
        guard v.count > 1 else { return 0 }
        let m = mean(v)
        return sqrt(v.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(v.count - 1))
    }

    /// Median; averages the two middle values for an even count, like NumPy.
    static func median(_ v: [Double]) -> Double {
        let s = v.sorted()
        guard !s.isEmpty else { return 0 }
        let mid = s.count / 2
        return s.count % 2 == 0 ? (s[mid - 1] + s[mid]) / 2 : s[mid]
    }

    static func absDiff(_ v: [Double]) -> [Double] {
        guard v.count > 1 else { return [] }
        return (1..<v.count).map { abs(v[$0] - v[$0 - 1]) }
    }
}
