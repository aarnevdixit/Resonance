//
//  VoiceLabFlowView.swift
//  Resonance
//
//  The Voice Lab screens (PLAN.pdf Section 9): big cues, a live level meter,
//  countdowns, automatic stopping, redo buttons, and a results summary.
//

import SwiftUI
import SwiftData

struct VoiceLabFlowView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var model = VoiceLabModel()

    var body: some View {
        VStack(spacing: 0) {
            ProgressView(value: model.progress)
                .tint(AppTheme.accent)
                .padding(.horizontal, AppTheme.padding)
                .padding(.top, 8)
                .accessibilityLabel("Voice Lab progress")

            ScrollView {
                VStack(spacing: 20) {
                    switch model.step {
                    case .intro: intro
                    case .calibration: calibration
                    case .vowel: vowelTask
                    case .vowelEee: eeeTask
                    case .ddk: ddkTask
                    case .reading: readingTask
                    case .results: results
                    }

                    // "Why this test?" before each recording, so every task has a purpose.
                    if let exercise = currentExercise, model.taskState == .ready {
                        WhyThisTestCard(exercise: exercise)
                    }

                    if let message = model.message {
                        Card {
                            Text(message).foregroundStyle(AppTheme.warning)
                        }
                    }
                    if let problem = model.permissionProblem {
                        Card {
                            Text(problem).foregroundStyle(AppTheme.warning)
                        }
                    }
                }
                .padding(AppTheme.padding)
            }
        }
        .screenBackground()
        .navigationTitle("Voice Lab")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { model.cancel() }
        .confirmationDialog(
            "On-device speech recognition isn't available on this iPhone.",
            isPresented: $model.askServerTranscription,
            titleVisibility: .visible
        ) {
            Button("Use Apple's speech recognition") {
                model.askServerTranscription = false
                Task { await model.finishReading(allowServer: true) }
            }
            Button("Skip, keep everything on this iPhone", role: .cancel) {
                model.skipTranscription()
            }
        } message: {
            Text("To measure reading speed and word clarity, this recording would be sent to Apple for transcription. Everything else stays on this iPhone.")
        }
    }

    // MARK: Steps

    private var intro: some View {
        VStack(spacing: 20) {
            IconBadge(systemImage: "waveform", size: 88)
                .padding(.top, 8)
            Text("Four short voice tasks, about 3 minutes.")
                .font(.system(.title2, design: .rounded).weight(.bold))
                .multilineTextAlignment(.center)
            Card {
                Label("Find a quiet room.", systemImage: "speaker.slash")
                Label("Hold the phone about one foot (30 cm) from your mouth.", systemImage: "ruler")
                Label("Use the same room and distance each week.", systemImage: "calendar")
            }
            .font(.title3)
            Button("Start") {
                Task { await model.begin() }
            }
            .buttonStyle(PrimaryButtonStyle())
            Card {
                Text("What you'll do").font(.headline)
                ForEach([Exercise.ahh, .eee, .pataka, .reading]) { exercise in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(AppTheme.accent)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(exercise.title).font(.body.weight(.semibold))
                            Text("Checks: \(exercise.tests)").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private var currentExercise: Exercise? {
        switch model.step {
        case .vowel: return .ahh
        case .vowelEee: return .eee
        case .ddk: return .pataka
        case .reading: return .reading
        default: return nil
        }
    }

    private var calibration: some View {
        VStack(spacing: 20) {
            IconBadge(systemImage: "ear.fill", size: 88)
                .padding(.top, 8)
            Text("Checking the room")
                .font(.system(.title, design: .rounded).weight(.bold))
            if model.taskState == .recording {
                Text("Please stay quiet for a moment…")
                    .font(.title3)
                ProgressView().controlSize(.large)
            } else if model.taskState == .ready {
                // The microphone did not start; the reason is shown in the message card below.
                Button("Try again") { model.startCalibration() }
                    .buttonStyle(PrimaryButtonStyle())
            } else {
                if model.tooNoisy {
                    Text("It's a bit noisy here. Try a quieter room if you can.")
                        .font(.title3)
                        .foregroundStyle(AppTheme.warning)
                        .multilineTextAlignment(.center)
                } else {
                    Label("The room is quiet enough.", systemImage: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(AppTheme.mint)
                }
                HStack(spacing: 12) {
                    Button("Check again") { model.startCalibration() }
                        .buttonStyle(SecondaryButtonStyle())
                    Button("Continue") { model.next() }
                        .buttonStyle(PrimaryButtonStyle())
                }
            }
        }
    }

    private var vowelTask: some View {
        TaskScreen(
            title: "Task 1 of 4: Hold \"ahh\"",
            instructions: "Take a deep breath, then say \"ahh\" steadily for as long as you comfortably can. Recording stops by itself when you finish.",
            model: model,
            start: { model.startVowel() },
            stop: { model.finishVowel() },
            cue: "ahh",
            resultText: model.vowel.map { result in
                if result.mpt < 0.3 { return "We couldn't hear a held \"ahh\"." }
                var lines = [String(format: "You held it for %.1f seconds.", result.mpt)]
                if let f0 = result.f0Mean { lines.append(String(format: "Average pitch: %.0f Hz", f0)) }
                return lines.joined(separator: "\n")
            }
        )
    }

    private var eeeTask: some View {
        TaskScreen(
            title: "Task 2 of 4: Hold \"eee\"",
            instructions: "Now say \"eee\", as in \"see\", steadily for a few seconds. Smile a little to keep the sound bright.",
            model: model,
            start: { model.startVowel() },
            stop: { model.finishVowel() },
            cue: "eee",
            resultText: model.taskState == .done ? eeeResultText : nil
        )
    }

    private var eeeResultText: String {
        guard let eee = model.eeeAnalysis else {
            return "We couldn't hear a steady \"eee\". You can try again, or continue."
        }
        var lines = ["Got it."]
        if let f2 = eee.f2 {
            lines.append(String(format: "Tongue reach (F2): %.2f kHz", f2))
        }
        return lines.joined(separator: "\n")
    }

    private var ddkTask: some View {
        TaskScreen(
            title: "Task 3 of 4: \"pa-ta-ka\"",
            instructions: "Say \"pa-ta-ka\" over and over, as quickly and clearly as you can, until the timer ends.",
            model: model,
            start: { model.startDDK() },
            stop: { model.finishDDK() },
            showCountdown: true,
            cue: "pa-ta-ka",
            resultText: model.ddk.map { result in
                if let rate = result.rate {
                    return String(format: "%.1f syllables per second.", rate)
                }
                return "We couldn't count the syllables this time."
            }
        )
    }

    private var readingTask: some View {
        VStack(spacing: 16) {
            TaskScreen(
                title: "Task 4 of 4: Read aloud",
                instructions: "Tap Start, then read the passage below at your normal pace. Tap Done when you finish.",
                model: model,
                start: { model.startReading() },
                stop: { Task { await model.finishReading() } },
                stopLabel: "Done",
                resultText: model.reading.map { result in
                    if model.transcriptSkipped {
                        return "Reading speed and word clarity weren't measured this time."
                    }
                    if result.flags.contains(QualityFlag.noSpeech) {
                        return "We couldn't hear the reading, so nothing was measured."
                    }
                    var lines: [String] = []
                    if let wpm = result.wpm { lines.append(String(format: "Speaking rate: %.0f words per minute", wpm)) }
                    lines.append(String(format: "Word clarity: %.0f%%", result.intelligibility))
                    return lines.joined(separator: "\n")
                }
            )
            Card {
                Text(ReadingPassage.text)
                    .font(.title3)
                    .lineSpacing(6)
            }
            if let reading = model.reading, !model.transcriptSkipped,
               !reading.flags.contains(QualityFlag.noSpeech), !reading.missedWords.isEmpty {
                Card {
                    Text("Words the recognizer didn't catch").font(.headline)
                    Text(reading.missedWords.joined(separator: ", "))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var results: some View {
        let measured = !model.allMetrics.isEmpty
        return VStack(spacing: 20) {
            Image(systemName: measured ? "checkmark.seal.fill" : "mic.slash.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(measured ? AppTheme.mint : AppTheme.amber)
                .accessibilityHidden(true)
            Text(model.saved ? "Saved" : (measured ? "All done" : "Nothing measured"))
                .font(.system(.title, design: .rounded).weight(.bold))

            if measured {
                ResultInterpretationList(latest: model.allMetrics, keys: headlineKeys)

                if let score = model.speechChangeScore {
                    SpeechChangeScoreCard(score: score)
                }

                DisclosureGroup("All measurements") {
                    ForEach(metricDefs.filter { $0.domain == .speech }) { def in
                        if let value = model.allMetrics[def.key] {
                            HStack {
                                Text(def.name)
                                Spacer()
                                Text("\(formatted(value)) \(def.unit)").monospacedDigit()
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .padding(AppTheme.padding)
                .surfaceStyle()

                Text("These are estimates from a phone microphone. They are most useful compared with your own past results, and they are not a diagnosis.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                // Nothing usable was recorded: don't save an empty check-in.
                Card {
                    Text("We couldn't hear your voice clearly enough to measure anything this time. Check that the microphone isn't covered, find a quiet room, and try again.")
                        .font(.title3)
                }
            }

            if model.saved || !measured {
                Button("Close") { dismiss() }
                    .buttonStyle(PrimaryButtonStyle())
            } else {
                Button("Save results") {
                    model.save(in: modelContext)
                }
                .buttonStyle(PrimaryButtonStyle())
            }

            if model.saved {
                NextStepsPanel(limit: 3)
                    .padding(.top, 8)
            }
        }
    }

    /// One key measure from each task, explained on the results screen.
    private let headlineKeys = [MetricKey.mpt, MetricKey.f2Eee, MetricKey.ddkRate,
                                MetricKey.wpm, MetricKey.intelligibility]

    private func formatted(_ value: Double) -> String {
        abs(value) >= 100 ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }
}

/// Shared layout for the three recording tasks.
private struct TaskScreen: View {
    let title: String
    let instructions: String
    let model: VoiceLabModel
    let start: () -> Void
    let stop: () -> Void
    var stopLabel: String = "Stop"
    var showCountdown: Bool = false
    /// The sound to make, shown large in the center ("ahh", "eee", "pa-ta-ka").
    var cue: String? = nil
    let resultText: String?

    var body: some View {
        VStack(spacing: 18) {
            Text(title)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .multilineTextAlignment(.center)

            CueOrb(cue: cue, state: model.taskState, level: model.recorder.level,
                   needsRetry: model.message != nil)
                .padding(.vertical, 6)

            switch model.taskState {
            case .ready:
                Text(instructions)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    start()
                } label: {
                    Label("Start", systemImage: "mic.fill")
                }
                .buttonStyle(PrimaryButtonStyle())

            case .recording:
                LevelMeterView(db: model.recorder.level)
                Text(showCountdown
                     ? secondsLeft(model.countdown)
                     : String(format: "%.1f s", model.recorder.duration))
                    .font(.system(.title2, design: .rounded).weight(.semibold).monospacedDigit())
                    .contentTransition(.numericText())
                Button {
                    stop()
                } label: {
                    Label(stopLabel, systemImage: "stop.fill")
                }
                .buttonStyle(PrimaryButtonStyle(color: AppTheme.danger))

            case .analyzing:
                Text("Analyzing…")
                    .font(.title3)
                    .foregroundStyle(.secondary)

            case .done:
                if let resultText {
                    Card {
                        Text(resultText).font(.title3)
                    }
                }
                HStack(spacing: 12) {
                    Button("Redo") { model.redo() }
                        .buttonStyle(SecondaryButtonStyle())
                    Button("Next") { model.next() }
                        .buttonStyle(PrimaryButtonStyle())
                }
            }
        }
    }
}

/// The big circle in the middle of each voice task. It shows the sound to make, breathes
/// with your voice while recording, spins while analyzing, and shows a check when done.
private struct CueOrb: View {
    let cue: String?
    let state: VoiceLabModel.TaskState
    let level: Float
    var needsRetry = false

    @State private var breathe = false

    /// 0...1 loudness from the live level in dBFS.
    private var loudness: CGFloat {
        CGFloat(min(max((level + 60) / 50, 0), 1))
    }

    var body: some View {
        ZStack {
            if state == .recording {
                Circle()
                    .fill(AppTheme.accent.opacity(0.12))
                    .scaleEffect(1.05 + loudness * 0.3)
                    .animation(.easeOut(duration: 0.12), value: loudness)
                Circle()
                    .stroke(AppTheme.accent.opacity(0.25), lineWidth: 2)
                    .scaleEffect(breathe ? 1.25 : 1.0)
                    .opacity(breathe ? 0 : 1)
                    .animation(.easeOut(duration: 1.4).repeatForever(autoreverses: false), value: breathe)
            }
            Circle()
                .fill(state == .recording ? AnyShapeStyle(AppTheme.heroGradient) : AnyShapeStyle(AppTheme.violetSoft))
            Group {
                switch state {
                case .analyzing:
                    ProgressView().controlSize(.large).tint(AppTheme.accent)
                case .done:
                    Image(systemName: needsRetry ? "arrow.counterclockwise" : "checkmark")
                        .font(.system(size: 56, weight: .bold))
                        .foregroundStyle(needsRetry ? AppTheme.amber : AppTheme.mint)
                        .transition(.scale.combined(with: .opacity))
                default:
                    if let cue {
                        Text(cue)
                            .font(.system(size: cue.count > 4 ? 34 : 50, weight: .bold, design: .rounded))
                            .foregroundStyle(state == .recording ? .white : AppTheme.accent)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                            .padding(.horizontal, 18)
                    } else {
                        Image(systemName: state == .recording ? "mic.fill" : "text.book.closed.fill")
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundStyle(state == .recording ? .white : AppTheme.accent)
                    }
                }
            }
        }
        // Smaller for the reading task, so the passage stays on screen.
        .animation(.easeInOut(duration: 0.3), value: state)
        .frame(width: cue == nil ? 96 : 170, height: cue == nil ? 96 : 170)
        .frame(maxWidth: .infinity)
        .onAppear { breathe = true }
        .accessibilityElement()
        .accessibilityLabel(state == .recording ? "Recording" : (cue.map { "Say \($0)" } ?? "Voice task"))
    }
}

/// The AI Speech Change Score with the required wording (PLAN.pdf Section 21).
struct SpeechChangeScoreCard: View {
    let score: Double

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                Label(SpeechChangeModel.title, systemImage: "sparkles")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(AppTheme.accent)
                Spacer()
                Text("\(Int(score.rounded()))")
                    .font(.system(size: 36, weight: .bold, design: .rounded).monospacedDigit())
                Text("/100").foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppTheme.violetSoft)
                    Capsule().fill(AppTheme.accent)
                        .frame(width: max(8, geo.size.width * score / 100))
                }
            }
            .frame(height: 10)
            .accessibilityHidden(true)
            Text(SpeechChangeModel.explanation)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(SpeechChangeModel.title), \(Int(score.rounded())) out of 100. \(SpeechChangeModel.explanation)")
    }
}

#Preview {
    NavigationStack { VoiceLabFlowView() }
        .modelContainer(for: VoiceSession.self, inMemory: true)
}
