//
//  TodayView.swift
//  Resonance
//
//  The Today tab (PLAN.pdf Section 5): a violet hero with the Function Index and this
//  week's summary, then the check-ins that are due and quick links.
//

import SwiftUI
import SwiftData

struct TodayView: View {
    @Query(sort: \VoiceSession.date, order: .reverse) private var voice: [VoiceSession]
    @Query(sort: \MotorSession.date, order: .reverse) private var motor: [MotorSession]
    @Query(sort: \FunctionCheck.date, order: .reverse) private var checks: [FunctionCheck]
    @Query private var profiles: [Profile]
    @AppStorage("selectedTab") private var selectedTab = AppTab.today.rawValue
    @State private var showProfile = false

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let part = hour < 12 ? "Good morning" : (hour < 17 ? "Good afternoon" : "Good evening")
        if let name = profiles.first?.name, !name.isEmpty { return "\(part), \(name)" }
        return part
    }

    private var hasDemoData: Bool {
        voice.contains(where: \.isDemo) || motor.contains(where: \.isDemo) || checks.contains(where: \.isDemo)
    }

    var body: some View {
        let records = InsightsBuilder.records(voice: voice, motor: motor, checks: checks)
        let snapshot = InsightsBuilder.snapshot(from: records)
        let week = WeeklyProgress(voice: voice, motor: motor, checks: checks)
        let checkDone = checks.contains { !$0.isDemo && Calendar.current.isDateInToday($0.date) }

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TodayHero(greeting: greeting,
                              date: Date(),
                              index: snapshot.functionIndex,
                              summary: snapshot.headline)

                    if hasDemoData { DemoBanner() }

                    let changed = snapshot.insights.filter { $0.status == .noticeableChange }
                    if !changed.isEmpty {
                        ChangesCard(insights: changed) { selectedTab = AppTab.trends.rawValue }
                    }

                    SectionTitle(text: "This week", trailing: "\(week.count) of 4 done")

                    NavigationLink { WeeklyCheckInView() } label: {
                        Label(week.isComplete ? "See your week" :
                                (week.count == 0 ? "Start this week's check-in" : "Continue this week's check-in"),
                              systemImage: week.isComplete ? "chart.bar.doc.horizontal" : "play.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityHint("Voice, breath, movement and daily questions, one after another.")

                    ForEach(WeeklyStep.allCases) { step in
                        NavigationLink { destination(step) } label: {
                            // Every row uses the same weekly rule as the "x of 4 done" count above.
                            DueRow(title: step.title,
                                   detail: step == .daily ? (checkDone ? "Done today" : "Daily, 30 seconds") : step.detail,
                                   systemImage: step.icon, color: step.color,
                                   done: week.done.contains(step))
                        }
                        .buttonStyle(.plain)
                    }

                    CareScheduleCard(hideWhenEmpty: true)
                        .padding(.top, 6)

                    NextStepsPanel()
                        .padding(.top, 6)

                    SectionTitle(text: "Shortcuts")

                    HStack(spacing: 12) {
                        Button { selectedTab = AppTab.talk.rawValue } label: {
                            QuickTile(title: "Talk", systemImage: "bubble.left.and.bubble.right.fill")
                        }
                        Button { selectedTab = AppTab.family.rawValue } label: {
                            QuickTile(title: "Family", systemImage: "person.2.fill")
                        }
                        NavigationLink { VoiceBankView() } label: {
                            QuickTile(title: "Voice Bank", systemImage: "music.mic")
                        }
                        NavigationLink { ReportPreviewView() } label: {
                            QuickTile(title: "Report", systemImage: "doc.richtext.fill")
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(AppTheme.padding)
            }
            .screenBackground()
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ProfileButton(name: profiles.first?.name ?? "") { showProfile = true }
                }
            }
            .sheet(isPresented: $showProfile) { ProfileView(isSheet: true) }
        }
    }
}

extension TodayView {
    @ViewBuilder
    func destination(_ step: WeeklyStep) -> some View {
        switch step {
        case .voice: VoiceLabFlowView()
        case .breath: BreathTestView()
        case .motor: MotorLabFlowView()
        case .daily: FunctionCheckView()
        }
    }
}

// MARK: - Hero

private struct TodayHero: View {
    let greeting: String
    let date: Date
    let index: Double?
    let summary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.75))
                    Text(greeting)
                        .font(.system(.title, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                WaveformMark(color: .white.opacity(0.55), barWidth: 4, spacing: 3)
                    .frame(width: 58, height: 34)
            }

            HStack(alignment: .center, spacing: 18) {
                IndexRing(value: index)
                VStack(alignment: .leading, spacing: 6) {
                    Text("This week")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(summary)
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack(alignment: .bottomTrailing) {
                AppTheme.heroGradient
                Circle()
                    .fill(.white.opacity(0.07))
                    .frame(width: 200, height: 200)
                    .offset(x: 70, y: 80)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.heroRadius, style: .continuous))
        .shadow(color: AppTheme.violetDeep.opacity(0.25), radius: 18, y: 10)
        .accessibilityElement(children: .combine)
    }
}

private struct IndexRing: View {
    let value: Double?

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.18), lineWidth: 11)
            Circle()
                .trim(from: 0, to: CGFloat((value ?? 0) / 100))
                .stroke(.white, style: StrokeStyle(lineWidth: 11, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: -2) {
                Text(value.map { "\(Int($0.rounded()))" } ?? "--")
                    .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                Text("Index")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .frame(width: 104, height: 104)
        .accessibilityElement()
        .accessibilityLabel("Function Index")
        .accessibilityValue(value.map { "\(Int($0.rounded())) out of 100" } ?? "not available yet")
    }
}

// MARK: - Changes to note

/// Lists measures flagged as a noticeable change, with the required wording (PLAN.pdf Section 21).
private struct ChangesCard: View {
    let insights: [MetricInsight]
    let openTrends: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                IconBadge(systemImage: "waveform.path.ecg", color: AppTheme.amber, size: 40)
                Text("Changes to note")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
            }
            ForEach(insights.prefix(4), id: \.def.key) { insight in
                HStack {
                    Text(insight.def.name)
                        .foregroundStyle(AppTheme.ink)
                    Spacer()
                    if let text = shortChange(insight) {
                        Text(text)
                            .font(.body.monospacedDigit().weight(.semibold))
                            .foregroundStyle(AppTheme.amber)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            if insights.count > 4 {
                Text("and \(insights.count - 4) more")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text("This measure has changed more than your usual day-to-day variation. It may be worth mentioning to your care team.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("See trends", action: openTrends)
                .buttonStyle(SecondaryButtonStyle(color: AppTheme.amber))
        }
        .padding(AppTheme.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceStyle()
    }
}

/// "28% worse", or "+33 points" for scores that are already 0-100.
private func shortChange(_ insight: MetricInsight) -> String? {
    if insight.def.unit == "/100", let baseline = insight.baseline {
        let diff = Int((insight.latest - baseline).rounded())
        return diff >= 0 ? "+\(diff) points" : "\(diff) points"
    }
    guard let change = insight.changePct else { return nil }
    let n = Int(abs(change).rounded())
    return change < 0 ? "\(n)% worse" : "\(n)% better"
}

// MARK: - Rows and tiles

private struct DueRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let color: Color
    let done: Bool

    var body: some View {
        HStack(spacing: 14) {
            IconBadge(systemImage: systemImage, color: color, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                Text(done ? "Done. Nice work." : detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if done {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(AppTheme.mint)
                    .accessibilityHidden(true)
            } else {
                Text("Start")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(color.opacity(0.12), in: Capsule())
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .surfaceStyle()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? "Done" : "Due")
    }
}

private struct QuickTile: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 10) {
            IconBadge(systemImage: systemImage, size: 46)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 104)
        .surfaceStyle()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    TodayView()
        .modelContainer(for: [VoiceSession.self, MotorSession.self, FunctionCheck.self, Profile.self], inMemory: true)
}
