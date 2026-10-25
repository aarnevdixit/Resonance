//
//  InsightsBuilder.swift
//  Resonance
//
//  Turns saved sessions into the inputs and outputs of the Insights Engine:
//  points per metric, current insights, domain scores and Function Index history.
//  Takes plain records (not SwiftData objects) so it can be unit tested.
//

import Foundation

/// A saved check-in reduced to what the Insights Engine needs.
struct SessionRecord: Equatable {
    var date: Date
    var metrics: [String: Double]
    var flagged: Bool
}

struct IndexPoint: Identifiable, Equatable {
    var date: Date
    var index: Double
    var id: Date { date }
}

struct InsightsSnapshot {
    var insights: [MetricInsight]
    var domainScores: [Domain: Double]
    var functionIndex: Double?
    var history: [IndexPoint]
    var summary: String

    static let empty = InsightsSnapshot(insights: [], domainScores: [:], functionIndex: nil,
                                        history: [], summary: InsightsEngine.summary([]))
}

enum InsightsBuilder {

    static func points(for key: String, in records: [SessionRecord]) -> [MetricPoint] {
        records
            .compactMap { r in r.metrics[key].map { MetricPoint(date: r.date, value: $0, hasQualityFlag: r.flagged) } }
            .sorted { $0.date < $1.date }
    }

    static func insights(from records: [SessionRecord]) -> [MetricInsight] {
        metricDefs.compactMap { def in
            InsightsEngine.insight(for: def, points: points(for: def.key, in: records))
        }
    }

    static func domainScores(_ insights: [MetricInsight]) -> [Domain: Double] {
        var scores: [Domain: Double] = [:]
        for domain in Domain.allCases {
            if let s = InsightsEngine.domainScore(insights, domain: domain) { scores[domain] = s }
        }
        return scores
    }

    /// Function Index after each check-in date, using only data up to that date.
    static func history(from records: [SessionRecord]) -> [IndexPoint] {
        let dates = Array(Set(records.map { Calendar.current.startOfDay(for: $0.date) })).sorted()
        return dates.compactMap { day in
            let cutoff = day.addingTimeInterval(86_400)
            let upTo = records.filter { $0.date < cutoff }
            let ins = insights(from: upTo)
            guard let index = InsightsEngine.functionIndex(domainScores: domainScores(ins)) else { return nil }
            return IndexPoint(date: day, index: index)
        }
    }

    static func snapshot(from records: [SessionRecord]) -> InsightsSnapshot {
        let ins = insights(from: records)
        let scores = domainScores(ins)
        return InsightsSnapshot(
            insights: ins,
            domainScores: scores,
            functionIndex: InsightsEngine.functionIndex(domainScores: scores),
            history: history(from: records),
            summary: InsightsEngine.summary(ins)
        )
    }

    // MARK: From SwiftData models

    static func records(voice: [VoiceSession], motor: [MotorSession], checks: [FunctionCheck]) -> [SessionRecord] {
        let v = voice.map { SessionRecord(date: $0.date, metrics: $0.metrics, flagged: !$0.qualityFlags.isEmpty) }
        let m = motor.map { SessionRecord(date: $0.date, metrics: $0.metrics, flagged: !$0.qualityFlags.isEmpty) }
        let f = checks.filter { $0.answers.count == 8 }.map {
            SessionRecord(date: $0.date, metrics: [MetricKey.functionTotal: Double($0.total)], flagged: false)
        }
        return v + m + f
    }
}

extension InsightsSnapshot {
    /// Short sentence for the Today hero.
    var headline: String { InsightsEngine.headline(insights) }
}
