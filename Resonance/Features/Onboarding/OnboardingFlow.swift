//
//  OnboardingFlow.swift
//  Resonance
//
//  First launch (PLAN.pdf Section 15): welcome, who is using the app, the
//  not-a-diagnosis consent, permissions explained one at a time, the person to call
//  for help, and a weekly reminder.
//

import SwiftUI
import SwiftData
import AVFAudio
import Speech

struct OnboardingFlow: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [Profile]
    let onFinish: () -> Void

    @State private var page = 0
    @State private var role = "person"
    @State private var name = ""
    @State private var micAllowed: Bool?
    @State private var speechAllowed: Bool?
    @State private var reminderDay = 2      // Monday
    @State private var reminderTime = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var reminderSet: Bool?
    @State private var familyName = ""
    @State private var familyPhone = ""
    @State private var familyRelation = ""

    private let pageCount = 6

    var body: some View {
        Group {
            if page == 0 {
                welcome
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Button { page -= 1 } label: {
                            Image(systemName: "chevron.left")
                                .font(.title3.weight(.semibold))
                                .frame(width: AppTheme.minTapSize, height: AppTheme.minTapSize)
                        }
                        .accessibilityLabel("Back")
                        ProgressView(value: Double(page), total: Double(pageCount - 1))
                            .tint(AppTheme.accent)
                            .accessibilityLabel("Step \(page) of \(pageCount - 1)")
                        Color.clear.frame(width: 24, height: 1)
                    }
                    .padding(.horizontal, 8)

                    ScrollView {
                        VStack(spacing: 20) {
                            switch page {
                            case 1: whoIsUsing
                            case 2: consent
                            case 3: permissions
                            case 4: family
                            default: reminder
                            }
                        }
                        .padding(24)
                    }
                }
                .screenBackground()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: page)
        .interactiveDismissDisabled()
        .onAppear {
            // Shown again from Profile: start from what is already saved.
            if let profile = profiles.first {
                if name.isEmpty { name = profile.name }
                if ["person", "caregiver", "demo"].contains(profile.role) { role = profile.role }
            }
        }
    }

    // MARK: Pages

    private var welcome: some View {
        ZStack {
            AppTheme.heroGradient.ignoresSafeArea()
            Circle()
                .fill(.white.opacity(0.06))
                .frame(width: 420, height: 420)
                .offset(x: 150, y: -300)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 24)
                WaveformMark(color: .white, barWidth: 7, spacing: 6)
                    .frame(width: 110, height: 64)
                Text("Resonance")
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.top, 22)
                Text("Keep talking in your own voice, stay close to family, and see how things change.")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 18) {
                    feature("bubble.left.and.bubble.right.fill", "Talk", "Say what you need instantly, in your own voice, by touch, head movement or one switch.")
                    feature("person.2.fill", "Family", "Send needs, messages and alerts to family's phones.")
                    feature("chart.xyaxis.line", "Measure", "Short weekly check-ins show how speech, breathing and hands are changing.")
                    feature("doc.text.fill", "Share", "A clear report for your care team.")
                }
                .padding(.top, 36)

                Spacer(minLength: 24)

                Button { page = 1 } label: {
                    Text("Get started")
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .foregroundStyle(AppTheme.violetDeep)
                        .frame(maxWidth: .infinity, minHeight: AppTheme.minTapSize)
                        .background(.white, in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
                }
                .buttonStyle(.plain)
                Text("Everything stays on this iPhone.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
            }
            .padding(28)
        }
    }

    private var whoIsUsing: some View {
        VStack(spacing: 16) {
            Text("Who is using Resonance?")
                .font(.system(.title, design: .rounded).weight(.bold))
            choice("I'm living with ALS", value: "person")
            choice("I'm a caregiver or family member", value: "caregiver")
            choice("I'm just exploring (I'll use demo data)", value: "demo")
            TextField(role == "caregiver" ? "Name of the person you care for" : "Your first name (optional)", text: $name)
                .textInputAutocapitalization(.words)
                .padding(14)
                .background(AppTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
            Button("Continue") { page = 2 }
                .buttonStyle(PrimaryButtonStyle())
        }
    }

    private var consent: some View {
        VStack(spacing: 20) {
            IconBadge(systemImage: "hand.raised.fill", size: 76)
            Text("Before you start")
                .font(.system(.title, design: .rounded).weight(.bold))
            Card {
                Text("Resonance helps you track changes in speech and movement and communicate more easily. It does not diagnose ALS or any other condition, and it does not replace your care team. Phone measurements are estimates and can be affected by noise, posture and how you feel that day.")
                    .font(.title3)
            }
            Card {
                Label("Everything stays on this iPhone. Nothing is uploaded; texts to family are sent only when you send them. You can delete it all at any time in Profile.", systemImage: "lock.fill")
            }
            Button("I understand") { page = 3 }
                .buttonStyle(PrimaryButtonStyle())
        }
    }

    private var permissions: some View {
        VStack(spacing: 16) {
            Text("Permissions")
                .font(.system(.title, design: .rounded).weight(.bold))
            Text("Resonance asks for each one only when you choose. You can change them later in Settings.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            permissionRow(icon: "mic.fill", title: "Microphone",
                          detail: "To measure your voice and record phrases in your own voice.",
                          state: micAllowed) {
                micAllowed = await AudioRecorder.requestPermission()
            }
            permissionRow(icon: "text.bubble.fill", title: "Speech recognition",
                          detail: "To measure reading speed and word clarity, on this iPhone.",
                          state: speechAllowed) {
                speechAllowed = await Transcriber.requestAuthorization()
            }
            Card {
                Label("Motion and camera are asked for the first time you use the Motor Lab or head control.", systemImage: "info.circle")
                    .font(.callout)
            }
            Button("Continue") { page = 4 }
                .buttonStyle(PrimaryButtonStyle())
        }
        .onAppear(perform: readPermissionStatus)
    }

    private var family: some View {
        VStack(spacing: 16) {
            IconBadge(systemImage: "person.2.fill", color: AppTheme.mint, size: 76)
            Text(role == "caregiver" ? "Who else helps?" : "Who helps you most?")
                .font(.system(.title, design: .rounded).weight(.bold))
            Text("They'll get your alerts and messages as texts, and you can call them with one tap from the Talk board. You can add more people later on the Family tab.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                ContactPicker.present { pickedName, phone in
                    familyName = pickedName
                    familyPhone = phone
                }
            } label: {
                Label("Choose from Contacts", systemImage: "person.crop.circle")
            }
            .buttonStyle(SecondaryButtonStyle())
            VStack(spacing: 0) {
                TextField("Name", text: $familyName)
                    .textInputAutocapitalization(.words)
                    .frame(minHeight: AppTheme.minTapSize)
                Divider()
                TextField("Phone number", text: $familyPhone)
                    .keyboardType(.phonePad)
                    .frame(minHeight: AppTheme.minTapSize)
                Divider()
                TextField("Who are they to you? (optional)", text: $familyRelation)
                    .textInputAutocapitalization(.words)
                    .frame(minHeight: AppTheme.minTapSize)
            }
            .font(.title3)
            .padding(.horizontal, AppTheme.padding)
            .surfaceStyle(radius: AppTheme.controlRadius)
            Button("Add and continue") {
                saveFamily()
                page = 5
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(familyName.trimmingCharacters(in: .whitespaces).isEmpty || !PhoneNumber.isValid(familyPhone))
            Button("Skip for now") { page = 5 }
                .font(.headline)
                .frame(minHeight: AppTheme.minTapSize)
        }
    }

    private func saveFamily() {
        let name = familyName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, PhoneNumber.isValid(familyPhone) else { return }
        let existing = (try? modelContext.fetch(FetchDescriptor<CareContact>())) ?? []
        guard !existing.contains(where: { $0.dialable == PhoneNumber.dialable(familyPhone) }) else { return }
        let contact = CareContact(name: name, phone: familyPhone.trimmingCharacters(in: .whitespaces),
                                  relation: familyRelation.trimmingCharacters(in: .whitespaces),
                                  isPrimary: existing.isEmpty)
        modelContext.insert(contact)
        try? modelContext.save()
    }

    /// Show a check (or a cross) for permissions that were already answered.
    private func readPermissionStatus() {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: micAllowed = true
        case .denied: micAllowed = false
        default: break
        }
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: speechAllowed = true
        case .denied, .restricted: speechAllowed = false
        default: break
        }
    }

    private var reminder: some View {
        VStack(spacing: 16) {
            IconBadge(systemImage: "bell.badge.fill", size: 76)
            Text("Weekly reminder")
                .font(.system(.title, design: .rounded).weight(.bold))
            Text("Check-ins work best on the same day and time each week.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            VStack(spacing: 0) {
                HStack {
                    Text("Day").font(.title3)
                    Spacer()
                    Picker("Day", selection: $reminderDay) {
                        ForEach(1...7, id: \.self) { d in
                            Text(Calendar.current.weekdaySymbols[d - 1]).tag(d)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(AppTheme.accent)
                }
                .frame(minHeight: AppTheme.minTapSize)
                Divider()
                DatePicker("Time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                    .font(.title3)
                    .tint(AppTheme.accent)
                    .frame(minHeight: AppTheme.minTapSize)
            }
            .padding(.horizontal, AppTheme.padding)
            .surfaceStyle(radius: AppTheme.controlRadius)
            Button("Remind me weekly") {
                Task {
                    let parts = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
                    reminderSet = await ReminderScheduler.scheduleWeekly(weekday: reminderDay,
                                                                         hour: parts.hour ?? 10,
                                                                         minute: parts.minute ?? 0)
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            if let reminderSet {
                Text(reminderSet ? "Reminder set." : "Notifications are off. You can turn them on in Settings.")
                    .foregroundStyle(reminderSet ? AppTheme.mint : AppTheme.warning)
            }
            Button("Finish") { finish() }
                .buttonStyle(PrimaryButtonStyle())
        }
    }

    // MARK: Pieces

    private func feature(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(.white)
                Text(detail).font(.callout).foregroundStyle(.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func choice(_ label: String, value: String) -> some View {
        Button { role = value } label: {
            HStack {
                Text(label).multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: role == value ? "checkmark.circle.fill" : "circle")
            }
            .font(.title3)
            .padding()
            .frame(maxWidth: .infinity, minHeight: AppTheme.minTapSize)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous)
                .stroke(role == value ? AppTheme.accent : Color.clear, lineWidth: 2.5))
            .foregroundStyle(role == value ? AppTheme.accent : AppTheme.ink)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(role == value ? .isSelected : [])
    }

    private func permissionRow(icon: String, title: String, detail: String, state: Bool?,
                               request: @escaping () async -> Void) -> some View {
        HStack(spacing: 12) {
            IconBadge(systemImage: icon, size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if state == true {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppTheme.mint)
                    .font(.title2)
                    .accessibilityLabel("Allowed")
            } else if state == false {
                // Denied: iOS won't ask again, so offer the way to fix it.
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                } label: {
                    Text("Settings")
                        .font(.headline)
                        .foregroundStyle(AppTheme.warning)
                        .frame(minWidth: 84, minHeight: AppTheme.minTapSize)
                        .background(AppTheme.warning.opacity(0.14),
                                    in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(title) is off. Open Settings to turn it on")
            } else {
                Button { Task { await request() } } label: {
                    Text("Allow")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(minWidth: 84, minHeight: AppTheme.minTapSize)
                        .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Allow \(title)")
            }
        }
        .padding()
        .surfaceStyle(radius: AppTheme.controlRadius)
    }

    // MARK: Finish

    private func finish() {
        let profile: Profile
        if let existing = profiles.first {
            profile = existing
        } else {
            profile = Profile(name: "", role: role, onsetType: "unsure")
            modelContext.insert(profile)
        }
        profile.role = role
        // Seeing the welcome screens again never erases a name that was already set.
        let typed = name.trimmingCharacters(in: .whitespaces)
        if !typed.isEmpty { profile.name = typed }
        if role == "demo" {
            DemoDataSeeder.seed(in: modelContext)
        }
        PhraseLibrary.seedIfNeeded(in: modelContext)
        try? modelContext.save()
        onFinish()
    }
}

#Preview {
    OnboardingFlow {}
        .modelContainer(for: [Profile.self, Phrase.self, VoiceSession.self, MotorSession.self, FunctionCheck.self], inMemory: true)
}
