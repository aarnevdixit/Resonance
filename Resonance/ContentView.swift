//
//  ContentView.swift
//  Resonance
//
//  The app's root: five tabs (Today, Talk, Check-in, Trends, Family), plus onboarding on
//  first launch. Change from PLAN.pdf Section 5: Profile moved to an avatar button so
//  Family could have its own tab.
//  Note: the plan calls this file RootTabView.swift. Xcode's template created
//  ContentView.swift, so the RootTabView type lives here instead. You can rename the
//  file in Xcode at any time; nothing else depends on the file name.
//

import SwiftUI
import SwiftData

/// Tab identifiers. Stored in AppStorage so other screens (Today's quick tiles) can switch tabs.
/// Profile and settings open from the avatar button on Today and Family.
enum AppTab: Int {
    case today, talk, checkIn, trends, family
}

struct RootTabView: View {
    @AppStorage("didOnboard") private var didOnboard = false
    @AppStorage("selectedTab") private var selectedTab = AppTab.today.rawValue
    @Environment(\.modelContext) private var modelContext
    @State private var router = AppRouter.shared

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max.fill") }
                .tag(AppTab.today.rawValue)

            TalkBoardView()
                .tabItem { Label("Talk", systemImage: "bubble.left.and.bubble.right.fill") }
                .tag(AppTab.talk.rawValue)

            CheckInHubView()
                .tabItem { Label("Check-in", systemImage: "waveform.path.ecg") }
                .tag(AppTab.checkIn.rawValue)

            TrendsView()
                .tabItem { Label("Trends", systemImage: "chart.xyaxis.line") }
                .tag(AppTab.trends.rawValue)

            FamilyView()
                .tabItem { Label("Family", systemImage: "person.2.fill") }
                .tag(AppTab.family.rawValue)
        }
        .tint(AppTheme.accent)
        .onAppear {
            PhraseLibrary.seedIfNeeded(in: modelContext)
            DemoDataSeeder.refreshIfOutdated(in: modelContext)
        }
        .fullScreenCover(isPresented: Binding(get: { !didOnboard }, set: { _ in })) {
            OnboardingFlow { didOnboard = true }
        }
        // The alert started from a shortcut (Siri, Action button or Back Tap). It is shown on
        // top of whatever is open (a sheet, Profile, onboarding), so it can never be blocked.
        .onChange(of: router.showAlert) { _, show in presentShortcutAlert(show) }
        .onAppear { presentShortcutAlert(router.showAlert) }
    }
}

extension RootTabView {
    /// Tries on the next main-queue turn (the window may not be ready during a launch from
    /// Siri or Back Tap), and keeps trying briefly until the alert is on screen.
    private func presentShortcutAlert(_ show: Bool, attempt: Int = 0) {
        guard show else { return }
        let container = modelContext.container
        DispatchQueue.main.asyncAfter(deadline: .now() + (attempt == 0 ? 0.05 : 0.4)) {
            if AlertPresenter.present(container: container) {
                router.showAlert = false
            } else if attempt < 10 {
                presentShortcutAlert(true, attempt: attempt + 1)
            } else {
                // Give up for now, so the next shortcut run is noticed again.
                router.showAlert = false
            }
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: [
            Profile.self, VoiceSession.self, MotorSession.self,
            FunctionCheck.self, Phrase.self, BankedClip.self,
            CareContact.self, CareEvent.self, FeelingEntry.self, CareReminder.self, CareQuestion.self,
        ], inMemory: true)
}
