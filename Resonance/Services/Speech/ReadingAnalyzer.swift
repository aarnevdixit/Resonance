//
//  ReadingAnalyzer.swift
//  Resonance
//
//  Task C of the Voice Lab: turns the transcript of the reading passage into
//  speaking rate, syllable rate, pause time, word clarity and loudness
//  (PLAN.pdf Section 9). Pure Swift so it can be unit tested without audio.
//

import Foundation

/// The passage read aloud every week. It never changes, so weekly results are comparable.
/// (The plan suggests a Passage.txt resource; keeping it in code avoids a missing-file crash.)
enum ReadingPassage {
    static let text = """
    On Saturday morning my brother and I walked to the farmers market by the lake. \
    The air was cool, and the sky was a pale shade of blue. We bought peaches, fresh bread, \
    and a jar of honey for our grandmother. A man played a quiet tune on his guitar while \
    children chased a puppy around the fountain. Before we left, we shared a warm cinnamon \
    roll and talked about our plans for the week.
    """
}

/// One recognized word with its timing, in seconds from the start of the recording.
struct WordSegment: Equatable {
    var word: String
    var start: Double
    var duration: Double
    var end: Double { start + duration }
}

struct ReadingResult: Equatable {
    var transcript: String
    var wpm: Double?
    var sylPerSec: Double?
    var pauseRatio: Double?
    var intelligibility: Double
    var loudnessDb: Double?
    var missedWords: [String]
    var flags: [String]

    var metrics: [String: Double] {
        // With no speech heard, save nothing: a 0% would look like a huge real change in Trends.
        if flags.contains(QualityFlag.noSpeech) { return [:] }
        var m: [String: Double] = [MetricKey.intelligibility: intelligibility]
        if let wpm { m[MetricKey.wpm] = wpm }
        if let sylPerSec { m[MetricKey.sylPerSec] = sylPerSec }
        if let pauseRatio { m[MetricKey.pauseRatio] = pauseRatio }
        if let loudnessDb { m[MetricKey.loudnessDb] = loudnessDb }
        return m
    }
}

enum ReadingAnalyzer {
    static let pauseThreshold = 0.25   // seconds; shorter gaps are normal between words

    static func analyze(segments: [WordSegment], samples: [Float] = [],
                        passage: String = ReadingPassage.text) -> ReadingResult {
        let transcript = segments.map(\.word).joined(separator: " ")
        let alignment = TextAligner.align(reference: passage, hypothesis: transcript)
        let loudness = readingLoudness(samples)

        guard let first = segments.first, let last = segments.last, last.end > first.start else {
            return ReadingResult(transcript: transcript, wpm: nil, sylPerSec: nil, pauseRatio: nil,
                                 intelligibility: alignment.intelligibility, loudnessDb: loudness,
                                 missedWords: alignment.missedWords, flags: [QualityFlag.noSpeech])
        }

        let totalSeconds = last.end - first.start
        let words = segments.flatMap { TextAligner.normalize($0.word) }
        let wpm = Double(words.count) / totalSeconds * 60
        let sylPerSec = Double(SyllableCounter.count(words: words)) / totalSeconds

        var pauseSeconds = 0.0
        for (previous, next) in zip(segments, segments.dropFirst()) {
            let gap = next.start - previous.end
            if gap > pauseThreshold { pauseSeconds += gap }
        }
        let pauseRatio = pauseSeconds / totalSeconds * 100

        return ReadingResult(transcript: transcript, wpm: wpm, sylPerSec: sylPerSec,
                             pauseRatio: pauseRatio, intelligibility: alignment.intelligibility,
                             loudnessDb: loudness, missedWords: alignment.missedWords, flags: [])
    }

    /// Median loudness (dBFS) of the voiced frames while reading.
    static func readingLoudness(_ samples: [Float]) -> Double? {
        let frames = DSP.frameRMSdB(samples)
        guard !frames.isEmpty else { return nil }
        let floor = VoiceAnalyzer.estimateNoiseFloor(frames)
        let mask = DSP.voicedMask(frames, noiseFloor: floor)
        let voiced = zip(frames, mask).filter { $0.1 }.map { $0.0 }
        guard !voiced.isEmpty else { return nil }
        return Double(DSP.percentile(voiced, 50))
    }
}
