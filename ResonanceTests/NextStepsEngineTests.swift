//
//  NextStepsEngineTests.swift
//  ResonanceTests
//
//  Every Next Steps rule, checked with small hand-made situations.
//

import Testing
import Foundation
@testable import Resonance

struct NextStepsEngineTests {

    let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// Someone fully up to date with nothing changed.
    func upToDate() -> PlanContext {
        var c = PlanContext(now: now)
        c.lastVoiceLab = now.addingTimeInterval(-86_400)
        c.lastBreathTest = now.addingTimeInterval(-86_400)
        c.lastMotorLab = now.addingTimeInterval(-86_400)
        c.lastFunctionCheck = now.addingTimeInterval(-3_600)
        c.voiceLabCount = 5
        c.motorLabCount = 5
        c.latestAnswers = Array(repeating: 4, count: 8)
        c.previousAnswers = Array(repeating: 4, count: 8)
        c.latestBreathCount = 35
        c.totalPhrases = 24
        c.bankedPhrases = 24
        c.familyCount = 1
        return c
    }

    func insight(_ key: String, _ status: TrendStatus) throws -> MetricInsight {
        let def = try #require(MetricDef.named(key))
        return MetricInsight(def: def, latest: 1, baseline: 1, noise: 0.1, changePct: -20, score: 80,
                             status: status, sessionsSoFar: 6)
    }

    @Test func allCaughtUpWhenNothingToDo() {
        let steps = NextStepsEngine.steps(for: upToDate())
        #expect(steps.map(\.id) == ["all-caught-up"])
    }

    @Test func lowBreathingAnswerIsUrgentAndFirst() {
        var c = upToDate()
        c.latestAnswers?[NextStepsEngine.qBreath] = 1
        let steps = NextStepsEngine.steps(for: c)
        #expect(steps.first?.id == "breathing-care-team")
        #expect(steps.first?.priority == .urgent)
        #expect(steps.first?.detail.contains("911") == true)
        // PLAN.pdf Section 11: the exact safety wording, not a paraphrase.
        #expect(steps.first?.detail.hasPrefix(BreathingSafety.message) == true)
    }

    @Test func lowBreathCountTriggersCareTeam() {
        var c = upToDate()
        c.latestBreathCount = 12
        #expect(NextStepsEngine.steps(for: c).first?.id == "breathing-care-team")
    }

    @Test func breathingDropOfTwoTriggersCareTeam() {
        var c = upToDate()
        c.previousAnswers?[NextStepsEngine.qBreath] = 4
        c.latestAnswers?[NextStepsEngine.qBreath] = 2
        #expect(NextStepsEngine.steps(for: c).contains { $0.id == "breathing-care-team" })
    }

    @Test func speechChangeSuggestsVoiceBankWithCounts() throws {
        var c = upToDate()
        c.bankedPhrases = 3
        c.insights = [try insight(MetricKey.intelligibility, .noticeableChange)]
        let steps = NextStepsEngine.steps(for: c)
        let bank = try #require(steps.first { $0.id == "bank-voice" })
        #expect(bank.detail.contains("3 of 24"))
        #expect(bank.destination == .voiceBank)
        #expect(steps.contains { $0.id == "practise-talk" })
    }

    @Test func handChangeSuggestsHeadControlUnlessAlreadyOn() throws {
        var c = upToDate()
        c.insights = [try insight(MetricKey.tapRateR, .noticeableChange)]
        #expect(NextStepsEngine.steps(for: c).contains { $0.destination == .headControl })
        c.usesHeadControl = true
        #expect(!NextStepsEngine.steps(for: c).contains { $0.destination == .headControl })
    }

    @Test func severalDueCheckInsBecomeOneWeeklyStep() {
        var c = upToDate()
        c.lastVoiceLab = now.addingTimeInterval(-8 * 86_400)
        c.lastMotorLab = now.addingTimeInterval(-9 * 86_400)
        let steps = NextStepsEngine.steps(for: c)
        #expect(steps.filter { $0.destination == .weeklyCheckIn }.count == 1)
        #expect(!steps.contains { $0.destination == .voiceLab })
    }

    @Test func newUserIsAskedToBuildBaseline() {
        let c = PlanContext(now: now)
        let step = NextStepsEngine.steps(for: c).first { $0.id == "weekly-check-in" }
        #expect(step?.title == "Build your baseline")
    }

    @Test func improvementIsCelebrated() throws {
        var c = upToDate()
        c.insights = [try insight(MetricKey.wpm, .improved)]
        #expect(NextStepsEngine.steps(for: c).contains { $0.priority == .celebrate && $0.title.contains("improved") })
    }

    @Test func noFamilySuggestsAddingSomeone() {
        var c = upToDate()
        c.familyCount = 0
        let step = NextStepsEngine.steps(for: c).first { $0.id == "add-family" }
        #expect(step?.destination == .family)
    }

    @Test func neverMentionsDiagnosis() throws {
        var c = PlanContext(now: now)
        c.latestAnswers = Array(repeating: 0, count: 8)
        c.insights = [try insight(MetricKey.intelligibility, .noticeableChange),
                      try insight(MetricKey.tapRateL, .noticeableChange)]
        for step in NextStepsEngine.steps(for: c, limit: 20) {
            let text = (step.title + " " + step.detail).lowercased()
            #expect(!text.contains("diagnos"))
            #expect(!text.contains("you have als"))
        }
    }

    @Test func limitIsRespected() throws {
        var c = PlanContext(now: now)
        c.latestAnswers = Array(repeating: 0, count: 8)
        c.totalPhrases = 10
        #expect(NextStepsEngine.steps(for: c, limit: 3).count == 3)
    }
}
