//
//  WeeklyCheckInView.swift
//  Resonance
//
//  One guided check-in for the week: Voice → Breath → Motor → Daily questions, in order.
//  Each step opens the full exercise; coming back ticks it off. When all four are done
//  it ends with "Your week": what changed and what to do next.
//

import SwiftUI
import SwiftData

/// The four parts of the weekly check-in.
enum WeeklyStep: Int, CaseIterable, Identifiable {
    case voice, breath, motor, daily
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .voice: return "Voice Lab"
        case .breath: return "Breath test"
        case .motor: return "Motor Lab"
        case .daily: return "Daily questions"
        }
    }
    var detail: String {
        switch self {
        case .voice: return "Hold \"ahh\" and \"eee\", say \"pa-ta-ka\", read a passage. About 3 minutes."
        case .breath: return "Count out loud on one breath. About 30 seconds."
        case .motor: return "Tap, trace a spiral and hold the phone still. About 2 minutes."
        case .daily: return "Eight quick questions about daily life. About 30 seconds."
        }
    }
    var icon: String {
        switch self {
        case .voice: return "waveform"
        case .breath: return "wind"
        case .motor: return "hand.tap.fill"
        case .daily: return "checklist"
        }
    }
    var color: Color {
        switch self {
        case .voice: return AppTheme.violet
        case .breath: return AppTheme.blue
        case .motor: return AppTheme.amber
        case .daily: return AppTheme.mint
        }
    }
}

/// Which steps are done this week (in the last 7 days; real check-ins only, not demo data).
struct WeeklyProgress {
    var done: Set<WeeklyStep>

    init(voice: [VoiceSession], motor: [MotorSession], checks: [FunctionCheck], now: Date = Date()) {
        func recent(_ date: Date) -> Bool { now.timeIntervalSince(date) < 7 * 86_400 }
        var done: Set<WeeklyStep> = []
        if voice.contains(where: { !$0.isDemo && $0.kind != "breath" && recent($0.date) }) { done.insert(.voice) }
        if voice.contains(where: { !$0.isDemo && $0.kind == "breath" && recent($0.date) }) { done.insert(.breath) }
        if motor.contains(where: { !$0.isDemo && recent($0.date) }) { done.insert(.motor) }
        if checks.contains(where: { !$0.isDemo && recent($0.date) }) { done.insert(.daily) }
        self.done = done
    }

    var count: Int { done.count }
    var next: WeeklyStep? { WeeklyStep.allCases.first { !done.contains($0) } }
    var isComplete: Bool { next == nil }
}

struct WeeklyCheckInView: View {
    @Query(sort: \VoiceSession.date, order: .reverse) private var voice: [VoiceSession]
    @Query(sort: \MotorSession.date, order: .reverse) private var motor: [MotorSession]
    @Query(sort: \FunctionCheck.date, order: .reverse) private var checks: [FunctionCheck]

    var body: some View {
        let progress = WeeklyProgress(voice: voice, motor: motor, checks: checks)

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(progress)

                ForEach(WeeklyStep.allCases) { step in
                    NavigationLink {
                        destination(step)
                    } label: {
                        StepRow(step: step, done: progress.done.contains(step),
                                isNext: progress.next == step)
                    }
                    .buttonStyle(PressableStyle())
                }

                if let next = progress.next {
                    NavigationLink {
                        destination(next)
                    } label: {
                        Label(progress.count == 0 ? "Start with the \(next.title)" : "Next: \(next.title)",
                              systemImage: "play.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 4)

                    Text("You can stop any time. Finished steps stay ticked for 7 days.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                } else {
                    YourWeekSummary(voice: voice, motor: motor, checks: checks)
                }
            }
            .padding(AppTheme.padding)
        }
        .screenBackground()
        .navigationTitle("Weekly check-in")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.easeInOut(duration: 0.25), value: progress.count)
    }

    private func header(_ progress: WeeklyProgress) -> some View {
        HStack(spacing: 18) {
            ZStack {
                Circle().stroke(.white.opacity(0.2), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: CGFloat(progress.count) / CGFloat(WeeklyStep.allCases.count))
                    .stroke(.white, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(progress.count)/4")
                    .font(.system(.title2, design: .rounded).weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
            }
            .frame(width: 88, height: 88)
            VStack(alignment: .leading, spacing: 6) {
                Text(progress.isComplete ? "This week is done" : "This week's check-in")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                Text(progress.isComplete
                     ? "Thank you. Your results are below, with what to do next."
                     : "Four short steps, about 6 minutes in all. Doing them the same way each week makes changes easy to see.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.heroGradient,
                    in: RoundedRectangle(cornerRadius: AppTheme.heroRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Weekly check-in, \(progress.count) of 4 steps done")
    }

    @ViewBuilder
    private func destination(_ step: WeeklyStep) -> some View {
        switch step {
        case .voice: VoiceLabFlowView()
        case .breath: BreathTestView()
        case .motor: MotorLabFlowView()
        case .daily: FunctionCheckView()
        }
    }
}

private struct StepRow: View {
    let step: WeeklyStep
    let done: Bool
    let isNext: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                IconBadge(systemImage: step.icon, color: step.color, size: 52)
                if done {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white, AppTheme.mint)
                        .offset(x: 20, y: 20)
                        .accessibilityHidden(true)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("\(step.rawValue + 1). \(step.title)")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                Text(done ? "Done this week" : step.detail)
                    .font(.subheadline)
                    .foregroundStyle(done ? AppTheme.mint : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.headline)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
        .surfaceStyle()
        .overlay {
            if isNext {
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                    .strokeBorder(step.color, lineWidth: 2)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? "Done" : (isNext ? "Next" : "To do"))
    }
}

/// "Your week": a summary of what changed and the next steps.
struct YourWeekSummary: View {
    let voice: [VoiceSession]
    let motor: [MotorSession]
    let checks: [FunctionCheck]

    var body: some View {
        let records = InsightsBuilder.records(voice: voice, motor: motor, checks: checks)
        let snapshot = InsightsBuilder.snapshot(from: records)
        let changed = snapshot.insights.filter { $0.status == .noticeableChange }
        let improved = snapshot.insights.filter { $0.status == .improved }
        let stable = snapshot.insights.filter { $0.status == .stable }

        VStack(alignment: .leading, spacing: 14) {
            Text("Your week")
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(AppTheme.ink)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 8)

            Card {
                HStack(alignment: .firstTextBaseline) {
                    Text("Function Index").font(.headline)
                    Spacer()
                    Text(snapshot.functionIndex.map { "\(Int($0.rounded()))" } ?? "--")
                        .font(.system(.title, design: .rounded).weight(.bold).monospacedDigit())
                        .foregroundStyle(AppTheme.accent)
                }
                Text(snapshot.headline)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    countPill("\(stable.count)", "steady", AppTheme.accent)
                    countPill("\(changed.count)", "changed", AppTheme.amber)
                    countPill("\(improved.count)", "better", AppTheme.mint)
                }
            }

            if !changed.isEmpty {
                Card {
                    Label("Changes to note", systemImage: "waveform.path.ecg")
                        .font(.headline)
                        .foregroundStyle(AppTheme.amber)
                    ForEach(changed.prefix(5), id: \.def.key) { insight in
                        HStack(alignment: .top) {
                            Text(insight.def.name).foregroundStyle(AppTheme.ink)
                            Spacer()
                            if let text = InsightsEngine.changeText(insight) {
                                Text(text)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.amber)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                    Text("This measure has changed more than your usual day-to-day variation. It may be worth mentioning to your care team.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            NextStepsPanel(subtitle: "Picked from this week's results")
        }
    }

    private func countPill(_ number: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(number)
                .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack { WeeklyCheckInView() }
        .modelContainer(for: [VoiceSession.self, MotorSession.self, FunctionCheck.self, Phrase.self, Profile.self], inMemory: true)
}
