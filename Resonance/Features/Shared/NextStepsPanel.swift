//
//  NextStepsPanel.swift
//  Resonance
//
//  "Your next steps": the cards that link every result to the feature that helps.
//  Reads saved data itself, so any screen can drop it in (Today, after each test,
//  the end of the weekly check-in).
//

import SwiftUI
import SwiftData

struct NextStepsPanel: View {
    var title = "Your next steps"
    var subtitle: String? = "Based on your latest check-ins"
    var limit = 4

    @Query private var voice: [VoiceSession]
    @Query private var motor: [MotorSession]
    @Query private var checks: [FunctionCheck]
    @Query private var phrases: [Phrase]
    @Query private var profiles: [Profile]
    @Query private var contacts: [CareContact]

    var body: some View {
        let context = PlanContext.make(voice: voice, motor: motor, checks: checks,
                                       phrases: phrases, profile: profiles.first, familyCount: contacts.count)
        let steps = NextStepsEngine.steps(for: context, limit: limit)

        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            ForEach(steps) { step in
                NextStepCard(step: step)
            }
        }
    }
}

struct NextStepCard: View {
    let step: NextStep
    @AppStorage("selectedTab") private var selectedTab = AppTab.today.rawValue

    private var color: Color {
        switch step.priority {
        case .urgent: return AppTheme.coral
        case .important: return AppTheme.amber
        case .suggested: return AppTheme.violet
        case .celebrate: return AppTheme.mint
        }
    }

    private var label: String {
        switch step.priority {
        case .urgent: return "Do soon"
        case .important: return "Recommended"
        case .suggested: return "Suggested"
        case .celebrate: return "Good news"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                IconBadge(systemImage: step.icon, color: color, size: 46)
                VStack(alignment: .leading, spacing: 4) {
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(color)
                    Text(step.title)
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(step.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let destination = step.destination {
                action(for: destination)
            }
        }
        .padding(AppTheme.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceStyle()
        .overlay(alignment: .leading) {
            // A thin colored edge shows priority at a glance.
            UnevenRoundedRectangle(topLeadingRadius: AppTheme.cornerRadius, bottomLeadingRadius: AppTheme.cornerRadius)
                .fill(color)
                .frame(width: 5)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func action(for destination: StepDestination) -> some View {
        switch destination {
        case .talkBoard:
            Button(step.actionLabel) { selectedTab = AppTab.talk.rawValue }
                .buttonStyle(SecondaryButtonStyle(color: color))
        case .trends:
            Button(step.actionLabel) { selectedTab = AppTab.trends.rawValue }
                .buttonStyle(SecondaryButtonStyle(color: color))
        case .family:
            Button(step.actionLabel) { selectedTab = AppTab.family.rawValue }
                .buttonStyle(SecondaryButtonStyle(color: color))
        default:
            NavigationLink {
                DestinationView(destination: destination)
            } label: {
                Text(step.actionLabel)
            }
            .buttonStyle(SecondaryButtonStyle(color: color))
        }
    }
}

/// The screen each next step opens.
struct DestinationView: View {
    let destination: StepDestination

    var body: some View {
        switch destination {
        case .weeklyCheckIn: WeeklyCheckInView()
        case .voiceLab: VoiceLabFlowView()
        case .breathTest: BreathTestView()
        case .motorLab: MotorLabFlowView()
        case .functionCheck: FunctionCheckView()
        case .voiceBank: VoiceBankView()
        case .headControl: HeadControlSetupView()
        case .careReport: ReportPreviewView()
        case .talkBoard, .trends, .family: EmptyView()   // handled by switching tabs
        }
    }
}
