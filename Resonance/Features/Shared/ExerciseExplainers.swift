//
//  ExerciseExplainers.swift
//  Resonance
//
//  The two pieces that connect every exercise to its purpose:
//  - WhyThisTestCard: shown before an exercise ("Why this test?").
//  - ResultInterpretationList: shown after it ("What this means"), comparing each
//    new value with the person's own baseline and saying what it measures.
//  Wording rule (PLAN.pdf Section 21): describe change, never diagnose.
//

import SwiftUI
import SwiftData

/// Collapsible "Why this test?" card for one exercise.
struct WhyThisTestCard: View {
    let exercise: Exercise
    var title = "Why this test?"
    var startExpanded = false
    @State private var expanded: Bool?

    private var isExpanded: Bool { expanded ?? startExpanded }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded = !isExpanded }
            } label: {
                HStack(spacing: 12) {
                    IconBadge(systemImage: "lightbulb.fill", color: AppTheme.amber, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(AppTheme.ink)
                        Text("Checks: \(exercise.tests)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .frame(minHeight: AppTheme.minTapSize)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("\(title) Checks \(exercise.tests)")
            .accessibilityHint(isExpanded ? "Hides the explanation" : "Shows the explanation")

            if isExpanded {
                Text(exercise.why)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !exercise.metricKeys.isEmpty {
                    Text("What it measures")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                        .padding(.top, 2)
                    ForEach(exercise.metricKeys, id: \.self) { key in
                        if let def = MetricDef.named(key), let text = Explanations.metric(key) {
                            HStack(alignment: .top, spacing: 8) {
                                Circle().fill(AppTheme.accent).frame(width: 6, height: 6).padding(.top, 7)
                                    .accessibilityHidden(true)
                                Text("**\(def.name):** \(text.measures)")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
        .padding(AppTheme.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceStyle()
    }
}

/// "What this means": each new value, how it compares with the person's baseline,
/// and what the measure shows. Reads saved history itself.
struct ResultInterpretationList: View {
    let latest: [String: Double]
    let keys: [String]
    var title = "What this means"

    @Query private var voice: [VoiceSession]
    @Query private var motor: [MotorSession]
    @Query private var checks: [FunctionCheck]

    var body: some View {
        let records = InsightsBuilder.records(voice: voice, motor: motor, checks: checks)
        let shown = keys.filter { latest[$0] != nil }

        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(AppTheme.ink)
                .accessibilityAddTraits(.isHeader)
            ForEach(shown, id: \.self) { key in
                if let def = MetricDef.named(key), let value = latest[key] {
                    let points = InsightsBuilder.points(for: key, in: records)
                    InterpretationRow(def: def, value: value,
                                      comparison: Self.comparison(def: def, value: value, points: points))
                }
            }
        }
    }

    /// Plain-words comparison with the baseline, and whether the change counts as worse.
    static func comparison(def: MetricDef, value: Double, points: [MetricPoint]) -> (text: String, worse: Bool?) {
        guard let baseline = InsightsEngine.baseline(points), baseline != 0 else {
            let left = max(InsightsEngine.baselineSessions - points.count, 0)
            return (left > 0
                    ? "Building your baseline: \(left) more test\(left == 1 ? "" : "s") until we can compare."
                    : "Building your baseline.", nil)
        }
        let change = InsightsEngine.changePct(current: value, baseline: baseline, higherIsBetter: def.higherIsBetter)
        let noise = InsightsEngine.noise(points) ?? 0
        let withinNoise = abs(value - baseline) <= max(noise, abs(baseline) * InsightsEngine.minNoiseFraction)
        let base = "\(MetricFormat.value(baseline, def: def)) \(def.unit)"
        if withinNoise { return ("Within your normal range (baseline \(base)).", nil) }
        // Very large percentages of a small baseline are confusing; say it in words instead.
        if abs(change) >= 100 {
            return ("\(change < 0 ? "Much worse" : "Much better") than your baseline (\(base)).", change < 0)
        }
        return (InsightsEngine.changePhrase(change) + " (baseline \(base)).", change < 0)
    }
}

private struct InterpretationRow: View {
    let def: MetricDef
    let value: Double
    let comparison: (text: String, worse: Bool?)

    private var color: Color {
        switch comparison.worse {
        case .some(true): return AppTheme.amber
        case .some(false): return AppTheme.mint
        case .none: return AppTheme.accent
        }
    }

    var body: some View {
        let explanation = Explanations.metric(def.key)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(def.name)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                Spacer(minLength: 8)
                Text(MetricFormat.value(value, def: def))
                    .font(.system(.title2, design: .rounded).weight(.bold).monospacedDigit())
                    .foregroundStyle(AppTheme.ink)
                Text(def.unit).font(.subheadline).foregroundStyle(.secondary)
            }
            Label(comparison.text, systemImage: comparison.worse == true ? "arrow.down.right.circle.fill"
                  : comparison.worse == false ? "arrow.up.right.circle.fill" : "circle.dashed")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
            if let explanation {
                Text(explanation.measures)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if comparison.worse == true {
                    // One result can vary from day to day, so this is framed as "if it continues".
                    Text("If this keeps happening over several check-ins: \(explanation.whenWorse.prefix(1).lowercased() + explanation.whenWorse.dropFirst())")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(AppTheme.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceStyle()
        .accessibilityElement(children: .combine)
    }
}

/// Number formatting that suits each measure: whole numbers for counts.
enum MetricFormat {
    static func value(_ value: Double, def: MetricDef) -> String {
        if def.unit == "numbers" { return String(Int(value.rounded())) }
        // Small values (rhythm CV, tremor ratio) need two decimals, or they all read "0.0".
        if value != 0 && abs(value) < 1 { return String(format: "%.2f", value) }
        return InsightsEngine.format(value)
    }
}
