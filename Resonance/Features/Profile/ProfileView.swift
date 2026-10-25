//
//  ProfileView.swift
//  Resonance
//
//  Profile tab (PLAN.pdf Sections 5 and 15): name and settings, demo data,
//  and data and privacy controls.
//

import SwiftUI
import SwiftData

struct ProfileView: View {
    /// True when opened from the avatar button (shows a Done button).
    var isSheet = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [Profile]
    @Query private var voice: [VoiceSession]
    @Query private var motor: [MotorSession]
    @Query private var checks: [FunctionCheck]
    @State private var confirmDeleteAll = false
    @AppStorage("didOnboard") private var didOnboard = true

    private var hasDemoData: Bool {
        voice.contains(where: \.isDemo) || motor.contains(where: \.isDemo) || checks.contains(where: \.isDemo)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ProfileHeader(name: profiles.first?.name ?? "",
                                  checkIns: voice.filter { !$0.isDemo && $0.kind != "breath" }.count
                                      + motor.filter { !$0.isDemo }.count
                                      + checks.filter { !$0.isDemo }.count)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                if let profile = profiles.first {
                    ProfileSettingsSection(profile: profile)
                }

                Section {
                    NavigationLink {
                        ReportPreviewView()
                    } label: {
                        Label("Care Report (PDF)", systemImage: "doc.richtext.fill")
                            .frame(minHeight: AppTheme.minTapSize)
                    }
                    NavigationLink {
                        VoiceBankView()
                    } label: {
                        Label("Voice Bank", systemImage: "music.mic")
                            .frame(minHeight: AppTheme.minTapSize)
                    }
                } header: {
                    Text("Share and prepare")
                }

                Section {
                    Text("Resonance helps you track changes in speech and movement and communicate more easily. It does not diagnose ALS or any other condition, and it does not replace your care team. Phone measurements are estimates and can be affected by noise, posture and how you feel that day.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button {
                        // Close this sheet first, so the welcome screens can cover the whole app.
                        if isSheet {
                            dismiss()
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(600))
                                didOnboard = false
                            }
                        } else {
                            didOnboard = false
                        }
                    } label: {
                        Label("Show the welcome screens again", systemImage: "sparkles")
                            .frame(minHeight: AppTheme.minTapSize)
                    }
                } header: {
                    Text("About")
                }

                Section {
                    if hasDemoData {
                        Button("Remove demo data", role: .destructive) {
                            DemoDataSeeder.clear(in: modelContext)
                        }
                        .frame(minHeight: AppTheme.minTapSize)
                    } else {
                        Button("Load 12 weeks of demo data") {
                            DemoDataSeeder.seed(in: modelContext)
                        }
                        .frame(minHeight: AppTheme.minTapSize)
                    }
                } header: {
                    Text("Demo data")
                } footer: {
                    Text("Sample check-ins for showing how trends look over months. They are clearly labeled and never mixed into a real report without a warning.")
                }

                Section {
                    LabeledContent("Voice Lab check-ins", value: "\(voice.filter { !$0.isDemo && $0.kind != "breath" }.count)")
                    LabeledContent("Motor Lab check-ins", value: "\(motor.filter { !$0.isDemo }.count)")
                    LabeledContent("Function checks", value: "\(checks.filter { !$0.isDemo }.count)")
                    Button("Delete all my data", role: .destructive) {
                        confirmDeleteAll = true
                    }
                    .frame(minHeight: AppTheme.minTapSize)
                } header: {
                    Text("Data and privacy")
                } footer: {
                    Text("Everything stays on this iPhone. Nothing is uploaded.")
                }
            }
            .tint(AppTheme.accent)
            .scrollContentBackground(.hidden)
            .screenBackground()
            .navigationTitle("Profile")
            .toolbar {
                if isSheet {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }.fontWeight(.semibold)
                    }
                }
            }
            .onAppear(perform: ensureProfile)
            .confirmationDialog("Delete all check-ins, recordings, shared feelings, care reminders and questions? Your Voice Bank phrases and family contacts are kept. This can't be undone.",
                                isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive, action: deleteAll)
            }
        }
    }

    private func ensureProfile() {
        if profiles.isEmpty {
            modelContext.insert(Profile(name: "", role: "person", onsetType: "unsure"))
            try? modelContext.save()
        }
    }

    private func deleteAll() {
        // Deleted one by one: on iOS 17, screens don't refresh after a bulk delete.
        for item in (try? modelContext.fetch(FetchDescriptor<VoiceSession>())) ?? [] { modelContext.delete(item) }
        for item in (try? modelContext.fetch(FetchDescriptor<MotorSession>())) ?? [] { modelContext.delete(item) }
        for item in (try? modelContext.fetch(FetchDescriptor<FunctionCheck>())) ?? [] { modelContext.delete(item) }
        for item in (try? modelContext.fetch(FetchDescriptor<FeelingEntry>())) ?? [] { modelContext.delete(item) }
        for item in (try? modelContext.fetch(FetchDescriptor<CareQuestion>())) ?? [] { modelContext.delete(item) }
        // Care reminders: remove their notifications first, then the records.
        for reminder in (try? modelContext.fetch(FetchDescriptor<CareReminder>())) ?? [] {
            CareSchedule.remove(reminder)
            modelContext.delete(reminder)
        }
        try? modelContext.save()
        if let dir = try? AudioFiles.audioDirectory() {
            try? FileManager.default.removeItem(at: dir)
        }
    }
}

/// Initials avatar and a one-line summary at the top of Profile.
private struct ProfileHeader: View {
    let name: String
    let checkIns: Int

    private var initial: String {
        name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? ""
    }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(AppTheme.heroGradient)
                if initial.isEmpty {
                    Image(systemName: "person.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                } else {
                    Text(initial)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 68, height: 68)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(name.isEmpty ? "Welcome" : name)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                Text(checkIns == 1 ? "1 check-in on this iPhone" : "\(checkIns) check-ins on this iPhone")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

private struct ProfileSettingsSection: View {
    @Bindable var profile: Profile

    var body: some View {
        Section {
            TextField("Your first name", text: $profile.name)
                .frame(minHeight: AppTheme.minTapSize)
            Picker("How ALS started", selection: $profile.onsetType) {
                Text("Speech or swallowing (bulbar)").tag("bulbar")
                Text("Arms or legs (limb)").tag("limb")
                Text("Not sure").tag("unsure")
            }
            .frame(minHeight: AppTheme.minTapSize)
            Picker("Talk board control", selection: $profile.inputMode) {
                Text("Touch").tag("touch")
                Text("Head pointer").tag("head")
                Text("Switch scanning").tag("scan")
            }
            .frame(minHeight: AppTheme.minTapSize)
            NavigationLink {
                HeadControlSetupView()
            } label: {
                Label("Hands-free settings", systemImage: "figure.roll")
                    .frame(minHeight: AppTheme.minTapSize)
            }
            Toggle("Use my Personal Voice when available", isOn: $profile.preferPersonalVoice)
                .frame(minHeight: AppTheme.minTapSize)
        } header: {
            Text("You")
        }
    }
}

#Preview {
    ProfileView()
        .modelContainer(for: [Profile.self, VoiceSession.self, MotorSession.self, FunctionCheck.self], inMemory: true)
}
