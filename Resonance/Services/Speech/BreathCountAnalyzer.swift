//
//  BreathCountAnalyzer.swift
//  Resonance
//
//  Breath test (count out loud on one breath).
//  1. Count: reads the numbers in the on-device transcript ("1 2 3", "one two three",
//     "twenty-one") and finds the longest run counting upward. The highest number in that
//     run is the score. Small recognizer slips (a skipped number) are tolerated.
//  2. Breath length: the longest stretch of speech, allowing the short gaps between
//     numbers (up to 0.4 s) but not a new breath (longer gaps).
//
//  Plain Swift, no UI, unit tested in BreathCountTests.
//

import Foundation

struct BreathResult: Equatable {
    var count: Int?           // highest number reached in one upward run
    var seconds: Double       // longest stretch of continuous speech
    var flags: [String]

    var metrics: [String: Double] {
        var m: [String: Double] = [:]
        if let count, count > 0 { m[MetricKey.breathCount] = Double(count) }
        if seconds >= 1 { m[MetricKey.breathSeconds] = seconds }
        return m
    }
}

enum BreathCountAnalyzer {

    static let units: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
        "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13,
        "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19,
        // Common recognizer spellings.
        "won": 1, "to": 2, "too": 2, "for": 4, "ate": 8,
    ]
    static let tens: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
        "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
    ]

    /// Numbers in the order they were said.
    static func numbers(in transcript: String) -> [Int] {
        let tokens = transcript.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        var out: [Int] = []
        var i = 0
        while i < tokens.count {
            let t = tokens[i]
            if let n = Int(t) {
                out.append(n)
            } else if let tensValue = tens[t] {
                if i + 1 < tokens.count, let u = units[tokens[i + 1]], (1...9).contains(u) {
                    out.append(tensValue + u)
                    i += 1
                } else {
                    out.append(tensValue)
                }
            } else if let u = units[t] {
                out.append(u)
            }
            i += 1
        }
        return out
    }

    /// Highest number in the longest upward run (each step +1, or +2 if the recognizer missed one).
    static func count(in transcript: String) -> Int? {
        let nums = numbers(in: transcript)
        guard !nums.isEmpty else { return nil }
        var bestLength = 0, bestTop = 0
        var runLength = 1, runTop = nums[0]
        if nums.count > 1 {
            for k in 1..<nums.count {
                let step = nums[k] - nums[k - 1]
                if step == 1 || step == 2 {
                    runLength += 1
                    runTop = nums[k]
                } else {
                    if runLength > bestLength { bestLength = runLength; bestTop = runTop }
                    runLength = 1
                    runTop = nums[k]
                }
            }
        }
        if runLength > bestLength { bestLength = runLength; bestTop = runTop }
        // A single isolated number is not a count.
        return bestLength >= 2 ? bestTop : nil
    }

    /// Longest continuous speech, allowing gaps under 0.4 s between numbers.
    static func breathSeconds(_ samples: [Float], noiseFloor: Float? = nil) -> Double {
        let db = DSP.frameRMSdB(samples)
        guard !db.isEmpty else { return 0 }
        let floor = max(noiseFloor ?? DSP.percentile(db, 10), -70)
        // Speech must also be clearly audible, not just above a very low floor.
        let mask = DSP.voicedMask(db, noiseFloor: max(floor, -65), margin: 15, minGap: 40)
        return DSP.seconds(frames: DSP.longestTrueRun(mask))
    }

    static func analyze(transcript: String?, samples: [Float], noiseFloor: Float? = nil) -> BreathResult {
        let seconds = breathSeconds(samples, noiseFloor: noiseFloor)
        let count = transcript.flatMap(count(in:))
        var flags: [String] = []
        if seconds < 1 { flags.append(QualityFlag.noSpeech) }
        return BreathResult(count: seconds < 1 ? nil : count, seconds: seconds, flags: flags)
    }
}
