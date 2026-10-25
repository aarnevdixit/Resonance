//
//  ResonanceApp.swift
//  Resonance
//
//  App entry point. Sets up SwiftData storage for every model in PLAN.pdf Section 8.
//

import SwiftUI
import SwiftData

@main
struct ResonanceApp: App {
    let modelContainer: ModelContainer = ResonanceApp.makeContainer()

    init() {
        // Reminder banners while the app is open, and the Done / Remind me later buttons.
        NotificationHandler.shared.install(container: modelContainer)
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .tint(AppTheme.accent)
        }
        .modelContainer(modelContainer)
    }

    /// All data stays on this iPhone (no CloudKit). If the on-disk store can't be opened,
    /// fall back to an in-memory store so the app still launches instead of crashing.
    static func makeContainer() -> ModelContainer {
        let schema = Schema([
            Profile.self,
            VoiceSession.self,
            MotorSession.self,
            FunctionCheck.self,
            Phrase.self,
            BankedClip.self,
            CareContact.self,
            CareEvent.self,
            FeelingEntry.self,
            CareReminder.self,
            CareQuestion.self,
        ])
        let disk = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        if let container = try? ModelContainer(for: schema, configurations: [disk]) {
            return container
        }
        let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: schema, configurations: [memory])
        } catch {
            fatalError("Could not create any ModelContainer: \(error)")
        }
    }
}
