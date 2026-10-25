//
//  InsightsEngine.swift
//  Resonance
//
//  Compares each person to their own baseline, separates real change from normal
//  day-to-day variation, and produces scores, flags and a weekly summary
//  (PLAN.pdf Section 12). Pure Swift, no UI, no SwiftData, so it is fully unit tested.
//

import Foundation

/// One value of one metric on one date.
struct MetricPoint: Equatable {
    var date: Date
    var value: Double
    var hasQualityFlag: Bool = false
}

enum TrendStatus: String, Equatable {
    case buildingBaseline = "Building baseline"
    case stable = "Stable"
    case noticeableChange = "Noticeable change"
    case improved = "Improved"
}

struct MetricInsight: Equatable {
    var def: MetricDef
    var latest: Double
    var baseline: Double?
    var noise: Double?
    var changePct: Double?      // negative = worse, positive = better
    var score: Double?          // 0...100 (100 = at or better than baseline)
    var status: TrendStatus
    var sessionsSoFar: Int
}

enum InsightsEngine {
    static let baselineSessions = 3
    static let baselineDays = 14.0
    static let trendWindow = 6
    static let minTrendSessions = 4
    static let minNoiseFraction = 0.03     // noise is at least 3% of the baseline
    static let trendThresholdPct = 10.0    // % change projected over 4 weeks

    // MARK: Baseline

    /// Baseline points: the first 3 sessions, or every session in the first 14 days if there are more.
    static func baselinePoints(_ points: [MetricPoint]) -> [MetricPoint] {
        let sorted = points.sorted { $0.date < $1.date }
        guard let first = sorted.first else { return [] }
        let window = sorted.filter { $0.date.timeIntervalSince(first.date) <= baselineDays * 86_400 }
        return window.count > baselineSessions ? window : Array(sorted.prefix(baselineSessions))
    }

    /// Median of the baseline sessions; nil until there are enough sessions.
    static func baseline(_ points: [MetricPoint]) -> Double? {
        let base = baselinePoints(points)
        guard base.count >= baselineSessions else { return nil }
        return median(base.map(\.value))
    }

    /// Standard deviation of the baseline sessions, at least 3% of the baseline.
    static func noise(_ points: [MetricPoint]) -> Double? {
        guard let baseline = baseline(points) else { return nil }
        let base = baselinePoints(points).map(\.value)
        return max(standardDeviation(base), abs(baseline) * minNoiseFraction)
    }

    // MARK: Per-metric change

    /// Positive = better than baseline, negative = worse, in percent.
    static func changePct(current: Double, baseline: Double, higherIsBetter: Bool) -> Double {
        guard baseline != 0 else { return 0 }
        let direction = higherIsBetter ? 1.0 : -1.0
        return direction * (current - baseline) / abs(baseline) * 100
    }

    /// 100 when at or better than baseline, falling toward 0 as the metric worsens.
    static func metricScore(current: Double, baseline: Double, higherIsBetter: Bool) -> Double {
        guard baseline > 0, current > 0 else { return 0 }
        let ratio = higherIsBetter ? current / baseline : baseline / current
        return min(max(ratio, 0), 1) * 100
    }

    // MARK: Trend detection

    /// "Noticeable change" needs BOTH: the last 2 sessions worse than baseline by more than
    /// 2 x normal noise, AND a trend that projects to worse than 10% over 4 weeks.
    /// Sessions with quality flags are ignored for the first rule.
    static func status(for points: [MetricPoint], higherIsBetter: Bool) -> TrendStatus {
        let sorted = points.sorted { $0.date < $1.date }
        guard let baseline = baseline(sorted), let noise = noise(sorted) else { return .buildingBaseline }
        guard sorted.count >= minTrendSessions else { return .stable }

        let recent = Array(sorted.suffix(trendWindow))
        let lastTwo = Array(recent.suffix(2))
        guard lastTwo.count == 2, !lastTwo.contains(where: \.hasQualityFlag) else { return .stable }

        let direction = higherIsBetter ? 1.0 : -1.0
        let worseBy = lastTwo.map { direction * (baseline - $0.value) }   // positive = worse
        let bothWorse = worseBy.allSatisfy { $0 > 2 * noise }
        let bothBetter = worseBy.allSatisfy { -$0 > 2 * noise }

        guard let slope = slopePerDay(recent) else { return .stable }
        let projected4wk = direction * slope * 28 / abs(baseline) * 100   // positive = improving

        if bothWorse && projected4wk < -trendThresholdPct { return .noticeableChange }
        if bothBetter && projected4wk > trendThresholdPct { return .improved }
        return .stable
    }

    /// Least-squares slope of value against days.
    static func slopePerDay(_ points: [MetricPoint]) -> Double? {
        guard points.count >= 2, let t0 = points.first?.date else { return nil }
        let xs = points.map { $0.date.timeIntervalSince(t0) / 86_400 }
        let ys = points.map(\.value)
        let mx = mean(xs), my = mean(ys)
        let sxx = xs.reduce(0) { $0 + ($1 - mx) * ($1 - mx) }
        guard sxx > 0 else { return nil }
        let sxy = zip(xs, ys).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) }
        return sxy / sxx
    }

    // MARK: Insights for one metric

    static func insight(for def: MetricDef, points: [MetricPoint]) -> MetricInsight? {
        let sorted = points.sorted { $0.date < $1.date }
        guard let latest = sorted.last?.value else { return nil }
        let base = baseline(sorted)
        return MetricInsight(
            def: def,
            latest: latest,
            baseline: base,
            noise: noise(sorted),
            changePct: base.map { changePct(current: latest, baseline: $0, higherIsBetter: def.higherIsBetter) },
            score: base.map { metricScore(current: latest, baseline: $0, higherIsBetter: def.higherIsBetter) },
            status: status(for: sorted, higherIsBetter: def.higherIsBetter),
            sessionsSoFar: sorted.count
        )
    }

    // MARK: Domain scores and Function Index

    static let domainWeights: [Domain: Double] = [.speech: 0.40, .motor: 0.35, .daily: 0.25]

    /// Mean score of the index metrics in a domain; nil if none have a baseline yet.
    static func domainScore(_ insights: [MetricInsight], domain: Domain) -> Double? {
        let scores = insights.filter { $0.def.domain == domain && $0.def.inIndex }.compactMap(\.score)
        return scores.isEmpty ? nil : mean(scores)
    }

    /// Weighted mean of the available domain scores (weights renormalized when a domain is missing).
    static func functionIndex(domainScores: [Domain: Double]) -> Double? {
        var total = 0.0, weightSum = 0.0
        for (domain, score) in domainScores {
            let w = domainWeights[domain] ?? 0
            total += w * score
            weightSum += w
        }
        guard weightSum > 0 else { return nil }
        return min(100, total / weightSum)
    }

    // MARK: Weekly summary

    static func summary(_ insights: [MetricInsight]) -> String {
        guard !insights.isEmpty else {
            return "Complete a Voice Lab or Motor Lab check-in to start building your baseline."
        }
        let ready = insights.filter { $0.status != .buildingBaseline }
        if ready.isEmpty {
            let n = min(insights.map(\.sessionsSoFar).max() ?? 0, baselineSessions)
            return "Building your baseline: \(n) of \(baselineSessions) sessions. Keep checking in weekly."
        }

        var parts: [String] = []
        let headline = ready.filter { $0.def.inIndex }
        for insight in headline.prefix(4) {
            var text = "\(insight.def.name) \(format(insight.latest)) \(insight.def.unit)"
            if let change = insight.changePct {
                // "up/down" describes the number itself, not whether that is better or worse.
                let numberWentUp = insight.def.higherIsBetter ? change >= 0 : change <= 0
                text += " (\(numberWentUp ? "up" : "down") \(format(abs(change)))% from your baseline)"
            }
            parts.append(text)
        }
        var sentence = "This week: " + parts.joined(separator: "; ") + "."

        let changed = ready.filter { $0.status == .noticeableChange }
        let improved = ready.filter { $0.status == .improved }
        if changed.isEmpty && improved.isEmpty {
            sentence += " Everything is within your normal range."
        }
        for c in changed {
            sentence += " Noticeable change: \(c.def.name.lowercased()) has changed more than your usual day-to-day variation. It may be worth mentioning to your care team."
        }
        for i in improved {
            sentence += " \(i.def.name) has improved compared with your baseline."
        }
        return sentence
    }

    /// One short sentence for the Today hero. The full wording lives in `summary`.
    static func headline(_ insights: [MetricInsight]) -> String {
        guard !insights.isEmpty else { return "Do your first check-in to start your baseline." }
        let ready = insights.filter { $0.status != .buildingBaseline }
        if ready.isEmpty {
            let n = min(insights.map(\.sessionsSoFar).max() ?? 0, baselineSessions)
            return "Building your baseline: \(n) of \(baselineSessions) check-ins."
        }
        let changed = ready.filter { $0.status == .noticeableChange }.count
        let improved = ready.filter { $0.status == .improved }.count
        switch (changed, improved) {
        case (0, 0): return "Everything is within your normal range."
        case (0, _): return improved == 1 ? "1 measure has improved." : "\(improved) measures have improved."
        default:
            return changed == 1
                ? "1 measure changed more than usual."
                : "\(changed) measures changed more than usual."
        }
    }

    /// The change line shown on a metric card. Scores already on a 0-100 scale are compared in
    /// points (a percentage of a small baseline score would be misleading); everything else in %.
    static func changeText(_ insight: MetricInsight) -> String? {
        if insight.def.unit == "/100", let baseline = insight.baseline {
            let diff = Int((insight.latest - baseline).rounded())
            if diff == 0 { return "Same as baseline" }
            return "\(abs(diff)) points \(diff > 0 ? "higher" : "lower") than baseline"
        }
        return insight.changePct.map(changePhrase)
    }

    /// When the latest check-in alone is far from baseline but the measure is still "Stable"
    /// (one check-in is not a trend), say so, so "Stable" next to "20% worse" isn't confusing.
    static func singleCheckInNote(_ insight: MetricInsight) -> String? {
        guard insight.status == .stable, let change = insight.changePct, abs(change) >= 10 else { return nil }
        return "Latest check-in only, not a trend yet"
    }

    /// Plain words for a change score: "12% worse than baseline", "5% better than baseline",
    /// "Same as baseline". Positive change means better, whichever way the number moved.
    static func changePhrase(_ change: Double) -> String {
        let rounded = Int(abs(change).rounded())
        if rounded == 0 { return "Same as baseline" }
        return "\(rounded)% \(change > 0 ? "better" : "worse") than baseline"
    }

    // MARK: Helpers

    static func format(_ value: Double) -> String {
        abs(value) >= 100 ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }

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
        return sqrt(x.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(x.count - 1))
    }
}
