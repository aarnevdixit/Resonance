//
//  VoiceBankView.swift
//  Resonance
//
//  Voice Bank (PLAN.pdf Section 14): keep sounding like yourself.
//  - Recording studio: one phrase at a time, big and simple, with a level meter,
//    playback, and Keep / Redo / Skip. Silent or too-short recordings are refused.
//  - Every Talk board phrase by category, with play, re-record and delete.
//  - Add personal phrases (names, sayings, a laugh); suggestions to get started.
//  - Apple Personal Voice: status, setup steps, and permission for Resonance to use it.
//

import SwiftUI
import SwiftData
import AVFoundation

struct VoiceBankView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\Phrase.category), SortDescriptor(\Phrase.order)]) private var phrases: [Phrase]
    @Query private var profiles: [Profile]

    @State private var recorder = ClipRecorder()
    @State private var personalStatus = SpeechOutput.personalVoiceStatusText
    @State private var newPhrase = ""
    @State private var showSetupSteps = false
    @State private var showStudio = false
    @State private var expanded: Set<String> = ["Needs"]
    @State private var backupURL: URL?
    @State private var makingBackup = false
    @State private var backupError: String?

    private var recorded: Int { phrases.filter { $0.clip != nil }.count }

    private let suggestions = ["Good morning, sweetheart", "I love you so much", "That's hilarious!",
                               "Ha ha ha", "Give me a hug", "Goodnight, sleep well", "You're the best",
                               "Hey, how was your day?"]

    var body: some View {
        List {
            Section {
                progressHeader
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }

            Section {
                ForEach(PhraseLibrary.categories, id: \.self) { category in
                    let items = phrases.filter { $0.category == category }
                    if !items.isEmpty {
                        DisclosureGroup(isExpanded: Binding(
                            get: { expanded.contains(category) },
                            set: { if $0 { expanded.insert(category) } else { expanded.remove(category) } })) {
                            ForEach(items) { phrase in
                                PhraseRecordRow(phrase: phrase, recorder: recorder) { fileName in
                                    attach(fileName, to: phrase)
                                } onDelete: {
                                    removeClip(from: phrase)
                                }
                            }
                        } label: {
                            HStack {
                                Text(PhraseLibrary.displayName(category))
                                    .font(.headline)
                                    .foregroundStyle(AppTheme.ink)
                                Spacer()
                                Text("\(items.filter { $0.clip != nil }.count) of \(items.count)")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .frame(minHeight: AppTheme.minTapSize)
                        }
                    }
                }
                if let error = recorder.errorMessage {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(AppTheme.warning)
                }
            } header: {
                Text("Every phrase")
            } footer: {
                Text("Tap the microphone, say the phrase, then tap stop. Tiles with your recording show \"My voice\" on the Talk board.")
            }

            Section {
                TextField("New phrase, e.g. \"Good morning, Marcus\"", text: $newPhrase)
                    .frame(minHeight: AppTheme.minTapSize)
                Button("Add to my phrases") { addPhrase(newPhrase) }
                    .fontWeight(.semibold)
                    .frame(minHeight: AppTheme.minTapSize)
                    .disabled(newPhrase.trimmingCharacters(in: .whitespaces).isEmpty)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions.filter { s in !phrases.contains { $0.text == s } }, id: \.self) { text in
                            Button {
                                addPhrase(text)
                            } label: {
                                Label(text, systemImage: "plus")
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .frame(minHeight: AppTheme.minTapSize)
                                    .foregroundStyle(AppTheme.accent)
                                    .background(AppTheme.violetSoft, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Your own phrases")
            } footer: {
                Text("The words only you say: names of family, a favorite saying, an inside joke, your laugh. They go to \"Mine\" on the Talk board.")
            }

            if recorded > 0 { backupSection }

            personalVoiceSection
        }
        .tint(AppTheme.accent)
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Voice Bank")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .fullScreenCover(isPresented: $showStudio) {
            RecordingStudioView()
        }
        .onDisappear { recorder.cancel() }
        // A new or deleted recording makes an earlier backup out of date.
        .onChange(of: recorded) { _, _ in backupURL = nil }
    }

    // MARK: Backup

    private var backupSection: some View {
        Section {
            if let backupURL {
                ShareLink(item: backupURL) {
                    Label("Save or send the backup", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: AppTheme.minTapSize, alignment: .leading)
                }
                .accessibilityHint("Opens the share sheet. Choose Save to Files, AirDrop or Messages.")
            } else {
                Button(action: makeBackup) {
                    HStack(spacing: 12) {
                        if makingBackup {
                            ProgressView()
                        } else {
                            Image(systemName: "externaldrive.fill.badge.checkmark")
                                .foregroundStyle(AppTheme.accent)
                        }
                        Text(makingBackup ? "Making the backup…" : "Back up my voice")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity, minHeight: AppTheme.minTapSize, alignment: .leading)
                }
                .disabled(makingBackup)
            }
            if let backupError {
                Label(backupError, systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(AppTheme.warning)
            }
        } header: {
            Text("Keep your voice safe")
        } footer: {
            Text("Puts all \(recorded) recording\(recorded == 1 ? "" : "s") in one file. Save it to Files, iCloud Drive, a computer or a family member's phone, so your voice isn't lost with this iPhone. Nothing is sent anywhere unless you choose.")
        }
    }

    private func makeBackup() {
        backupError = nil
        let items = phrases.compactMap { phrase in
            phrase.clip.map { VoiceBackup.Item(fileName: $0.fileName, label: phrase.text) }
        }
        guard let directory = try? BankFiles.directory() else {
            backupError = VoiceBackup.BackupError.couldNotPack.errorDescription
            return
        }
        makingBackup = true
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try VoiceBackup.makeArchive(items: items, bankDirectory: directory) }
            }.value
            makingBackup = false
            switch result {
            case .success(let url): backupURL = url
            case .failure(let error): backupError = error.localizedDescription
            }
        }
    }

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                ZStack {
                    Circle().stroke(.white.opacity(0.2), lineWidth: 9)
                    Circle()
                        .trim(from: 0, to: CGFloat(recorded) / CGFloat(max(phrases.count, 1)))
                        .stroke(.white, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "person.wave.2.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                }
                .frame(width: 76, height: 76)
                .accessibilityHidden(true)   // the text next to it says the same
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(recorded) of \(phrases.count) in your voice")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)
                    Text("Record now, while your voice feels strong. Later, the Talk board plays these recordings instead of a computer voice.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button {
                showStudio = true
            } label: {
                Label(recorded == 0 ? "Start recording" : "Keep recording", systemImage: "mic.fill")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(AppTheme.violetDeep)
                    .frame(maxWidth: .infinity, minHeight: AppTheme.minTapSize)
                    .background(.white, in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
            }
            .buttonStyle(PressableStyle())
            .disabled(recorded == phrases.count && !phrases.isEmpty)
        }
        .padding(20)
        .background(AppTheme.heroGradient, in: RoundedRectangle(cornerRadius: AppTheme.heroRadius, style: .continuous))
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }

    private var personalVoiceSection: some View {
        Section {
            HStack {
                Text("Status")
                Spacer()
                Text(personalStatus).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
            }
            Button("Allow Resonance to use my Personal Voice") {
                Task {
                    _ = await SpeechOutput.requestPersonalVoiceAccess()
                    personalStatus = SpeechOutput.personalVoiceStatusText
                }
            }
            .frame(minHeight: AppTheme.minTapSize)
            Button("Test my voice") {
                SpeechOutput.shared.speak("Hello, this is my voice.",
                                          preferPersonalVoice: profiles.first?.preferPersonalVoice ?? true,
                                          rate: Float(profiles.first?.speechRate ?? 0.45))
            }
            .frame(minHeight: AppTheme.minTapSize)
            .disabled(recorder.isRecording)
            DisclosureGroup(isExpanded: $showSetupSteps) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("1. Open Settings > Accessibility > Personal Voice.")
                    Text("2. Tap Create a Personal Voice and read the prompts (about 15 minutes).")
                    Text("3. Leave the iPhone charging and locked while it processes. This can take hours.")
                    Text("4. In the same screen, turn on Allow Apps to Request to Use.")
                    Text("5. Come back here and tap Allow Resonance to use my Personal Voice.")
                }
                .font(.callout)
            } label: {
                Text("How to create a Personal Voice")
                    .frame(minHeight: AppTheme.minTapSize)
            }
        } header: {
            Text("Apple Personal Voice")
        } footer: {
            Text("A computer voice that sounds like you, made on your iPhone. It can say anything you type. Recording it early, while your voice is strong, keeps it closest to your natural voice.")
        }
    }

    private func attach(_ fileName: String, to phrase: Phrase) {
        removeClip(from: phrase)
        let clip = BankedClip(fileName: fileName, label: phrase.text)
        modelContext.insert(clip)
        phrase.clip = clip
        try? modelContext.save()
    }

    private func removeClip(from phrase: Phrase) {
        guard let clip = phrase.clip else { return }
        if let url = try? BankFiles.url(for: clip.fileName) {
            try? FileManager.default.removeItem(at: url)
        }
        phrase.clip = nil
        modelContext.delete(clip)
        try? modelContext.save()
    }

    private func addPhrase(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !phrases.contains(where: { $0.text == text }) else { return }
        let order = (phrases.filter { $0.category == "Custom" }.map(\.order).max() ?? -1) + 1
        modelContext.insert(Phrase(text: text, category: "Custom", order: order))
        try? modelContext.save()
        newPhrase = ""
        expanded.insert("Custom")
    }
}

private struct PhraseRecordRow: View {
    let phrase: Phrase
    let recorder: ClipRecorder
    let onRecorded: (String) -> Void
    let onDelete: () -> Void

    private var key: PersistentIdentifierBox { PersistentIdentifierBox(key: phrase.text) }
    private var isRecordingThis: Bool { recorder.isRecording && recorder.recordingFor == key }
    @State private var confirmDelete = false

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(phrase.text)
                    .foregroundStyle(AppTheme.ink)
                if isRecordingThis {
                    LevelBar(level: recorder.level)
                        .frame(height: 6)
                } else if phrase.clip != nil {
                    Label("My voice", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(AppTheme.mint)
                }
            }
            Spacer()
            if phrase.clip != nil && !isRecordingThis {
                Button {
                    SpeechOutput.shared.speak(phrase.text, clipFileName: phrase.clip?.fileName)
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: AppTheme.minTapSize, height: AppTheme.minTapSize)
                }
                .accessibilityLabel("Play my recording of \(phrase.text)")
                // Playing another clip would stop a recording in progress.
                .disabled(recorder.isRecording)
                Button(role: .destructive) { confirmDelete = true } label: {
                    Image(systemName: "trash")
                        .font(.title3)
                        .foregroundStyle(AppTheme.danger)
                        .frame(width: AppTheme.minTapSize, height: AppTheme.minTapSize)
                }
                .disabled(recorder.isRecording)
                .accessibilityLabel("Delete my recording of \(phrase.text)")
                .confirmationDialog("Delete your recording of \"\(phrase.text)\"? You may not be able to record it the same way again.",
                                    isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete recording", role: .destructive) { onDelete() }
                }
            }
            Button {
                if isRecordingThis {
                    if let name = recorder.stop() { onRecorded(name) }
                } else if !recorder.isRecording {
                    Task {
                        guard await AudioRecorder.requestPermission() else {
                            recorder.errorMessage = "Microphone access is off. Turn it on in Settings > Privacy & Security > Microphone."
                            return
                        }
                        _ = recorder.start(for: key)
                    }
                }
            } label: {
                Image(systemName: isRecordingThis ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(isRecordingThis ? AppTheme.danger : AppTheme.accent)
                    .symbolEffect(.pulse, isActive: isRecordingThis)
                    .frame(width: AppTheme.minTapSize, height: AppTheme.minTapSize)
            }
            .accessibilityLabel(isRecordingThis ? "Stop recording" : (phrase.clip == nil ? "Record \(phrase.text) in my voice" : "Record \(phrase.text) again"))
        }
        .buttonStyle(.borderless)
        .frame(minHeight: AppTheme.minTapSize)
    }
}

/// Thin live loudness bar for recording.
struct LevelBar: View {
    let level: Float

    var body: some View {
        GeometryReader { geo in
            let fraction = CGFloat(min(max((level + 60) / 60, 0), 1))
            ZStack(alignment: .leading) {
                Capsule().fill(AppTheme.violetSoft)
                Capsule().fill(fraction > 0.85 ? AppTheme.amber : AppTheme.mint)
                    .frame(width: geo.size.width * fraction)
                    .animation(.linear(duration: 0.05), value: fraction)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Recording studio

/// One phrase at a time: say it, hear it, keep it.
struct RecordingStudioView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Phrase.category), SortDescriptor(\Phrase.order)]) private var phrases: [Phrase]

    @State private var recorder = ClipRecorder()
    @State private var skipped: Set<String> = []
    @State private var pendingFile: String?
    @State private var keptThisSession = 0

    /// Most useful first: needs and replies, then feelings, people, and the person's own.
    private static let categoryOrder = ["Needs", "Replies", "Feelings", "People", "Custom"]

    private var queue: [Phrase] {
        phrases
            .filter { $0.clip == nil && !skipped.contains($0.text) }
            .sorted {
                let a = Self.categoryOrder.firstIndex(of: $0.category) ?? 9
                let b = Self.categoryOrder.firstIndex(of: $1.category) ?? 9
                return a == b ? $0.order < $1.order : a < b
            }
    }

    private var current: Phrase? { queue.first }
    private var recordedTotal: Int { phrases.filter { $0.clip != nil }.count }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                ProgressView(value: Double(recordedTotal), total: Double(max(phrases.count, 1)))
                    .tint(AppTheme.accent)
                Text("\(recordedTotal) of \(phrases.count) recorded")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)

                if let current {
                    Spacer(minLength: 0)
                    Text(PhraseLibrary.displayName(current.category))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                        .accessibilityHidden(true)
                    Text("\u{201C}\(current.text)\u{201D}")
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(AppTheme.ink)
                        .minimumScaleFactor(0.5)
                        .padding(.horizontal)
                        .accessibilityLabel("Say: \(current.text)")
                    Text(pendingFile == nil
                         ? "Say it the way you would to someone you love."
                         : "Listen back. Keep it, or record again.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)

                    if recorder.isRecording {
                        LevelBar(level: recorder.level)
                            .frame(height: 10)
                            .padding(.horizontal, 40)
                        Text(String(format: "%.1f s", recorder.seconds))
                            .font(.headline.monospacedDigit())
                    }
                    if let error = recorder.errorMessage {
                        Label(error, systemImage: "exclamationmark.circle.fill")
                            .font(.callout)
                            .foregroundStyle(AppTheme.warning)
                            .multilineTextAlignment(.center)
                    }

                    controls(for: current)
                } else {
                    Spacer()
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(AppTheme.mint)
                        .accessibilityHidden(true)
                    Text(skipped.isEmpty ? "Every phrase is in your voice" : "That's all for now")
                        .font(.system(.title, design: .rounded).weight(.bold))
                    Text(keptThisSession == 1 ? "You recorded 1 phrase this time." : "You recorded \(keptThisSession) phrases this time.")
                        .foregroundStyle(.secondary)
                    if !skipped.isEmpty {
                        Button("Go back to the ones I skipped") { skipped = [] }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                    Spacer()
                    Button("Done") { dismiss() }
                        .buttonStyle(PrimaryButtonStyle())
                }
            }
            .padding(AppTheme.padding)
            .screenBackground()
            .navigationTitle("Recording studio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onDisappear {
                recorder.cancel()
                discardPending()
            }
        }
    }

    @ViewBuilder
    private func controls(for phrase: Phrase) -> some View {
        if let pendingFile {
            HStack(spacing: 12) {
                Button {
                    SpeechOutput.shared.speak(phrase.text, clipFileName: pendingFile)
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .buttonStyle(SecondaryButtonStyle())
                Button {
                    discardPending()
                } label: {
                    Label("Redo", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            Button {
                keep(pendingFile, for: phrase)
            } label: {
                Label("Keep and go on", systemImage: "checkmark")
            }
            .buttonStyle(PrimaryButtonStyle(color: AppTheme.mint))
        } else {
            Button {
                toggleRecording(for: phrase)
            } label: {
                ZStack {
                    Circle()
                        .fill(recorder.isRecording ? AppTheme.coral : AppTheme.accent)
                        .frame(width: 96, height: 96)
                        .shadow(color: (recorder.isRecording ? AppTheme.coral : AppTheme.accent).opacity(0.35), radius: 12, y: 6)
                    Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(recorder.isRecording ? "Stop recording" : "Record")
            Button("Skip this one") {
                recorder.cancel()
                skipped.insert(phrase.text)
            }
            .font(.headline)
            .frame(minHeight: AppTheme.minTapSize)
            .disabled(recorder.isRecording)
        }
    }

    private func toggleRecording(for phrase: Phrase) {
        if recorder.isRecording {
            pendingFile = recorder.stop()
            if let pendingFile { SpeechOutput.shared.speak(phrase.text, clipFileName: pendingFile) }
        } else {
            Task {
                guard await AudioRecorder.requestPermission() else {
                    recorder.errorMessage = "Microphone access is off. Turn it on in Settings > Privacy & Security > Microphone."
                    return
                }
                SpeechOutput.shared.stop()
                _ = recorder.start(for: PersistentIdentifierBox(key: phrase.text))
            }
        }
    }

    private func keep(_ fileName: String, for phrase: Phrase) {
        if let old = phrase.clip {
            if let url = try? BankFiles.url(for: old.fileName) { try? FileManager.default.removeItem(at: url) }
            modelContext.delete(old)
        }
        let clip = BankedClip(fileName: fileName, label: phrase.text)
        modelContext.insert(clip)
        phrase.clip = clip
        try? modelContext.save()
        pendingFile = nil
        keptThisSession += 1
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func discardPending() {
        guard let pendingFile else { return }
        if let url = try? BankFiles.url(for: pendingFile) { try? FileManager.default.removeItem(at: url) }
        self.pendingFile = nil
    }
}

#Preview {
    NavigationStack { VoiceBankView() }
        .modelContainer(for: [Phrase.self, BankedClip.self, Profile.self], inMemory: true)
}
