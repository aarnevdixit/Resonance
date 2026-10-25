//
//  DemoDataSeeder.swift
//  Resonance
//
//  Creates 12 weeks of realistic SAMPLE data for the demo video (PLAN.pdf Section 15).
//  Speech measures decline from week 6 (3% a week), the breath count more slowly;
//  motor measures (tapping, spiral, steadiness) stay stable with noise.
//  Everything is marked isDemo = true, and the app shows a "Demo data" banner.
//

import Foundation
import SwiftData

enum DemoDataSeeder {

    static func seed(in context: ModelContext, weeks: Int = 12, now: Date = Date()) {
        clear(in: context)
        var rng = SeededGenerator(seed: 2026)

        func noise(_ sd: Double) -> Double {
            // Approximately normal noise (sum of uniforms), mean 1, standard deviation sd.
            let u = (0..<6).reduce(0.0) { acc, _ in acc + Double.random(in: -1...1, using: &rng) }
            return 1 + sd * u / 1.414
        }

        for w in 0..<weeks {
            let date = now.addingTimeInterval(-Double(weeks - 1 - w) * 7 * 86_400)
            // The plan suggested 1.2% a week; 3% a week makes the "noticeable change" flag appear
            // in the demo, so the video can show how flags work.
            let decline = w > 5 ? (1 - 0.03 * Double(w - 5)) : 1

            let voice = VoiceSession(date: date, metrics: [
                MetricKey.wpm: 165 * decline * noise(0.03),
                MetricKey.sylPerSec: 3.9 * decline * noise(0.03),
                MetricKey.ddkRate: 6.0 * decline * noise(0.03),
                MetricKey.ddkCV: 0.08 / decline * noise(0.05),
                MetricKey.mpt: 16 * decline * noise(0.03),
                MetricKey.intelligibility: min(100, 95 * (1 - (1 - decline) * 0.6) * noise(0.01)),
                MetricKey.pauseRatio: 12 / decline * noise(0.05),
                MetricKey.f0Mean: 190 * noise(0.02),
                MetricKey.f0StdSemi: 0.25 * noise(0.05),
                MetricKey.jitter: 0.6 / decline * noise(0.05),
                MetricKey.shimmer: 3.2 / decline * noise(0.05),
                MetricKey.loudnessDb: -28 * noise(0.02),
                MetricKey.cpp: 1.2 * decline * noise(0.04),
                MetricKey.f2Eee: 2.35 * (1 - (1 - decline) * 0.8) * noise(0.02),
                MetricKey.vowelSpace: 1.1 * (1 - (1 - decline) * 1.2) * noise(0.03),
                MetricKey.speechChangeScore: min(100, 22 + (1 - decline) * 160) * noise(0.06),
            ])
            voice.speechChangeScore = voice.metrics[MetricKey.speechChangeScore]
            voice.isDemo = true
            context.insert(voice)

            let motor = MotorSession(date: date.addingTimeInterval(600), metrics: [
                MetricKey.tapRateR: 5.5 * noise(0.04),
                MetricKey.tapRateL: 5.1 * noise(0.04),
                MetricKey.tapAccuracy: min(100, 97 * noise(0.01)),
                MetricKey.tapCV: 0.12 * noise(0.05),
                MetricKey.steadyRMS: 24 * noise(0.05),
                MetricKey.fatigueRatio: 1.1 * noise(0.04),
                MetricKey.tremorBand: 0.35 * noise(0.05),
                MetricKey.spiralError: 4.2 * noise(0.06),
                MetricKey.spiralSpeed: 160 * noise(0.05),
                MetricKey.spiralTremor: 0.04 * noise(0.08),
            ])
            motor.isDemo = true
            context.insert(motor)

            // Breath test: counting on one breath declines more slowly than speech (1.5% a week).
            let breathDecline = w > 5 ? (1 - 0.015 * Double(w - 5)) : 1
            let breath = VoiceSession(date: date.addingTimeInterval(300), metrics: [
                MetricKey.breathCount: (36 * breathDecline * noise(0.03)).rounded(),
                MetricKey.breathSeconds: 14.5 * breathDecline * noise(0.03),
            ])
            breath.kind = "breath"
            breath.isDemo = true
            context.insert(breath)

            var answers = [4, 4, 4, 4, 4, 4, 4, 3]
            if w >= 8 { answers[0] = 3 }   // speech answer drops from 4 to 3 at week 8
            let check = FunctionCheck(date: date.addingTimeInterval(1200), answers: answers, mood: 4)
            check.isDemo = true
            context.insert(check)
        }
        try? context.save()
    }

    /// Demo data made by an older version of the app lacks newer measurements (for example the
    /// "eee" formants). If so, replace it so every chart has data in the demo.
    static func refreshIfOutdated(in context: ModelContext) {
        let demo = (try? context.fetch(FetchDescriptor<VoiceSession>(predicate: #Predicate { $0.isDemo }))) ?? []
        guard !demo.isEmpty else { return }
        let hasFormants = demo.contains { $0.metrics[MetricKey.f2Eee] != nil }
        let hasBreath = demo.contains { $0.kind == "breath" }
        guard !hasFormants || !hasBreath else { return }
        clear(in: context)
        seed(in: context)
    }

    static func clear(in context: ModelContext) {
        // Deleted one by one: on iOS 17, screens don't refresh after a bulk delete.
        for item in (try? context.fetch(FetchDescriptor<VoiceSession>(predicate: #Predicate { $0.isDemo }))) ?? [] { context.delete(item) }
        for item in (try? context.fetch(FetchDescriptor<MotorSession>(predicate: #Predicate { $0.isDemo }))) ?? [] { context.delete(item) }
        for item in (try? context.fetch(FetchDescriptor<FunctionCheck>(predicate: #Predicate { $0.isDemo }))) ?? [] { context.delete(item) }
        try? context.save()
    }
}

/// Small deterministic random generator so the demo data looks the same every time.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
