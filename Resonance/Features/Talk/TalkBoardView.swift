//
//  TalkBoardView.swift
//  Resonance
//
//  The Talk board (PLAN.pdf Section 13): speak instantly in the user's own voice.
//  - Quick row: Yes, No, Pain, Wait, always on screen.
//  - "I'm in pain" asks where and how bad, then says one clear sentence.
//  - Phrase tiles by category, and a keyboard with word predictions for anything else.
//  - The last thing said stays on screen: repeat it, show it in big letters, or text it to family.
//  - Bottom row: keyboard, call the first family member, and the loud alert.
//  Works by touch, by head pointer (dwell), or by switch scanning (tap anywhere, a
//  Bluetooth switch, or a long blink). Every control goes through `activate(_:)`.
//

import SwiftUI
import SwiftData
import UIKit

struct TalkBoardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Query(sort: [SortDescriptor(\Phrase.order)]) private var phrases: [Phrase]
    @Query private var profiles: [Profile]
    @Query(sort: [SortDescriptor(\CareContact.createdAt)]) private var contacts: [CareContact]
    @AppStorage("selectedTab") private var selectedTab = AppTab.talk.rawValue

    enum Panel: Equatable { case phrases, keyboard, painWhere, painHow, feelings }

    @State private var category = "Needs"
    @State private var page = 0
    @State private var panel: Panel = .phrases
    @State private var painArea: PainArea?
    @State private var feelingIntensity: FeelingIntensity = .plain
    @State private var lastSaid: String?
    /// A short confirmation shown at the top of the board (for example "Saved to Questions").
    @State private var notice: String?
    @State private var noticeCount = 0
    /// The last 10 different messages, newest first (touch and hold the message to see them).
    @State private var recent: [String] = []
    @State private var typed = ""
    @State private var showEmergency = false
    @State private var showVoiceBank = false
    @State private var showBigText = false
    @State private var showHandsFree = false
    @State private var sendRequest: FamilySendRequest?
    @State private var callProblem = false

    // Hands-free
    @State private var tracker = FaceTracker()
    @State private var dwell = DwellSelector(dwell: 1.2)
    @State private var hovered: String?
    @State private var dwellProgress: Double = 0
    @State private var calibrating = false
    /// Calibration was wanted while a sheet was open; start it when the board is visible again.
    @State private var calibrationPending = false
    @State private var scanner = Scanner()
    @State private var scanElapsed: Double = 0
    /// Timer bookkeeping kept outside SwiftUI state, so the 30 Hz timer doesn't redraw the board.
    @State private var clock = TickClock()
    @State private var battery = BatteryMonitor()
    @State private var blinkHold: Double = 0
    @FocusState private var switchFocused: Bool

    private let pageSize = 6
    private let ticker = Timer.publish(every: 1.0 / 30, on: .main, in: .common).autoconnect()

    private var profile: Profile? { profiles.first }
    private var mode: String { profile?.inputMode ?? "touch" }
    private var headMode: Bool { mode == "head" }
    private var scanMode: Bool { mode == "scan" }
    private var primaryContact: CareContact? { contacts.first(where: \.isPrimary) ?? contacts.first }

    /// The camera runs for the head pointer, for blink selection, or for the eyes-closed alert.
    private var needsCamera: Bool {
        guard let profile else { return false }
        return headMode || (scanMode && profile.blinkToSelect) || profile.eyesClosedAlert
    }

    /// Something covers the board, so hands-free selection pauses.
    private var paused: Bool {
        calibrating || showEmergency || showBigText || showVoiceBank || showHandsFree || sendRequest != nil || callProblem
            || AlertPresenter.isShowing   // an alert opened by a shortcut is on top
    }

    private var categoryPhrases: [Phrase] { phrases.filter { $0.category == category } }

    private var pageCount: Int {
        max(1, Int(ceil(Double(categoryPhrases.count) / Double(pageSize))))
    }

    private var pagePhrases: [Phrase] {
        let start = min(page, pageCount - 1) * pageSize
        return Array(categoryPhrases.dropFirst(start).prefix(pageSize))
    }

    var body: some View {
        NavigationStack {
            board
                .screenBackground()
                .navigationTitle("Talk")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
                .sheet(isPresented: $showVoiceBank) {
                    NavigationStack { VoiceBankView() }
                }
                .sheet(isPresented: $showHandsFree) {
                    NavigationStack { HeadControlSetupView(isSheet: true) }
                }
                .fullScreenCover(isPresented: $showEmergency) {
                    EmergencyAlertView()
                }
                .fullScreenCover(isPresented: $showBigText) {
                    BigTextView(text: lastSaid ?? "")
                }
                .familySender($sendRequest)
                .overlay(alignment: .bottom) {
                    // Above the Keyboard / Call / Alert row, so it never covers the message.
                    if let notice {
                        Label(notice, systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(AppTheme.mint, in: Capsule())
                            .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
                            .padding(.bottom, 96)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .allowsHitTesting(false)
                            .accessibilityAddTraits(.isStaticText)
                    }
                }
                .sensoryFeedback(.success, trigger: noticeCount)
                .alert("Calling isn't available on this device", isPresented: $callProblem) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(contacts.isEmpty
                         ? "Add a family member on the Family tab first."
                         : "On an iPhone, this calls \(primaryContact?.name ?? "them"). iOS asks to confirm before dialing.")
                }
        }
        .onAppear {
            clock.visible = true
            battery.start()
            PhraseLibrary.seedIfNeeded(in: modelContext)
            dwell.dwell = profile?.dwellSeconds ?? 1.2
            updateTracking()
            refreshScanGroups()
        }
        .onDisappear {
            clock.visible = false
            battery.stop()
            tracker.stop()
            // The alert keeps the screen on itself; don't undo that while it is sounding.
            if !AlertPresenter.isShowing { UIApplication.shared.isIdleTimerDisabled = false }
        }
        // After a sheet or alert closes: give focus back to a Bluetooth switch, and start
        // head-pointer calibration if it was waiting.
        .onChange(of: paused) { _, isPaused in
            if !isPaused {
                switchFocused = scanMode
                if calibrationPending && headMode && tracker.mapper == nil && FaceTracker.isSupported && !calibrating {
                    calibrating = true
                }
                calibrationPending = false
            }
        }
        .onChange(of: profile?.inputMode) { _, _ in updateTracking(); refreshScanGroups() }
        .onChange(of: battery.advice) { _, _ in refreshScanGroups() }
        .onChange(of: profile?.blinkToSelect) { _, _ in updateTracking() }
        .onChange(of: profile?.eyesClosedAlert) { _, _ in updateTracking() }
        .onChange(of: profile?.dwellSeconds) { _, newValue in dwell.dwell = newValue ?? 1.2 }
        .onChange(of: panel) { _, _ in refreshScanGroups() }
        .onChange(of: page) { _, _ in refreshScanGroups() }
        .onChange(of: category) { _, _ in refreshScanGroups() }
        .onChange(of: typed) { _, _ in refreshScanGroups() }
        .onChange(of: phrases.count) { _, _ in refreshScanGroups() }
        .onReceive(ticker) { _ in tick() }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { showVoiceBank = true } label: {
                Label("Voice Bank", systemImage: "waveform.badge.mic")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Control", selection: inputModeBinding) {
                    Label("Touch", systemImage: "hand.point.up").tag("touch")
                    Label("Head pointer", systemImage: "face.smiling").tag("head")
                    Label("Switch scanning", systemImage: "rectangle.and.hand.point.up.left.filled").tag("scan")
                }
                if headMode {
                    Button("Calibrate head pointer") { calibrating = true }
                }
                Button("Hands-free settings…") { showHandsFree = true }
            } label: {
                Label("Control", systemImage: modeIcon)
            }
            .accessibilityLabel("How I choose: \(modeName)")
        }
    }

    private var modeIcon: String {
        switch mode {
        case "head": return "face.smiling"
        case "scan": return "rectangle.and.hand.point.up.left.filled"
        default: return "hand.point.up"
        }
    }

    private var modeName: String {
        switch mode {
        case "head": return "head pointer"
        case "scan": return "switch scanning"
        default: return "touch"
        }
    }

    // MARK: Board layout

    private var board: some View {
        VStack(spacing: 8) {
            if mode != "touch" || (profile?.eyesClosedAlert ?? false) { statusLine }

            messageStrip
            if let warning = battery.advice.message { batteryBanner(warning) }
            // The quick row makes room for the keyboard and the pain questions on smaller iPhones.
            if panel == .phrases { quickRow }

            switch panel {
            case .phrases:
                categoryBar
                phraseGrid
                pager
            case .keyboard:
                KeyboardPanel(text: typed, predictions: Predictions.complete(typed),
                              highlight: highlightState, activate: activate)
            case .painWhere:
                PainWherePanel(highlight: highlightState, activate: activate)
            case .painHow:
                PainHowPanel(area: painArea, highlight: highlightState, activate: activate)
            case .feelings:
                FeelingsPanel(intensity: feelingIntensity, highlight: highlightState, activate: activate)
            }

            bottomRow
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .coordinateSpace(name: TileFramesKey.space)
        // Only store frames that really changed, to avoid extra redraws.
        .onPreferenceChange(TileFramesKey.self) { frames in
            // Kept outside view state: only the head-pointer timer reads them, and storing them
            // in @State re-rendered the board on every layout pass ("updated multiple times per frame").
            clock.tileFrames = frames
        }
        .overlay {
            if headMode, !calibrating, let p = tracker.livePointer {
                Circle()
                    .stroke(AppTheme.amber, lineWidth: 4)
                    .background(Circle().fill(AppTheme.amber.opacity(0.2)))
                    .frame(width: 36, height: 36)
                    .position(p)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .overlay {
            // Switch scanning: a tap anywhere on the board is the switch.
            if scanMode && !paused {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { switchPressed() }
                    .accessibilityElement()
                    .accessibilityLabel("Switch")
                    .accessibilityHint("Chooses the highlighted item")
                    .accessibilityAddTraits(.isButton)
            }
        }
        .overlay {
            if calibrating {
                CalibrationOverlay(tracker: tracker) { mapper in
                    if let mapper { tracker.setMapper(mapper) }
                    calibrating = false
                    dwell.reset()
                }
            }
        }
        // A Bluetooth switch or keyboard (space or return) also works as the switch.
        .focusable(scanMode)
        .focused($switchFocused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.space, .return]) { _ in
            guard scanMode, !paused else { return .ignored }
            switchPressed()
            return .handled
        }
    }

    private var statusLine: some View {
        HStack(spacing: 8) {
            Group {
                if headMode {
                    if !FaceTracker.isSupported {
                        Text("Head pointer needs an iPhone with Face ID. Touch still works.")
                    } else if tracker.mapper == nil {
                        Button { calibrating = true } label: {
                            Text("Calibrate the head pointer to start")
                                .frame(minHeight: AppTheme.minTapSize)
                                .contentShape(Rectangle())
                        }
                            .fontWeight(.semibold)
                    } else if !tracker.faceVisible {
                        Text("Looking for your face… hold the phone in front of you.")
                    } else {
                        Text("Point at a button and hold still to choose it.")
                    }
                } else if scanMode {
                    Text(profile?.blinkToSelect == true
                         ? "Tap anywhere, press your switch, or blink long to choose."
                         : "Tap anywhere or press your switch to choose the highlighted item.")
                } else {
                    Text("Eyes-closed alert is on.")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .minimumScaleFactor(0.8)

            if blinkHold > 0.3 {
                // Shows the eyes-closed timer so a deliberate close is visible to helpers.
                ProgressView(value: min(blinkHold / (profile?.eyesClosedAlertSeconds ?? 3), 1))
                    .tint(AppTheme.coral)
                    .frame(width: 50)
                    .accessibilityLabel("Eyes closed")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 22)
    }

    /// Low battery: a calm banner with one button that asks people nearby to plug the phone in.
    private func batteryBanner(_ text: String) -> some View {
        let critical: Bool = { if case .critical = battery.advice { return true } else { return false } }()
        return HStack(spacing: 10) {
            Image(systemName: critical ? "battery.0percent" : "battery.25percent")
                .font(.title2)
                .foregroundStyle(critical ? AppTheme.coral : AppTheme.amber)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { activate("battery.ask") } label: {
                Label("Ask", systemImage: "speaker.wave.2.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(minWidth: AppTheme.minTapSize, minHeight: AppTheme.minTapSize)
                    .background(critical ? AppTheme.coral : AppTheme.amber,
                                in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
                    .highlight(highlightState("battery.ask"))
            }
            .buttonStyle(PressableStyle())
            .reportFrame("battery.ask")
            .accessibilityLabel("Ask someone to plug in the phone")
        }
        .padding(.leading, 12)
        .padding(4)
        .background((critical ? AppTheme.coral : AppTheme.amber).opacity(0.14),
                    in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
        .transition(.opacity)
        .accessibilityElement(children: .contain)
    }

    private var messageStrip: some View {
        HStack(spacing: 8) {
            Button { activate("msg.repeat") } label: {
                HStack(spacing: 10) {
                    Image(systemName: lastSaid == nil ? "text.bubble" : "speaker.wave.2.fill")
                        .font(.title3)
                        .foregroundStyle(AppTheme.accent)
                        .accessibilityHidden(true)
                    Text(lastSaid ?? "Choose anything below to say it out loud.")
                        .font(lastSaid == nil ? .subheadline : .headline)
                        .foregroundStyle(lastSaid == nil ? .secondary : AppTheme.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: AppTheme.minTapSize)
                .surfaceStyle(radius: AppTheme.controlRadius)
                .highlight(highlightState("msg.repeat"))
            }
            .buttonStyle(PressableStyle())
            .reportFrame("msg.repeat", when: lastSaid != nil)
            .disabled(lastSaid == nil)
            .contextMenu {
                if let lastSaid, CareQuestions.clean(lastSaid) != nil {
                    Button { saveQuestion(lastSaid) } label: {
                        Label("Save as a question for my care team", systemImage: "questionmark.bubble")
                    }
                }
                if recent.count > 1 {
                    Section("Say again") {
                        ForEach(recent, id: \.self) { text in
                            Button(text) { say(text, phrase: phrases.first { $0.text == text }) }
                        }
                    }
                }
            }
            .accessibilityHint(recent.count > 1 ? "Touch and hold for recent messages" : "")
            .accessibilityAction(named: "Save as a question for my care team") {
                if let lastSaid { saveQuestion(lastSaid) }
            }
            .accessibilityLabel(lastSaid.map { "Say again: \($0)" } ?? "Nothing said yet")

            stripButton("msg.show", icon: "textformat.size", label: "Show")
            stripButton("msg.send", icon: "paperplane.fill", label: "Send")
        }
    }

    private func stripButton(_ id: String, icon: String, label: String) -> some View {
        Button { activate(id) } label: {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.headline)
                Text(label).font(.caption.weight(.semibold))
            }
            .foregroundStyle(lastSaid == nil ? Color.secondary : AppTheme.accent)
            .frame(minWidth: 62, minHeight: AppTheme.minTapSize)
            .background(AppTheme.violetSoft, in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
            .highlight(highlightState(id))
        }
        .buttonStyle(PressableStyle())
        .reportFrame(id, when: lastSaid != nil)
        .disabled(lastSaid == nil)
        .accessibilityLabel(id == "msg.show" ? "Show in big letters" : "Send to family")
    }

    private var quickRow: some View {
        HStack(spacing: 8) {
            QuickButton(id: "quick.yes", title: "Yes", icon: "checkmark", color: AppTheme.mint,
                        state: highlightState("quick.yes"), activate: activate)
            QuickButton(id: "quick.no", title: "No", icon: "xmark", color: AppTheme.coral,
                        state: highlightState("quick.no"), activate: activate)
            QuickButton(id: "quick.pain", title: "Pain", icon: "bandage.fill", color: AppTheme.amber,
                        state: highlightState("quick.pain"), activate: activate)
            QuickButton(id: "quick.wait", title: "Wait", icon: "hand.raised.fill", color: AppTheme.blue,
                        state: highlightState("quick.wait"), activate: activate)
            QuickButton(id: "quick.feel", title: "Feel", icon: "face.smiling", color: AppTheme.violet,
                        state: highlightState("quick.feel"), activate: activate)
        }
    }

    private var categoryBar: some View {
        HStack(spacing: 6) {
            ForEach(PhraseLibrary.categories, id: \.self) { name in
                let id = "cat.\(name)"
                Button { activate(id) } label: {
                    Text(PhraseLibrary.displayName(name))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: AppTheme.minTapSize)
                        .background(category == name ? AppTheme.accent : AppTheme.surface,
                                    in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
                        .foregroundStyle(category == name ? Color.white : AppTheme.ink)
                        .highlight(highlightState(id))
                }
                .buttonStyle(PressableStyle())
                .reportFrame(id)
                .accessibilityAddTraits(category == name ? .isSelected : [])
            }
        }
    }

    private var phraseGrid: some View {
        // Tiles share the available height in 3 rows, so the board fills the screen on every iPhone.
        GeometryReader { geo in
            let rows = CGFloat(pageSize / 2)
            let tileHeight = max(60, (geo.size.height - 8 * (rows - 1)) / rows)
            let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(pagePhrases) { phrase in
                    let id = "phrase.\(phrase.text)"
                    Button { activate(id) } label: {
                        PhraseTile(phrase: phrase, state: highlightState(id))
                            .frame(height: tileHeight)
                    }
                    .buttonStyle(PressableStyle())
                    .reportFrame(id)
                    .accessibilityLabel(phrase.text)
                    .accessibilityHint(phrase.clip != nil ? "Plays your recorded voice" : "Speaks this phrase")
                    .contextMenu {
                        // Touch and hold a tile for more ways to use it.
                        Button { lastSaid = phrase.text; showBigText = true } label: {
                            Label("Show in big letters", systemImage: "textformat.size")
                        }
                        Button { lastSaid = phrase.text; activate("msg.send") } label: {
                            Label("Send to family", systemImage: "paperplane.fill")
                        }
                        Button { showVoiceBank = true } label: {
                            Label(phrase.clip == nil ? "Record in my voice" : "Record again", systemImage: "mic.fill")
                        }
                        if phrase.category == "Custom" {
                            Button(role: .destructive) {
                                if let clip = phrase.clip {
                                    if let url = try? BankFiles.url(for: clip.fileName) {
                                        try? FileManager.default.removeItem(at: url)
                                    }
                                    modelContext.delete(clip)
                                }
                                modelContext.delete(phrase)
                                try? modelContext.save()
                            } label: {
                                Label("Remove from Mine", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .overlay {
                if pagePhrases.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "text.bubble")
                            .font(.largeTitle)
                            .foregroundStyle(AppTheme.accent)
                        Text("Your own phrases go here.").font(.headline)
                        Text("Type one on the keyboard and tap Save phrase, or add it in Voice Bank.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var pager: some View {
        HStack {
            Button { activate("nav.prev") } label: {
                Label("Back", systemImage: "chevron.left")
                    .frame(minWidth: 96, minHeight: AppTheme.minTapSize)
                    .highlight(highlightState("nav.prev"))
            }
            .reportFrame("nav.prev", when: pageCount > 1 && page > 0)
            .disabled(page == 0)
            Spacer()
            HStack(spacing: 6) {
                ForEach(0..<pageCount, id: \.self) { i in
                    Circle()
                        .fill(i == min(page, pageCount - 1) ? AppTheme.accent : AppTheme.violetSoft)
                        .frame(width: 8, height: 8)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Page \(min(page, pageCount - 1) + 1) of \(pageCount)")
            Spacer()
            Button { activate("nav.next") } label: {
                Label("More", systemImage: "chevron.right")
                    .labelStyle(TrailingIconLabelStyle())
                    .frame(minWidth: 96, minHeight: AppTheme.minTapSize)
                    .highlight(highlightState("nav.next"))
            }
            .reportFrame("nav.next", when: pageCount > 1 && page < pageCount - 1)
            .disabled(page >= pageCount - 1)
        }
        .font(.headline)
        .opacity(pageCount > 1 ? 1 : 0)
        .allowsHitTesting(pageCount > 1)
    }

    private var bottomRow: some View {
        HStack(spacing: 8) {
            bottomButton(id: "keyboard", title: panel == .keyboard ? "Phrases" : "Keyboard",
                         icon: panel == .keyboard ? "square.grid.2x2.fill" : "keyboard.fill", color: AppTheme.violetDeep)
            bottomButton(id: "call", title: primaryContact.map { "Call \($0.firstName)" } ?? "Family",
                         icon: primaryContact == nil ? "person.2.fill" : "phone.fill", color: AppTheme.mint)
            bottomButton(id: "emergency", title: "Alert", icon: "exclamationmark.triangle.fill", color: AppTheme.danger)
                .accessibilityHint("Plays a loud alert to get attention nearby. It does not contact emergency services.")
        }
    }

    private func bottomButton(id: String, title: String, icon: String, color: Color) -> some View {
        Button { activate(id) } label: {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.title3)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(color, in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
            .highlight(highlightState(id))
        }
        .buttonStyle(PressableStyle())
        .reportFrame(id)
    }

    // MARK: Actions

    /// Every tile, button and key goes through here, whether chosen by touch, dwell or switch.
    private func activate(_ id: String) {
        if id.hasPrefix("phrase.") {
            let text = String(id.dropFirst("phrase.".count))
            say(text, phrase: phrases.first { $0.text == text })
        } else if id.hasPrefix("cat.") {
            category = String(id.dropFirst("cat.".count))
            page = 0
        } else if id.hasPrefix("key.") || id.hasPrefix("pred.") {
            handleKey(id)
        } else if id.hasPrefix("pain.") {
            handlePain(id)
        } else if id.hasPrefix("quick.") {
            handleQuick(id)
        } else if id.hasPrefix("feel") {
            handleFeeling(id)
        } else {
            switch id {
            case "battery.ask":
                speakOnly(BatteryAdvice.spokenRequest)
            case "msg.repeat":
                if let lastSaid { say(lastSaid, phrase: phrases.first { $0.text == lastSaid }) }
            case "msg.show":
                if lastSaid != nil { showBigText = true }
            case "msg.send":
                if let lastSaid {
                    sendRequest = FamilySendRequest(kind: .message,
                                                    body: CareMessage.relay(lastSaid, name: profile?.name ?? "", date: Date()),
                                                    contacts: contacts)
                }
            case "nav.prev": page = max(0, page - 1)
            case "nav.next": page = min(pageCount - 1, page + 1)
            case "keyboard": panel = panel == .keyboard ? .phrases : .keyboard
            case "call": callPrimary()
            case "emergency": showEmergency = true
            default: break
            }
        }
    }

    private func handleQuick(_ id: String) {
        switch id {
        case "quick.yes": say("Yes", phrase: phrases.first { $0.text == "Yes" })
        case "quick.no": say("No", phrase: phrases.first { $0.text == "No" })
        case "quick.wait": say("Please wait", phrase: phrases.first { $0.text == "Please wait" })
        case "quick.feel":
            feelingIntensity = .plain
            panel = .feelings
        case "quick.pain":
            // Say it right away, then ask where and how bad for the details.
            say(PainPhrase.opening, phrase: phrases.first { $0.text == "I'm in pain" })
            painArea = nil
            panel = .painWhere
        default: break
        }
    }

    private func handlePain(_ id: String) {
        let key = String(id.dropFirst("pain.".count))
        if key.hasPrefix("area.") {
            painArea = PainArea(rawValue: String(key.dropFirst("area.".count)))
            if let painArea { speakOnly(painArea.sentence) }
            panel = .painHow
        } else if key.hasPrefix("level.") {
            let level = Int(key.dropFirst("level.".count)) ?? 5
            speakOnly(PainPhrase.levelSentence(level))
            finishPain(level: level)
        } else if key == "skip" {
            if panel == .painWhere { panel = .painHow } else { finishPain(level: nil) }
        } else if key == "cancel" {
            panel = .phrases
        }
    }

    /// Faces: "feel.sad" says it (and keeps it for family); "feelint.3" picks "very"; "feel.cancel" goes back.
    private func handleFeeling(_ id: String) {
        if id.hasPrefix("feelint.") {
            feelingIntensity = FeelingIntensity(rawValue: Int(id.dropFirst("feelint.".count)) ?? 2) ?? .plain
            return
        }
        let key = String(id.dropFirst("feel.".count))
        if key == "cancel" {
            panel = .phrases
            return
        }
        guard let feeling = Feeling(rawValue: key) else { return }
        say(FeelingPhrase.full(feeling, intensity: feelingIntensity), phrase: nil)
        modelContext.insert(FeelingEntry(feeling: feeling, intensity: feelingIntensity))
        try? modelContext.save()
        panel = .phrases
    }

    /// The whole sentence becomes the message on screen, ready to repeat, show or send.
    private func finishPain(level: Int?) {
        let sentence = PainPhrase.sentence(area: painArea, level: level)
        lastSaid = sentence
        remember(sentence)
        panel = .phrases
        painArea = nil
    }

    private func handleKey(_ id: String) {
        if id.hasPrefix("pred.") {
            let word = String(id.dropFirst("pred.".count))
            typed = Predictions.apply(word, to: typed)
            return
        }
        let key = String(id.dropFirst("key.".count))
        switch key {
        case "space": typed += " "
        case "delete": if !typed.isEmpty { typed.removeLast() }
        case "clear": typed = ""
        case "speak":
            let text = typed.trimmingCharacters(in: .whitespaces)
            if !text.isEmpty { say(text.capitalizedFirstLetter, phrase: nil) }
        case "save":
            let text = typed.trimmingCharacters(in: .whitespaces).capitalizedFirstLetter
            if !text.isEmpty && !phrases.contains(where: { $0.text == text }) {
                let order = (phrases.filter { $0.category == "Custom" }.map(\.order).max() ?? -1) + 1
                modelContext.insert(Phrase(text: text, category: "Custom", order: order))
                try? modelContext.save()
                speakOnly("Saved.")
                showNotice("Saved to Mine")
            } else if !text.isEmpty {
                showNotice("Already in Mine")
            }
        case "ask":
            let text = typed.trimmingCharacters(in: .whitespaces)
            if text.isEmpty {
                showNotice("Type the question first")
            } else {
                saveQuestion(CareQuestions.asQuestion(text.capitalizedFirstLetter))
            }
        default:
            typed += typed.isEmpty ? key : key.lowercased()
        }
    }

    private func remember(_ text: String) {
        recent.removeAll { $0 == text }
        recent.insert(text, at: 0)
        if recent.count > 10 { recent.removeLast() }
    }

    private func saveQuestion(_ text: String) {
        guard let cleaned = CareQuestions.clean(text) else { return }
        let existing = (try? modelContext.fetch(FetchDescriptor<CareQuestion>())) ?? []
        if let old = existing.first(where: { CareQuestions.isDuplicate(cleaned, of: [$0.text]) }) {
            if old.asked {
                // Asked before but it came up again: put it back on the list.
                old.asked = false
                try? modelContext.save()
                showNotice("Back on your Questions list")
            } else {
                showNotice("Already in Questions")
            }
            return
        }
        modelContext.insert(CareQuestion(text: cleaned))
        try? modelContext.save()
        showNotice("Saved to Questions on the Family tab")
    }

    private func showNotice(_ text: String) {
        noticeCount += 1
        let shown = noticeCount
        // Wait for a context menu to finish closing so the confirmation is seen.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard shown == noticeCount else { return }
            withAnimation(.spring(duration: 0.35)) { notice = text }
            UIAccessibility.post(notification: .announcement, argument: text)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            guard shown == noticeCount else { return }
            withAnimation(.easeOut(duration: 0.3)) { notice = nil }
        }
    }

    private func say(_ text: String, phrase: Phrase?) {
        SpeechOutput.shared.speak(text, clipFileName: phrase?.clip?.fileName,
                                  preferPersonalVoice: profile?.preferPersonalVoice ?? true,
                                  rate: Float(profile?.speechRate ?? 0.45))
        phrase?.useCount += 1
        lastSaid = text
        remember(text)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Speaks without changing the message on screen (pain details, confirmations).
    private func speakOnly(_ text: String) {
        SpeechOutput.shared.speak(text, preferPersonalVoice: profile?.preferPersonalVoice ?? true,
                                  rate: Float(profile?.speechRate ?? 0.45))
    }

    private func callPrimary() {
        guard let contact = primaryContact else {
            selectedTab = AppTab.family.rawValue
            return
        }
        CallAction(openURL: openURL, context: modelContext).call(contact) { ok in
            if !ok { callProblem = true }
        }
    }

    // MARK: Hands-free

    private var inputModeBinding: Binding<String> {
        Binding(
            get: { profile?.inputMode ?? "touch" },
            set: { newValue in
                if let profile {
                    profile.inputMode = newValue
                } else {
                    let p = Profile(name: "", role: "person", onsetType: "unsure")
                    p.inputMode = newValue
                    modelContext.insert(p)
                }
                try? modelContext.save()
            }
        )
    }

    private func updateTracking() {
        if needsCamera {
            tracker.start()
            // Calibrate only when the board is in front of the person (not behind a sheet).
            if headMode && tracker.mapper == nil && FaceTracker.isSupported {
                if paused { calibrationPending = true } else { calibrating = true }
            }
        } else {
            tracker.stop()
        }
        // Hands-free users don't touch the screen, so keep it from locking while they talk.
        UIApplication.shared.isIdleTimerDisabled = clock.visible && (needsCamera || scanMode)
        if !headMode {
            hovered = nil
            dwellProgress = 0
        }
        clock.blink.reset()
        blinkHold = 0
        switchFocused = scanMode
    }

    /// The rows switch scanning steps through, in reading order of importance.
    private var scanGroups: [[String]] {
        var groups: [[String]] = []
        switch panel {
        case .phrases:
            groups.append(["quick.yes", "quick.no", "quick.pain", "quick.wait", "quick.feel"])
            let ids = pagePhrases.map { "phrase.\($0.text)" }
            stride(from: 0, to: ids.count, by: 2).forEach { groups.append(Array(ids[$0..<min($0 + 2, ids.count)])) }
            if pageCount > 1 {
                var nav: [String] = []
                if page > 0 { nav.append("nav.prev") }
                if page < pageCount - 1 { nav.append("nav.next") }
                groups.append(nav)
            }
            groups.append(PhraseLibrary.categories.map { "cat.\($0)" })
        case .keyboard:
            groups += KeyboardPanel.scanGroups(predictions: Predictions.complete(typed))
        case .painWhere:
            groups += PainWherePanel.scanGroups
        case .painHow:
            groups += PainHowPanel.scanGroups
        case .feelings:
            groups += FeelingsPanel.scanGroups
        }
        if lastSaid != nil { groups.append(["msg.repeat", "msg.show", "msg.send"]) }
        if battery.advice.isWarning { groups.insert(["battery.ask"], at: 0) }
        groups.append(["keyboard", "call", "emergency"])
        return groups
    }

    private func refreshScanGroups() {
        guard scanMode else { return }
        scanner.update(groups: scanGroups)
        scanElapsed = 0
    }

    private func switchPressed() {
        guard scanMode, !paused else { return }
        scanElapsed = 0
        if let id = scanner.select() {
            activate(id)
            refreshScanGroups()
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// What a control should look like right now (highlighted, and its progress ring).
    private func highlightState(_ id: String) -> HighlightState {
        if headMode {
            return HighlightState(on: hovered == id, progress: dwellProgress)
        }
        if scanMode, scanner.highlighted.contains(id) {
            let single = scanner.highlighted.count == 1
            let seconds = profile?.scanSeconds ?? 1.5
            return HighlightState(on: true, progress: single ? scanElapsed / seconds : nil)
        }
        return HighlightState(on: false, progress: nil)
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(now - clock.lastTick, 0.2)
        clock.lastTick = now
        // Nothing to do in touch mode without the camera, or while another tab is showing.
        guard clock.visible, mode != "touch" || tracker.isRunning else { return }

        // Long blink and eyes-closed alert (any mode where the camera runs).
        if tracker.isRunning, !paused, let profile {
            clock.blink.alertAfter = profile.eyesClosedAlertSeconds
            let event = clock.blink.update(eyesClosed: tracker.eyesClosed, now: now, alertEnabled: profile.eyesClosedAlert)
            let hold = profile.eyesClosedAlert ? (clock.blink.closedDuration(now: now) * 10).rounded() / 10 : 0
            if hold != blinkHold { blinkHold = hold }
            if event == .alert {
                showEmergency = true
            } else if event == .select, profile.blinkToSelect {
                if scanMode {
                    switchPressed()
                } else if headMode, let current = hovered {
                    hovered = nil
                    dwellProgress = 0
                    activate(current)
                }
            }
        }

        if scanMode && !paused {
            scanElapsed += dt
            if scanElapsed >= (profile?.scanSeconds ?? 1.5) {
                scanElapsed = 0
                scanner.advance()
            }
            return
        }

        guard headMode, !paused, let p = tracker.livePointer else {
            if hovered != nil { hovered = nil; dwellProgress = 0 }
            return
        }
        let tile = clock.tileFrames.first { $0.value.contains(p) }?.key
        let result = dwell.update(tile: tile, now: now)
        hovered = dwell.current
        dwellProgress = result.progress
        if let selected = result.selected {
            hovered = nil
            dwellProgress = 0
            activate(selected)
        }
    }
}

/// Plain reference type: changing it never redraws the view.
private final class TickClock {
    var lastTick = CACurrentMediaTime()
    var blink = BlinkDetector()
    var visible = false
    /// Where every dwell target is on screen, by id.
    var tileFrames: [String: CGRect] = [:]
}

// MARK: - Quick buttons and tiles

private struct QuickButton: View {
    let id: String
    let title: String
    let icon: String
    let color: Color
    let state: HighlightState
    let activate: (String) -> Void

    var body: some View {
        Button { activate(id) } label: {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.title2.weight(.bold))
                Text(title).font(.system(.headline, design: .rounded))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 66)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
            .highlight(state)
        }
        .buttonStyle(PressableStyle())
        .reportFrame(id)
        .accessibilityLabel(title == "Pain" ? "I'm in pain" : (title == "Feel" ? "How I feel" : title))
    }
}

private struct PhraseTile: View {
    let phrase: Phrase
    let state: HighlightState

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: PhraseLibrary.icon(for: phrase.text))
                .font(.system(size: 28))
                .accessibilityHidden(true)
            Text(phrase.text)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.65)
            if phrase.clip != nil {
                Label("My voice", systemImage: "person.wave.2.fill")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.white.opacity(0.2), in: Capsule())
            }
        }
        .foregroundStyle(.white)
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(colors: [Color(hex: 0x6A4CF0), AppTheme.violet],
                           startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
        .shadow(color: AppTheme.violetDeep.opacity(0.18), radius: 8, y: 4)
        .highlight(state)
    }
}

// MARK: - Pain panels

private struct PainWherePanel: View {
    let highlight: (String) -> HighlightState
    let activate: (String) -> Void

    static var scanGroups: [[String]] {
        var groups: [[String]] = []
        let ids = PainArea.board.map { "pain.area.\($0.rawValue)" }
        stride(from: 0, to: ids.count, by: 3).forEach { groups.append(Array(ids[$0..<min($0 + 3, ids.count)])) }
        groups.append(["pain.skip", "pain.cancel"])
        return groups
    }

    var body: some View {
        VStack(spacing: 8) {
            Text("Where does it hurt?")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(AppTheme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            GeometryReader { geo in
                let height = max(AppTheme.minTapSize, (geo.size.height - 3 * 8) / 4)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(PainArea.board) { area in
                        let id = "pain.area.\(area.rawValue)"
                        Button { activate(id) } label: {
                            VStack(spacing: 4) {
                                Image(systemName: area.icon).font(.title3)
                                Text(area.label).font(.headline)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            .foregroundStyle(AppTheme.ink)
                            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
                            .surfaceStyle(radius: AppTheme.controlRadius)
                            .highlight(highlight(id))
                        }
                        .buttonStyle(PressableStyle())
                        .reportFrame(id)
                        .accessibilityLabel(area.label)
                    }
                }
            }
            HStack(spacing: 8) {
                panelButton("pain.skip", "Skip", "forward.fill")
                panelButton("pain.cancel", "Cancel", "xmark")
            }
        }
    }

    private func panelButton(_ id: String, _ title: String, _ icon: String) -> some View {
        Button { activate(id) } label: {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(AppTheme.accent)
                .frame(maxWidth: .infinity, minHeight: AppTheme.minTapSize)
                .background(AppTheme.violetSoft, in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
                .highlight(highlight(id))
        }
        .buttonStyle(PressableStyle())
        .reportFrame(id)
    }
}

private struct PainHowPanel: View {
    let area: PainArea?
    let highlight: (String) -> HighlightState
    let activate: (String) -> Void

    static var scanGroups: [[String]] {
        [PainPhrase.boardLevels.map { "pain.level.\($0)" }, ["pain.skip", "pain.cancel"]]
    }

    private func color(_ level: Int) -> Color {
        switch level {
        case ...3: return AppTheme.mint
        case 4...6: return AppTheme.amber
        default: return AppTheme.coral
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("How bad is it?")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                if let area {
                    Text("\(area.label), from 0 (none) to 10 (the worst)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 8) {
                ForEach(PainPhrase.boardLevels.reversed(), id: \.self) { level in
                    let id = "pain.level.\(level)"
                    Button { activate(id) } label: {
                        HStack {
                            Text("\(level)")
                                .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                                .frame(width: 56)
                            Text(PainPhrase.word(for: level).capitalizedFirstLetter)
                                .font(.title3.weight(.semibold))
                            Spacer()
                            // A simple bar so the level is readable at a glance.
                            Capsule()
                                .fill(.white.opacity(0.85))
                                .frame(width: CGFloat(level) * 9, height: 10)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(color(level), in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
                        .highlight(highlight(id))
                    }
                    .buttonStyle(PressableStyle())
                    .reportFrame(id)
                    .accessibilityLabel("\(level) out of 10, \(PainPhrase.word(for: level))")
                }
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: 8) {
                Button { activate("pain.skip") } label: {
                    Label("Skip", systemImage: "forward.fill")
                        .font(.headline)
                        .foregroundStyle(AppTheme.accent)
                        .frame(maxWidth: .infinity, minHeight: AppTheme.minTapSize)
                        .background(AppTheme.violetSoft, in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
                        .highlight(highlight("pain.skip"))
                }
                .buttonStyle(PressableStyle())
                .reportFrame("pain.skip")
                Button { activate("pain.cancel") } label: {
                    Label("Cancel", systemImage: "xmark")
                        .font(.headline)
                        .foregroundStyle(AppTheme.accent)
                        .frame(maxWidth: .infinity, minHeight: AppTheme.minTapSize)
                        .background(AppTheme.violetSoft, in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
                        .highlight(highlight("pain.cancel"))
                }
                .buttonStyle(PressableStyle())
                .reportFrame("pain.cancel")
            }
        }
    }
}

// MARK: - Feelings panel

/// Nine faces and "a little / just say it / very". One tap on a face says the feeling.
private struct FeelingsPanel: View {
    let intensity: FeelingIntensity
    let highlight: (String) -> HighlightState
    let activate: (String) -> Void

    static var scanGroups: [[String]] {
        var groups: [[String]] = []
        let ids = Feeling.board.map { "feel.\($0.rawValue)" }
        stride(from: 0, to: ids.count, by: 3).forEach { groups.append(Array(ids[$0..<min($0 + 3, ids.count)])) }
        groups.append(FeelingIntensity.allCases.map { "feelint.\($0.rawValue)" } + ["feel.cancel"])
        return groups
    }

    var body: some View {
        VStack(spacing: 8) {
            Text("How do you feel?")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(AppTheme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                ForEach(FeelingIntensity.allCases, id: \.rawValue) { level in
                    let id = "feelint.\(level.rawValue)"
                    Button { activate(id) } label: {
                        Text(level.label)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity, minHeight: AppTheme.minTapSize)
                            .foregroundStyle(intensity == level ? Color.white : AppTheme.accent)
                            .background(intensity == level ? AppTheme.accent : AppTheme.violetSoft,
                                        in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
                            .highlight(highlight(id))
                    }
                    .buttonStyle(PressableStyle())
                    .reportFrame(id)
                    .accessibilityAddTraits(intensity == level ? .isSelected : [])
                }
            }

            GeometryReader { geo in
                let height = max(60, (geo.size.height - 2 * 8) / 3)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(Feeling.board) { feeling in
                        let id = "feel.\(feeling.rawValue)"
                        Button { activate(id) } label: {
                            VStack(spacing: 2) {
                                Text(feeling.emoji)
                                    .font(.system(size: 40))
                                    .accessibilityHidden(true)
                                Text(feeling.label)
                                    .font(.headline)
                                    .foregroundStyle(AppTheme.ink)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
                            .background(feeling.isPleasant ? AppTheme.mint.opacity(0.14) : AppTheme.surface,
                                        in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
                            .shadow(color: AppTheme.violetDeep.opacity(0.06), radius: 6, y: 3)
                            .highlight(highlight(id))
                        }
                        .buttonStyle(PressableStyle())
                        .reportFrame(id)
                        .accessibilityLabel(FeelingPhrase.sentence(feeling, intensity: intensity))
                    }
                }
            }

            Button { activate("feel.cancel") } label: {
                Label("Back to phrases", systemImage: "xmark")
                    .font(.headline)
                    .foregroundStyle(AppTheme.accent)
                    .frame(maxWidth: .infinity, minHeight: AppTheme.minTapSize)
                    .background(AppTheme.violetSoft, in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
                    .highlight(highlight("feel.cancel"))
            }
            .buttonStyle(PressableStyle())
            .reportFrame("feel.cancel")
        }
    }
}

// MARK: - Big text for the listener

/// The last message in very large letters, for a noisy room or someone hard of hearing.
/// "Flip" turns it upside down for a person sitting across the table.
struct BigTextView: View {
    let text: String
    @Environment(\.dismiss) private var dismiss
    @State private var flipped = false

    var body: some View {
        ZStack {
            AppTheme.heroGradient.ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                Text(text)
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .rotationEffect(.degrees(flipped ? 180 : 0))
                    .animation(.easeInOut(duration: 0.35), value: flipped)
                Spacer()
                HStack(spacing: 12) {
                    Button { flipped.toggle() } label: {
                        Label("Flip", systemImage: "arrow.up.arrow.down")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: AppTheme.minTapSize)
                            .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
                    }
                    .accessibilityLabel("Flip the text for someone across from me")
                    Button { dismiss() } label: {
                        Text("Close")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(AppTheme.violetDeep)
                            .frame(maxWidth: .infinity, minHeight: AppTheme.minTapSize)
                            .background(.white, in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
        }
        .accessibilityElement(children: .contain)
        .task {
            // Closes by itself so a hands-free user is never stuck on this screen.
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }
}

// MARK: - Highlighting and frame reporting

/// How a control looks while the head pointer or switch scanning is on it.
struct HighlightState: Equatable {
    var on: Bool
    /// Progress ring 0...1, or nil for a plain outline (a whole row being scanned).
    var progress: Double?
}

struct TileFramesKey: PreferenceKey {
    static let space = "talkBoard"
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Reports this view's frame in the Talk board's coordinate space under `id`.
    func reportFrame(_ id: String) -> some View {
        background(
            GeometryReader { geo in
                Color.clear.preference(key: TileFramesKey.self,
                                       value: [id: geo.frame(in: .named(TileFramesKey.space))])
            }
        )
    }

    /// Reports the frame only while the control can be used, so the head pointer never
    /// dwells on a hidden or disabled control.
    @ViewBuilder
    func reportFrame(_ id: String, when active: Bool) -> some View {
        if active { reportFrame(id) } else { self }
    }

    /// Yellow outline, plus a progress ring when the pointer dwells or the scan is on one item.
    func highlight(_ state: HighlightState) -> some View {
        overlay {
            if state.on {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.yellow, lineWidth: 5)
                    .shadow(color: .yellow.opacity(0.6), radius: 6)
                    .overlay(alignment: .topTrailing) {
                        if let progress = state.progress {
                            Circle()
                                .trim(from: 0, to: CGFloat(min(max(progress, 0), 1)))
                                .stroke(Color.yellow, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .frame(width: 24, height: 24)
                                .padding(6)
                        }
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon
        }
    }
}

private extension String {
    /// "hello there" → "Hello there" (typed messages read better with a capital).
    var capitalizedFirstLetter: String { prefix(1).uppercased() + dropFirst() }
}

#Preview {
    TalkBoardView()
        .modelContainer(for: [Phrase.self, BankedClip.self, Profile.self, CareContact.self, CareEvent.self], inMemory: true)
}
