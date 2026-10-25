//
//  PlanContext.swift
//  Resonance
//
//  Builds the Next Steps engine's input from saved SwiftData objects.
//  Demo check-ins count as data, so the demo shows realistic next steps.
//

import Foundation

extension PlanContext {
    static func make(voice: [VoiceSession], motor: [MotorSession], checks: [FunctionCheck],
                     phrases: [Phrase], profile: Profile?, familyCount: Int = 0, now: Date = Date()) -> PlanContext {
        let records = InsightsBuilder.records(voice: voice, motor: motor, checks: checks)
        let voiceLabs = voice.filter { $0.kind != "breath" }.sorted { $0.date > $1.date }
        let breathSessions = voice.filter { $0.kind == "breath" || $0.metrics[MetricKey.breathCount] != nil }
            .sorted { $0.date > $1.date }
        let motors = motor.sorted { $0.date > $1.date }
        let fullChecks = checks.filter { $0.answers.count == 8 }.sorted { $0.date > $1.date }

        var c = PlanContext(now: now)
        c.lastVoiceLab = voiceLabs.first?.date
        c.lastBreathTest = breathSessions.first?.date
        c.lastMotorLab = motors.first?.date
        c.lastFunctionCheck = fullChecks.first?.date
        c.voiceLabCount = voiceLabs.count
        c.motorLabCount = motors.count
        c.insights = InsightsBuilder.insights(from: records)
        c.latestAnswers = fullChecks.first?.answers
        // Compare a real check only with an earlier real one (never with demo data), the same
        // rule the Function Check screen uses for its breathing warning.
        if let latest = fullChecks.first {
            c.previousAnswers = fullChecks.dropFirst().first(where: { $0.isDemo == latest.isDemo })?.answers
        }
        c.latestBreathCount = breathSessions.first?.metrics[MetricKey.breathCount]
        c.bankedPhrases = phrases.filter { $0.clip != nil }.count
        c.totalPhrases = phrases.count
        c.usesHeadControl = profile?.inputMode == "head" || profile?.inputMode == "scan"
        c.familyCount = familyCount
        let all = voice.map(\.isDemo) + motor.map(\.isDemo) + checks.map(\.isDemo)
        c.hasDemoDataOnly = !all.isEmpty && all.allSatisfy { $0 }
        return c
    }
}
