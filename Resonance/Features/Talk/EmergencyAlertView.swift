//
//  EmergencyAlertView.swift
//  Resonance
//
//  The Alert (PLAN.pdf Section 13): gets attention nearby until someone taps Stop.
//  - Repeats a loud spoken call for help, with a siren between calls.
//  - Flashes the screen and the iPhone's flashlight.
//  - Big buttons to call the first family member and text everyone who gets alerts.
//  It does NOT contact emergency services (exact wording from PLAN.pdf Section 21).
//  Opened by the Alert button, or by keeping the eyes closed (if that is turned on).
//

import SwiftUI
import SwiftData

struct EmergencyAlertView: View {
    /// Set when shown from a shortcut (a UIKit presentation); otherwise SwiftUI's dismiss is used.
    var onStop: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Query(sort: [SortDescriptor(\CareContact.createdAt)]) private var contacts: [CareContact]
    @Query private var profiles: [Profile]

    @State private var flash = false
    @State private var task: Task<Void, Never>?
    @State private var tone = AlarmTone()
    @State private var sendRequest: FamilySendRequest?
    @State private var callProblem = false
    @State private var started = Date()
    @State private var callTask: Task<Void, Never>?
    @State private var idleWasDisabled = false
    /// Whether this screen is counted in AlertPresenter.openCount (Stop and closing both call stopAll).
    @State private var counted = false

    private var primary: CareContact? { contacts.first(where: \.isPrimary) ?? contacts.first }
    private var alertContacts: [CareContact] { contacts.filter(\.receivesAlerts) }
    private var name: String { profiles.first?.name ?? "" }

    private var callText: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "I need help. Please come here." : "\(trimmed) needs help. Please come here."
    }

    var body: some View {
        ZStack {
            (flash ? AppTheme.coral : Color.white)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.4), value: flash)

            VStack(spacing: 18) {
                Spacer(minLength: 8)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 84))
                    .foregroundStyle(flash ? .white : AppTheme.coral)
                    .symbolEffect(.pulse)
                    .accessibilityHidden(true)
                Text("I need help.\nPlease come here.")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(flash ? .white : AppTheme.coral)
                    .minimumScaleFactor(0.7)
                TimelineView(.periodic(from: started, by: 1)) { context in
                    Text("Sounding for \(Self.elapsed(from: started, to: context.date))")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(flash ? Color.white.opacity(0.9) : Color.secondary)
                }
                // Exact wording from PLAN.pdf Section 21.
                Text("Plays a loud alert to get attention nearby. It does not contact emergency services.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(flash ? Color.white : Color.secondary)
                    .padding(.horizontal)

                Spacer(minLength: 8)

                familyButtons
                    .padding(.horizontal, 24)

                Button {
                    stopAll()
                    if let onStop { onStop() } else { dismiss() }
                } label: {
                    Text("Stop")
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 84)
                        .background(Color(hex: 0x1B1530), in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
                        .foregroundStyle(flash ? AppTheme.coral : .white)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
                .accessibilityLabel("Stop the alert")
            }
        }
        .familySender($sendRequest)
        .alert("Calling isn't available on this device", isPresented: $callProblem) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("On an iPhone, this calls \(primary?.name ?? "your family member"). iOS asks to confirm before dialing.")
        }
        // The alert is designed on white and coral; keep it readable when the phone is in Dark Mode.
        .environment(\.colorScheme, .light)
        .onAppear(perform: start)
        .onDisappear(perform: stopAll)
    }

    @ViewBuilder
    private var familyButtons: some View {
        if let primary {
            VStack(spacing: 10) {
                Button {
                    CallAction(openURL: openURL, context: modelContext).call(primary) { ok in
                        if !ok { callProblem = true }
                    }
                } label: {
                    Label("Call \(primary.name)", systemImage: "phone.fill")
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 72)
                        .background(AppTheme.mint, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
                }
                .accessibilityLabel("Call \(primary.name)")
                if !alertContacts.isEmpty {
                    Button {
                        sendRequest = FamilySendRequest(kind: .alert, body: CareMessage.alert(name: name, date: Date()),
                                                        contacts: alertContacts)
                    } label: {
                        Label(alertContacts.count == 1 ? "Text \(alertContacts[0].name)" : "Text all \(alertContacts.count) family members",
                              systemImage: "message.fill")
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                            .foregroundStyle(AppTheme.coral)
                            .frame(maxWidth: .infinity, minHeight: AppTheme.minTapSize)
                            .background(.white, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                                .stroke(AppTheme.coral.opacity(0.4), lineWidth: 2))
                    }
                }
            }
        } else {
            Text("Add family on the Family tab to call or text them from this screen.")
                .font(.callout.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(flash ? .white : AppTheme.ink)
        }
    }

    static func elapsed(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func start() {
        if !counted {
            counted = true
            AlertPresenter.openCount += 1
        }
        started = Date()
        modelContext.insert(CareEvent(kind: CareMessage.Kind.alert.rawValue,
                                      text: "Alert sounded on this iPhone", recipients: ""))
        try? modelContext.save()
        idleWasDisabled = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        if let profile = profiles.first, profile.alertShortcutEnabled,
           let url = AlertShortcut.url(name: profile.alertShortcutName,
                                       message: CareMessage.alert(name: name, date: Date())) {
            // Hands-free texts: run the person's "Resonance Alert" shortcut. Wait 2 seconds
            // first, so a mistaken alert can be stopped before anything is sent.
            callTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                openURL(url) { opened in
                    modelContext.insert(CareEvent(kind: CareMessage.Kind.alert.rawValue,
                                                  text: opened ? "Alert shortcut started (texts are sent by the Shortcuts app)"
                                                               : "Alert shortcut couldn't run (is it set up?)",
                                                  recipients: opened ? "Family (from the shortcut)" : ""))
                    try? modelContext.save()
                }
            }
        } else if profiles.first?.autoCallOnAlert == true, let primary {
            // Give the alert a moment to start first (and time to Stop a mistaken alert).
            // iOS then asks to confirm the call.
            callTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                CallAction(openURL: openURL, context: modelContext).call(primary)
            }
        }
        task = Task { @MainActor in
            while !Task.isCancelled {
                // Keep the screen on for as long as the alert runs, whatever closes underneath.
                UIApplication.shared.isIdleTimerDisabled = true
                SpeechOutput.shared.speak(callText, preferPersonalVoice: false, rate: 0.5)
                // About 3 seconds of speech, then 2 seconds of siren; flash twice a second throughout.
                for step in 0..<10 {
                    if Task.isCancelled { return }
                    if step == 6 { tone.play() }
                    flash.toggle()
                    Flashlight.set(flash)
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }
        }
    }

    private func stopAll() {
        task?.cancel()
        task = nil
        callTask?.cancel()
        callTask = nil
        if counted {
            counted = false
            AlertPresenter.openCount = max(0, AlertPresenter.openCount - 1)
        }
        SpeechOutput.shared.stop()
        tone.stop()
        Flashlight.set(false)
        UIApplication.shared.isIdleTimerDisabled = idleWasDisabled
    }
}

#Preview {
    EmergencyAlertView()
        .modelContainer(for: [CareContact.self, CareEvent.self, Profile.self], inMemory: true)
}
