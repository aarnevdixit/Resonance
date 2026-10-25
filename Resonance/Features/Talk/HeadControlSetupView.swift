//
//  HeadControlSetupView.swift
//  Resonance
//
//  Hands-free settings: choose how to use the Talk board as hand strength changes.
//  - Touch
//  - Head pointer: point with small head movements, hold still to choose (Face ID camera).
//  - Switch scanning: buttons light up in turn; choose with a tap anywhere, a Bluetooth
//    switch, or a long blink.
//  Also the eyes-closed alert, and how fast the computer voice speaks.
//  Reached from the Talk board menu, Profile, and a Next Step when hand measures change.
//

import SwiftUI
import SwiftData

struct HeadControlSetupView: View {
    var isSheet = false

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [Profile]
    @AppStorage("selectedTab") private var selectedTab = AppTab.today.rawValue

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if let profile = profiles.first {
                    HandsFreeSettings(profile: profile)
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }

                Button {
                    selectedTab = AppTab.talk.rawValue
                    if isSheet { dismiss() }
                } label: {
                    Label("Open the Talk board", systemImage: "bubble.left.and.bubble.right.fill")
                }
                .buttonStyle(PrimaryButtonStyle())

                Text("The camera image is never saved or sent anywhere. Only the direction of your head and whether your eyes are open are used.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
            .padding(AppTheme.padding)
        }
        .screenBackground()
        .navigationTitle("Hands-free")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isSheet {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            if profiles.isEmpty {
                modelContext.insert(Profile(name: "", role: "person", onsetType: "unsure"))
                try? modelContext.save()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            IconBadge(systemImage: "figure.roll", size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text("Keep talking as your hands change")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Choose what works best today. You can switch any time from the Talk board's menu.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct HandsFreeSettings: View {
    @Bindable var profile: Profile
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ModeCard(selected: profile.inputMode == "touch", icon: "hand.point.up.fill", color: AppTheme.accent,
                     title: "Touch", detail: "Tap the buttons. Big targets, nothing to set up.") { set("touch") }

            ModeCard(selected: profile.inputMode == "head", icon: "face.smiling", color: AppTheme.blue,
                     title: "Head pointer",
                     detail: "Point your nose at a button and hold still. Needs an iPhone with Face ID, on a stand at face height.") { set("head") }

            ModeCard(selected: profile.inputMode == "scan", icon: "rectangle.and.hand.point.up.left.filled", color: AppTheme.amber,
                     title: "Switch scanning",
                     detail: "Rows light up one after another. Choose with one movement: a tap anywhere, a Bluetooth switch, or a long blink.") { set("scan") }

            if profile.inputMode == "head" { headSettings }
            if profile.inputMode == "scan" { scanSettings }

            alertSettings
            shortcutSettings
            voiceSettings
        }
        .animation(.easeInOut(duration: 0.2), value: profile.inputMode)
    }

    private var headSettings: some View {
        Card {
            Label("Head pointer", systemImage: "face.smiling")
                .font(.headline)
                .foregroundStyle(AppTheme.blue)
            step(1, "Prop the phone up", "On a stand or table at face height, about an arm's length away.")
            step(2, "Calibrate once", "On the Talk board, point your nose at 5 dots. About 10 seconds.")
            step(3, "Look and hold", "A ring fills while you hold still on a button, then it speaks.")
            VStack(alignment: .leading, spacing: 4) {
                Text("Hold still for \(profile.dwellSeconds, specifier: "%.1f") seconds to choose")
                    .font(.subheadline.weight(.semibold))
                Slider(value: $profile.dwellSeconds, in: 0.6...3.0, step: 0.1)
                    .accessibilityLabel("Dwell time")
                    .accessibilityValue("\(profile.dwellSeconds, specifier: "%.1f") seconds")
            }
            Toggle("Or choose with a long blink", isOn: $profile.blinkToSelect)
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: AppTheme.minTapSize)
            if !FaceTracker.isSupported {
                Label("This device has no Face ID camera, so the head pointer can't run here. Touch still works.",
                      systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.warning)
            }
        }
    }

    private var scanSettings: some View {
        Card {
            Label("Switch scanning", systemImage: "rectangle.and.hand.point.up.left.filled")
                .font(.headline)
                .foregroundStyle(AppTheme.amber)
            step(1, "A row lights up", "Rows of buttons light up in turn, starting with Yes, No, Pain and Wait.")
            step(2, "Choose the row", "Press your switch when the row you want is lit. Its buttons then light up one at a time.")
            step(3, "Choose the button", "Press again to say it. Scanning starts again from the top.")
            VStack(alignment: .leading, spacing: 4) {
                Text("Move every \(profile.scanSeconds, specifier: "%.1f") seconds")
                    .font(.subheadline.weight(.semibold))
                Slider(value: $profile.scanSeconds, in: 0.8...4.0, step: 0.1)
                    .accessibilityLabel("Scan speed")
                    .accessibilityValue("\(profile.scanSeconds, specifier: "%.1f") seconds per item")
            }
            Toggle("Choose with a long blink", isOn: $profile.blinkToSelect)
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: AppTheme.minTapSize)
            Text("Close your eyes for about half a second, then open them. Normal blinks are ignored. Needs an iPhone with Face ID.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Bluetooth switches: pair one in Settings > Bluetooth. Switches that send Space or Enter work on the Talk board.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var alertSettings: some View {
        Card {
            Toggle(isOn: $profile.eyesClosedAlert) {
                Label("Sound the alert when I close my eyes", systemImage: "eye.slash.fill")
                    .font(.headline)
                    .foregroundStyle(AppTheme.coral)
            }
            .frame(minHeight: AppTheme.minTapSize)
            Text("While the Talk board is open, keeping your eyes closed for \(Int(profile.eyesClosedAlertSeconds)) seconds plays the loud alert, even if you can't move. Uses the Face ID camera.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if profile.eyesClosedAlert {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Eyes closed for \(Int(profile.eyesClosedAlertSeconds)) seconds")
                        .font(.subheadline.weight(.semibold))
                    Slider(value: $profile.eyesClosedAlertSeconds, in: 2...8, step: 1)
                        .accessibilityLabel("Eyes-closed time")
                        .accessibilityValue("\(Int(profile.eyesClosedAlertSeconds)) seconds")
                }
                Label("Turn this off before resting or sleeping with the Talk board open.", systemImage: "moon.zzz.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            AlertShortcutSettings(profile: profile)
            Divider()
            Toggle(isOn: $profile.autoCallOnAlert) {
                Label("Also call my first family member", systemImage: "phone.arrow.up.right.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .frame(minHeight: AppTheme.minTapSize)
            .disabled(profile.alertShortcutEnabled)
            Text(profile.alertShortcutEnabled
                 ? "Off while the Resonance Alert shortcut is on: the shortcut texts family instead. You can add a Call action to the shortcut too."
                 : "When the alert starts, Resonance starts a call to the person marked \"Called first\" on the Family tab. iOS asks to confirm every call; with Switch Control or Voice Control turned on in iOS Settings > Accessibility, that can be done hands-free too.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var shortcutSettings: some View {
        Card {
            Label("Alert without opening the app", systemImage: "hand.tap.fill")
                .font(.headline)
                .foregroundStyle(AppTheme.coral)
            Text("A helper can set this up once, so the alert can start from anywhere on the phone:")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            step(1, "Back Tap", "Settings > Accessibility > Touch > Back Tap > Double Tap > choose \"Sound the Resonance alert\". A double tap on the back of the phone then sounds the alert.")
            step(2, "Action button", "On iPhones with an Action button: Settings > Action Button > Shortcut > \"Sound the Resonance alert\".")
            step(3, "Siri", "Say \"Resonance alert\". Siri needs speech, so this suits family more than the person using the app.")
        }
    }

    private var voiceSettings: some View {
        Card {
            Label("Computer voice", systemImage: "speaker.wave.2.fill")
                .font(.headline)
                .foregroundStyle(AppTheme.accent)
            HStack {
                Image(systemName: "tortoise.fill").foregroundStyle(.secondary).accessibilityHidden(true)
                Slider(value: $profile.speechRate, in: 0.35...0.55, step: 0.01)
                    .accessibilityLabel("Speaking speed")
                    .accessibilityValue(profile.speechRate < 0.42 ? "Slow" : profile.speechRate > 0.49 ? "Fast" : "Normal")
                Image(systemName: "hare.fill").foregroundStyle(.secondary).accessibilityHidden(true)
            }
            Button {
                SpeechOutput.shared.speak("This is how I sound.", preferPersonalVoice: profile.preferPersonalVoice,
                                          rate: Float(profile.speechRate))
            } label: {
                Label("Test the voice", systemImage: "play.fill")
            }
            .buttonStyle(SecondaryButtonStyle())
            Text("Phrases you recorded in Voice Bank always play in your own voice.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func set(_ mode: String) {
        profile.inputMode = mode
        try? modelContext.save()
    }

    private func step(_ n: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)")
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(AppTheme.accent, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Hands-free texts through a Shortcuts shortcut, with setup steps and a test.
private struct AlertShortcutSettings: View {
    @Bindable var profile: Profile
    @Environment(\.openURL) private var openURL
    @State private var showSteps = false
    @State private var testResult: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $profile.alertShortcutEnabled) {
                Label("Text family automatically", systemImage: "message.badge.filled.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .frame(minHeight: AppTheme.minTapSize)
            Text("Uses a shortcut you make once in Apple's Shortcuts app. When the alert starts, it texts your family with no tap needed, even if you can't move.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if profile.alertShortcutEnabled {
                HStack {
                    Text("Shortcut name")
                        .font(.subheadline)
                    TextField(AlertShortcut.defaultName, text: $profile.alertShortcutName)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                }
                .frame(minHeight: AppTheme.minTapSize)

                Button {
                    guard let url = AlertShortcut.url(name: profile.alertShortcutName,
                                                      message: AlertShortcut.testMessage(name: profile.name)) else { return }
                    openURL(url) { opened in
                        testResult = opened
                            ? "Shortcuts opened. If your family got the test text, it works."
                            : "Couldn't open Shortcuts. Is the Shortcuts app installed?"
                    }
                } label: {
                    Label("Test it (sends a test text)", systemImage: "paperplane.fill")
                }
                .buttonStyle(SecondaryButtonStyle(color: AppTheme.coral))
                if let testResult {
                    Text(testResult)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            DisclosureGroup(isExpanded: $showSteps) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(AlertShortcut.setupSteps.enumerated()), id: \.offset) { index, item in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(index + 1)")
                                .font(.system(.footnote, design: .rounded).weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(AppTheme.coral, in: Circle())
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).font(.subheadline.weight(.semibold))
                                Text(item.detail).font(.footnote).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.top, 6)
            } label: {
                Text("How to make the shortcut (5 minutes, done once)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(minHeight: AppTheme.minTapSize, alignment: .leading)
                    .contentShape(Rectangle())
            }
        }
    }
}

private struct ModeCard: View {
    let selected: Bool
    let icon: String
    let color: Color
    let title: String
    let detail: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                IconBadge(systemImage: icon, color: color, size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(selected ? color : Color.secondary.opacity(0.5))
                    .accessibilityHidden(true)
            }
            .padding(AppTheme.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surfaceStyle()
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                    .strokeBorder(selected ? color : .clear, lineWidth: 2)
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
