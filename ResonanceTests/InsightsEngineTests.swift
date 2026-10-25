//
//  InsightsEngineTests.swift
//  ResonanceTests
//
//  Tests for InsightsEngine (task T10).
//

import Testing
import Foundation
@testable import Resonance

struct InsightsEngineTests {

    /// Weekly sessions starting on a fixed date.
    private func weekly(_ values: [Double], flags: Set<Int> = []) -> [MetricPoint] {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        return values.enumerated().map { i, v in
            MetricPoint(date: start.addingTimeInterval(Double(i) * 7 * 86_400), value: v,
                        hasQualityFlag: flags.contains(i))
        }
    }

    @Test func baselineIsMedianOfFirstThree() {
        #expect(InsightsEngine.baseline(weekly([150, 160, 140, 100])) == 150)
    }

    @Test func noBaselineBeforeThreeSessions() {
        #expect(InsightsEngine.baseline(weekly([150, 160])) == nil)
        #expect(InsightsEngine.status(for: weekly([150, 160]), higherIsBetter: true) == .buildingBaseline)
    }

    @Test func noiseHasAFloorOfThreePercent() throws {
        let noise = try #require(InsightsEngine.noise(weekly([100, 100, 100])))
        #expect(abs(noise - 3) < 0.0001)
    }

    @Test func flatDataIsStable() {
        let points = weekly([160, 158, 161, 159, 160, 158])
        #expect(InsightsEngine.status(for: points, higherIsBetter: true) == .stable)
    }

    @Test func steadyDeclineIsNoticeableChange() {
        // 3% of the starting value lost every week for 6 weeks.
        let points = weekly([100, 97, 94, 91, 88, 85])
        #expect(InsightsEngine.status(for: points, higherIsBetter: true) == .noticeableChange)
    }

    @Test func declineWhereLowerIsBetter() {
        // Pause time rising is a worsening for a lower-is-better metric.
        let points = weekly([10, 10.3, 10.6, 10.9, 11.2, 11.5])
        #expect(InsightsEngine.status(for: points, higherIsBetter: false) == .noticeableChange)
    }

    @Test func oneBadSessionIsIgnored() {
        let points = weekly([100, 100, 100, 100, 100, 80])
        #expect(InsightsEngine.status(for: points, higherIsBetter: true) == .stable)
    }

    @Test func flaggedRecentSessionIsNotFlagged() {
        let points = weekly([100, 97, 94, 91, 88, 85], flags: [5])
        #expect(InsightsEngine.status(for: points, higherIsBetter: true) == .stable)
    }

    @Test func improvementIsDetected() {
        let points = weekly([100, 103, 106, 109, 112, 115])
        #expect(InsightsEngine.status(for: points, higherIsBetter: true) == .improved)
    }

    @Test func changeAndScore() {
        #expect(abs(InsightsEngine.changePct(current: 90, baseline: 100, higherIsBetter: true) - (-10)) < 0.0001)
        #expect(abs(InsightsEngine.changePct(current: 110, baseline: 100, higherIsBetter: false) - (-10)) < 0.0001)
        #expect(InsightsEngine.metricScore(current: 120, baseline: 100, higherIsBetter: true) == 100)
        #expect(abs(InsightsEngine.metricScore(current: 80, baseline: 100, higherIsBetter: true) - 80) < 0.0001)
    }

    @Test func functionIndexRenormalizesWeights() throws {
        // Only speech (weight 0.40) and motor (0.35) present.
        let index = try #require(InsightsEngine.functionIndex(domainScores: [.speech: 80, .motor: 100]))
        let expected = (0.40 * 80 + 0.35 * 100) / 0.75
        #expect(abs(index - expected) < 0.0001)
        #expect(InsightsEngine.functionIndex(domainScores: [:]) == nil)
    }

    @Test func summaryMentionsBaselineWhileBuilding() throws {
        let def = try #require(MetricDef.named(MetricKey.wpm))
        let insight = try #require(InsightsEngine.insight(for: def, points: weekly([150])))
        #expect(InsightsEngine.summary([insight]).contains("Building your baseline"))
    }

    @Test func summaryNeverSaysDiagnosis() throws {
        let def = try #require(MetricDef.named(MetricKey.wpm))
        let insight = try #require(InsightsEngine.insight(for: def, points: weekly([100, 97, 94, 91, 88, 85])))
        let text = InsightsEngine.summary([insight]).lowercased()
        #expect(text.contains("care team"))
        #expect(!text.contains("diagnos"))
        #expect(!text.contains("als "))
    }

    @Test func headlineIsShortWhenThingsChange() throws {
        let def = try #require(MetricDef.named(MetricKey.wpm))
        let insight = try #require(InsightsEngine.insight(for: def, points: weekly([100, 97, 94, 91, 88, 85])))
        let text = InsightsEngine.headline([insight])
        #expect(text == "1 measure changed more than usual.")
        #expect(!text.lowercased().contains("diagnos"))
    }

    @Test func headlineWhileBuildingBaseline() throws {
        let def = try #require(MetricDef.named(MetricKey.wpm))
        let insight = try #require(InsightsEngine.insight(for: def, points: weekly([150])))
        #expect(InsightsEngine.headline([insight]) == "Building your baseline: 1 of 3 check-ins.")
    }

    @Test func singleCheckInNoteOnlyForLargeStableChanges() throws {
        let def = try #require(MetricDef.named(MetricKey.wpm))
        func make(_ status: TrendStatus, _ change: Double) -> MetricInsight {
            MetricInsight(def: def, latest: 1, baseline: 1, noise: 0.1, changePct: change, score: 80,
                          status: status, sessionsSoFar: 6)
        }
        #expect(InsightsEngine.singleCheckInNote(make(.stable, -20)) != nil)
        #expect(InsightsEngine.singleCheckInNote(make(.stable, 12)) != nil)
        #expect(InsightsEngine.singleCheckInNote(make(.stable, -4)) == nil)
        #expect(InsightsEngine.singleCheckInNote(make(.noticeableChange, -20)) == nil)
    }

    @Test func changePhraseSaysBetterOrWorse() {
        #expect(InsightsEngine.changePhrase(-22.4) == "22% worse than baseline")
        #expect(InsightsEngine.changePhrase(5) == "5% better than baseline")
        #expect(InsightsEngine.changePhrase(0.3) == "Same as baseline")
    }
}
