//
//  CheckInHubView.swift
//  Resonance
//
//  The Check-in tab: start the Voice Lab, Motor Lab or Daily Function Check,
//  and see when each was last done (PLAN.pdf Section 5).
//

import SwiftUI
import SwiftData

struct CheckInHubView: View {
    @Query(sort: \VoiceSession.date, order: .reverse) private var voiceSessions: [VoiceSession]
    @Query(sort: \FunctionCheck.date, order: .reverse) private var functionChecks: [FunctionCheck]
    @Query(sort: \MotorSession.date, order: .reverse) private var motorSessions: [MotorSession]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Short, repeatable tasks. Resonance compares each one with your own baseline, never with other people.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 4)

                    NavigationLink {
                        WeeklyCheckInView()
                    } label: {
                        WeeklyCard(progress: WeeklyProgress(voice: voiceSessions, motor: motorSessions,
                                                            checks: functionChecks))
                    }
                    .buttonStyle(PressableStyle())

                    SectionTitle(text: "Or do one test")
                        .padding(.top, 4)

                    NavigationLink {
                        VoiceLabFlowView()
                    } label: {
                        CheckInCard(
                            title: "Voice Lab",
                            systemImage: "waveform",
                            color: AppTheme.violet,
                            detail: "Hold \"ahh\" and \"eee\", repeat \"pa-ta-ka\" and read a short passage.",
                            cadence: "Weekly, 3 min",
                            lastDone: voiceSessions.first(where: { !$0.isDemo && $0.kind != "breath" })?.date
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        BreathTestView()
                    } label: {
                        CheckInCard(
                            title: "Breath test",
                            systemImage: "wind",
                            color: AppTheme.blue,
                            detail: "Take a deep breath and count out loud as far as you can.",
                            cadence: "Weekly, 30 sec",
                            lastDone: voiceSessions.first(where: { !$0.isDemo && $0.kind == "breath" })?.date
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        MotorLabFlowView()
                    } label: {
                        CheckInCard(
                            title: "Motor Lab",
                            systemImage: "hand.tap.fill",
                            color: AppTheme.amber,
                            detail: "Tap two targets with each hand, trace a spiral, then hold the phone still.",
                            cadence: "Weekly, 2 min",
                            lastDone: motorSessions.first(where: { !$0.isDemo })?.date
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        FunctionCheckView()
                    } label: {
                        CheckInCard(
                            title: "Daily Function Check",
                            systemImage: "checklist",
                            color: AppTheme.mint,
                            detail: "Eight quick questions about speech, swallowing, movement and breathing.",
                            cadence: "Daily, 30 sec",
                            lastDone: functionChecks.first(where: { !$0.isDemo })?.date
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        MicrophoneTestView()
                    } label: {
                        Label("Test the microphone", systemImage: "mic.fill")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .padding(.top, 6)
                    .accessibilityHint("Record a short clip to check the microphone and level meter.")
                }
                .padding(AppTheme.padding)
            }
            .screenBackground()
            .navigationTitle("Check-in")
        }
    }
}

/// The guided weekly check-in, shown first on the hub.
private struct WeeklyCard: View {
    let progress: WeeklyProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Weekly check-in")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(progress.count) of 4")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.18), in: Capsule())
            }
            Text("Voice, breath, movement and daily questions in one guided session, about 6 minutes. Ends with a summary of your week and what to do next.")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                ForEach(WeeklyStep.allCases) { step in
                    let done = progress.done.contains(step)
                    Label(step.title, systemImage: done ? "checkmark.circle.fill" : step.icon)
                        .labelStyle(.iconOnly)
                        .font(.title3)
                        .foregroundStyle(done ? AppTheme.violetDeep : .white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(.white.opacity(done ? 0.95 : 0.16),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            Text(progress.isComplete ? "See your week" : (progress.count == 0 ? "Start" : "Continue"))
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(AppTheme.violetDeep)
                .frame(maxWidth: .infinity, minHeight: AppTheme.minTapSize)
                .background(.white, in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.heroGradient,
                    in: RoundedRectangle(cornerRadius: AppTheme.heroRadius, style: .continuous))
        .shadow(color: AppTheme.violetDeep.opacity(0.22), radius: 16, y: 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Weekly check-in, \(progress.count) of 4 steps done")
        .accessibilityAddTraits(.isButton)
    }
}

private struct CheckInCard: View {
    let title: String
    let systemImage: String
    let color: Color
    let detail: String
    let cadence: String
    let lastDone: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                IconBadge(systemImage: systemImage, color: color, size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(AppTheme.ink)
                    Text(cadence)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(color)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.headline)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack(spacing: 6) {
                Image(systemName: lastDone == nil ? "circle.dashed" : "clock.fill")
                    .accessibilityHidden(true)
                if let lastDone {
                    Text("Last done \(lastDone, format: .relative(presentation: .named))")
                } else {
                    Text("Not done yet")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(AppTheme.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceStyle()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    CheckInHubView()
        .modelContainer(for: [VoiceSession.self, FunctionCheck.self, MotorSession.self], inMemory: true)
}
