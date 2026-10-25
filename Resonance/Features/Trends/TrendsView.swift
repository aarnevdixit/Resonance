//
//  TrendsView.swift
//  Resonance
//
//  Trends tab (PLAN.pdf Sections 5 and 12): Function Index over time, then each
//  measurement compared with the person's own baseline.
//

import SwiftUI
import SwiftData
import Charts

struct TrendsView: View {
    @Query(sort: \VoiceSession.date) private var voice: [VoiceSession]
    @Query(sort: \MotorSession.date) private var motor: [MotorSession]
    @Query(sort: \FunctionCheck.date) private var checks: [FunctionCheck]
    @State private var domain: Domain = .speech

    private var records: [SessionRecord] {
        InsightsBuilder.records(voice: voice, motor: motor, checks: checks)
    }

    private var hasDemoData: Bool {
        voice.contains(where: \.isDemo) || motor.contains(where: \.isDemo) || checks.contains(where: \.isDemo)
    }

    var body: some View {
        let records = self.records
        let snapshot = InsightsBuilder.snapshot(from: records)

        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if hasDemoData { DemoBanner() }

                    if records.isEmpty {
                        Card {
                            Text("No check-ins yet").font(.title3.weight(.semibold))
                            Text("Complete a Voice Lab, Motor Lab or Function Check to start your trends. You can also turn on demo data in Profile.")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        FunctionIndexCard(snapshot: snapshot)

                        // Big buttons instead of a small segmented control (60 pt targets).
                        HStack(spacing: 8) {
                            ForEach([Domain.speech, .breathing, .motor, .daily], id: \.self) { d in
                                domainButton(d)
                            }
                        }

                        let shown = snapshot.insights.filter { $0.def.domain == domain }
                        if shown.isEmpty {
                            Text("No \(domainName(domain).lowercased()) measurements yet.")
                                .foregroundStyle(.secondary)
                                .padding()
                        }
                        ForEach(shown, id: \.def.key) { insight in
                            NavigationLink {
                                MetricDetailView(insight: insight,
                                                 points: InsightsBuilder.points(for: insight.def.key, in: records))
                            } label: {
                                MetricCard(insight: insight,
                                           points: InsightsBuilder.points(for: insight.def.key, in: records))
                            }
                            .buttonStyle(.plain)
                        }

                        NavigationLink {
                            ReportPreviewView()
                        } label: {
                            Label("Care Report", systemImage: "doc.text")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                }
                .padding(AppTheme.padding)
            }
            .screenBackground()
            .navigationTitle("Trends")
        }
    }

    private func domainButton(_ d: Domain) -> some View {
        let selected = domain == d
        let shape = RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous)
        let fill: Color = selected ? AppTheme.accent : AppTheme.surface
        let ink: Color = selected ? .white : AppTheme.ink
        return Button {
            withAnimation(.snappy) { domain = d }
        } label: {
            Text(d == .breathing ? "Breath" : domainName(d))
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: AppTheme.minTapSize)
                .foregroundStyle(ink)
                .background(fill, in: shape)
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func domainName(_ d: Domain) -> String {
        switch d {
        case .speech: return "Speech"
        case .breathing: return "Breathing"
        case .motor: return "Motor"
        case .daily: return "Daily"
        }
    }
}

// MARK: - Function Index

struct FunctionIndexCard: View {
    let snapshot: InsightsSnapshot

    private var indexSummary: String {
        let latest = Int((snapshot.history.last?.index ?? 0).rounded())
        return "Latest \(latest) out of 100, \(snapshot.history.count) check-ins"
    }

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Function Index")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                    Text("Compared with your own baseline")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let index = snapshot.functionIndex {
                    Text("\(Int(index.rounded()))")
                        .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(AppTheme.accent)
                }
            }
            if snapshot.history.count >= 2 {
                Chart(snapshot.history) { point in
                    AreaMark(x: .value("Date", point.date), y: .value("Index", point.index))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(LinearGradient(colors: [AppTheme.accent.opacity(0.28), AppTheme.accent.opacity(0.0)],
                                                        startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Date", point.date), y: .value("Index", point.index))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(AppTheme.accent)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                    PointMark(x: .value("Date", point.date), y: .value("Index", point.index))
                        .foregroundStyle(AppTheme.accent)
                        .symbolSize(28)
                }
                .chartYScale(domain: 0...100)
                .frame(height: 160)
                .accessibilityLabel("Function Index over time")
                .accessibilityValue(indexSummary)
            } else if snapshot.functionIndex == nil {
                Text("Building your baseline. The index appears after 3 check-ins.")
                    .foregroundStyle(.secondary)
            }
            Text("100 means at or better than your own baseline. Speech counts 40%, motor 35%, daily function 25%.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Metric card and detail

struct StatusBadge: View {
    let status: TrendStatus

    private var color: Color {
        switch status {
        case .buildingBaseline: return .gray
        case .stable: return AppTheme.mint
        case .noticeableChange: return AppTheme.warning
        case .improved: return AppTheme.blue
        }
    }

    var body: some View {
        Text(status.rawValue)
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.14))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

struct MetricCard: View {
    let insight: MetricInsight
    let points: [MetricPoint]

    var body: some View {
        Card {
            HStack {
                Text(insight.def.name)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                StatusBadge(status: insight.status)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(MetricFormat.value(insight.latest, def: insight.def))
                    .font(.system(.title, design: .rounded).weight(.bold).monospacedDigit())
                Text(insight.def.unit).foregroundStyle(.secondary)
                Spacer()
                if let change = InsightsEngine.changeText(insight) {
                    Text(change)
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if let note = InsightsEngine.singleCheckInNote(insight) {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            MetricChart(points: points, baseline: insight.baseline, noise: nil, height: 70)
        }
        .accessibilityElement(children: .combine)
    }
}

struct MetricChart: View {
    let points: [MetricPoint]
    let baseline: Double?
    let noise: Double?
    var height: CGFloat = 200

    var body: some View {
        Chart {
            if let baseline, let noise {
                RectangleMark(
                    xStart: .value("Start", points.first?.date ?? Date()),
                    xEnd: .value("End", points.last?.date ?? Date()),
                    yStart: .value("Low", baseline - 2 * noise),
                    yEnd: .value("High", baseline + 2 * noise)
                )
                .foregroundStyle(AppTheme.accent.opacity(0.12))
            }
            if let baseline {
                RuleMark(y: .value("Baseline", baseline))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.secondary)
            }
            ForEach(points, id: \.date) { p in
                LineMark(x: .value("Date", p.date), y: .value("Value", p.value))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(AppTheme.accent)
                    .lineStyle(StrokeStyle(lineWidth: height > 100 ? 3 : 2, lineCap: .round))
                PointMark(x: .value("Date", p.date), y: .value("Value", p.value))
                    .foregroundStyle(p.hasQualityFlag ? Color.gray : AppTheme.accent)
                    .symbol(p.hasQualityFlag ? .cross : .circle)   // shape as well as colour
                    .symbolSize(height > 100 ? 40 : 16)
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis(height > 100 ? .automatic : .hidden)
        .chartYAxis(height > 100 ? .automatic : .hidden)
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Chart of \(points.count) check-ins")
        .accessibilityValue(spokenSummary)
    }

    /// What VoiceOver says about the chart, e.g. "Latest 12.9, baseline 16.1".
    private var spokenSummary: String {
        guard let last = points.last else { return "No data" }
        var text = "Latest " + InsightsEngine.format(last.value)
        if let baseline { text += ", baseline " + InsightsEngine.format(baseline) }
        return text
    }
}

struct MetricDetailView: View {
    let insight: MetricInsight
    let points: [MetricPoint]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(MetricFormat.value(insight.latest, def: insight.def))
                        .font(.system(.largeTitle, design: .rounded).weight(.bold).monospacedDigit())
                    Text(insight.def.unit).foregroundStyle(.secondary)
                    Spacer()
                    StatusBadge(status: insight.status)
                }

                Card {
                    MetricChart(points: points, baseline: insight.baseline, noise: insight.noise, height: 240)
                    Text("Dashed line: your baseline. Shaded band: your normal range. Grey crosses: recordings with a quality warning.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Card {
                    if let baseline = insight.baseline {
                        row("Your baseline", "\(InsightsEngine.format(baseline)) \(insight.def.unit)")
                    }
                    if let noise = insight.noise {
                        row("Normal variation", "± \(InsightsEngine.format(2 * noise)) \(insight.def.unit)")
                    }
                    if let change = insight.changePct {
                        row("Compared with baseline", InsightsEngine.changeText(insight) ?? InsightsEngine.changePhrase(change))
                    }
                    if let note = InsightsEngine.singleCheckInNote(insight) {
                        Text(note + ". If the next check-in is also outside your normal range and the trend agrees, it will be flagged.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    row("Check-ins", "\(insight.sessionsSoFar)")
                    row("Better when", insight.def.higherIsBetter ? "higher" : "lower")
                }

                if insight.def.key == MetricKey.speechChangeScore {
                    Card {
                        Label("About this score", systemImage: "sparkles").font(.headline)
                        Text(SpeechChangeModel.explanation)
                            .foregroundStyle(.secondary)
                    }
                }

                Card {
                    Text("Why we say \"\(insight.status.rawValue.lowercased())\"").font(.headline)
                    Text(explanation)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(AppTheme.padding)
        }
        .screenBackground()
        .navigationTitle(insight.def.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var explanation: String {
        switch insight.status {
        case .buildingBaseline:
            return "Your baseline is the middle value of your first 3 check-ins. Until then there is nothing to compare with."
        case .stable:
            return "Everyone's measurements go up and down a little from week to week. The shaded band shows your normal range. A change is only flagged when your last two check-ins are both outside that band AND your recent trend would change the value by more than 10% over 4 weeks."
        case .noticeableChange:
            return "Your last two check-ins were both outside your normal range, and your recent trend is heading the same way. This measure has changed more than your usual day-to-day variation. It may be worth mentioning to your care team."
        case .improved:
            return "Your last two check-ins were both better than your normal range, and the recent trend is improving."
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).monospacedDigit().fontWeight(.semibold)
        }
        .accessibilityElement(children: .combine)
    }
}

struct DemoBanner: View {
    var body: some View {
        Label("Demo data: these are sample check-ins, not real measurements.", systemImage: "theatermasks.fill")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color(light: 0x8A5300, dark: 0xF2B661))
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.amber.opacity(0.16),
                        in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
    }
}

#Preview {
    TrendsView()
        .modelContainer(for: [VoiceSession.self, MotorSession.self, FunctionCheck.self], inMemory: true)
}
