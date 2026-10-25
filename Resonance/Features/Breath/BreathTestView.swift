//
//  BreathTestView.swift
//  Resonance
//
//  Breath test: take a deep breath and count out loud as far as you can on one breath.
//  Measures the count (from on-device speech recognition) and how long the breath lasted.
//  Saved as a VoiceSession with kind "breath" so it joins Trends and Next Steps.
//

import SwiftUI
import SwiftData
import Observation
import Speech

@MainActor
@Observable
final class BreathTestModel {
    enum Phase: Equatable { case ready, recording, analyzing, done }

    var phase: Phase = .ready
    var message: String?
    private(set) var result: BreathResult?
    private(set) var saved = false
    let recorder = AudioRecorder()

    static let maxSeconds = 60.0
    static let silenceToStop = 2.0

    @ObservationIgnored private var monitor: Task<Void, Never>?

    func start() async {
        message = nil
        guard await AudioRecorder.requestPermission() else {
            message = "Microphone access is off. Turn it on in Settings > Privacy & Security > Microphone > Resonance."
            return
        }
        _ = await Transcriber.requestAuthorization()
        recorder.start(name: "breath")
        guard recorder.isRecording else {
            message = recorder.errorMessage ?? "The microphone could not start. Please try again."
            return
        }
        phase = .recording
        monitor?.cancel()
        monitor = Task { [weak self] in
            var heard = false
            var quietFor = 0.0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self else { return }
                // Stopped from outside (an interruption): finish with what was recorded.
                if !self.recorder.isRecording { await self.finish(); return }
                if self.recorder.level > -45 {
                    heard = true
                    quietFor = 0
                } else if heard {
                    quietFor += 0.1
                }
                if (heard && quietFor >= Self.silenceToStop) || self.recorder.duration >= Self.maxSeconds {
                    await self.finish()
                    return
                }
            }
        }
    }

    func finish() async {
        guard phase == .recording else { return }
        monitor?.cancel()
        let interruption = recorder.errorMessage
        recorder.stop()
        if let interruption {
            // An interrupted test is thrown away (never analyzed or saved); the person can redo it.
            if let url = recorder.fileURL { try? FileManager.default.removeItem(at: url) }
            result = nil
            message = interruption
            phase = .done
            return
        }
        phase = .analyzing
        let samples = recorder.samples
        var transcript: String?
        let speechAllowed = SFSpeechRecognizer.authorizationStatus() == .authorized
        if speechAllowed, Transcriber.supportsOnDevice, let url = recorder.fileURL,
           let segments = try? await Transcriber.transcribe(fileURL: url, allowServer: false) {
            transcript = segments.map(\.word).joined(separator: " ")
        }
        result = await Task.detached(priority: .userInitiated) {
            BreathCountAnalyzer.analyze(transcript: transcript, samples: samples)
        }.value
        // Only the numbers are kept, never the recording.
        if let url = recorder.fileURL { try? FileManager.default.removeItem(at: url) }
        if result?.flags.contains(QualityFlag.noSpeech) == true {
            message = "We couldn't hear counting. Take a deep breath and count out loud, close to the phone."
        } else if result?.count == nil && !speechAllowed {
            message = "Speech recognition is off for Resonance, so only your breath length was measured. You can turn it on in Settings > Privacy & Security > Speech Recognition."
        } else if result?.count == nil {
            message = Transcriber.supportsOnDevice
                ? "We measured your breath length, but couldn't read the numbers. Count clearly: one, two, three…"
                : "This iPhone can't recognize speech on the device, so only your breath length was measured."
        }
        phase = .done
    }

    func redo() {
        monitor?.cancel()
        if recorder.isRecording { recorder.stop() }
        if let url = recorder.fileURL { try? FileManager.default.removeItem(at: url) }
        result = nil
        message = nil
        saved = false
        phase = .ready
    }

    func save(in context: ModelContext) {
        guard !saved, let result, !result.metrics.isEmpty else { return }
        let session = VoiceSession(date: Date(), metrics: result.metrics)
        session.kind = "breath"
        session.qualityFlags = result.flags
        context.insert(session)
        try? context.save()
        saved = true
    }

    func cancel() {
        monitor?.cancel()
        if recorder.isRecording { recorder.stop() }
    }
}

struct BreathTestView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var model = BreathTestModel()
    @State private var breathe = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Text("Count on one breath")
                    .font(.system(.title2, design: .rounded).weight(.bold))

                orb

                switch model.phase {
                case .ready:
                    Text("Take a deep breath. Then count out loud, \"one, two, three…\", at a steady pace, as far as you can on that single breath. Recording stops when you stop.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        Task { await model.start() }
                    } label: {
                        Label("Start", systemImage: "mic.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    WhyThisTestCard(exercise: .breath)

                case .recording:
                    Text("Count out loud: one, two, three…")
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                    LevelMeterView(db: model.recorder.level)
                    Text(String(format: "%.1f s", model.recorder.duration))
                        .font(.system(.title2, design: .rounded).weight(.semibold).monospacedDigit())
                    Button {
                        Task { await model.finish() }
                    } label: {
                        Label("Done", systemImage: "stop.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle(color: AppTheme.danger))

                case .analyzing:
                    Text("Counting your numbers…").font(.title3).foregroundStyle(.secondary)

                case .done:
                    results
                }

                if let message = model.message {
                    Card {
                        Label(message, systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(AppTheme.warning)
                    }
                }
            }
            .padding(AppTheme.padding)
        }
        .screenBackground()
        .navigationTitle("Breath test")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { model.cancel() }
    }

    /// The big circle: shows a count when done, breathes while recording.
    private var orb: some View {
        ZStack {
            if model.phase == .recording {
                Circle()
                    .fill(AppTheme.accent.opacity(0.12))
                    .scaleEffect(breathe ? 1.25 : 1.05)
                    .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: breathe)
                    .onAppear { breathe = true }
                    .onDisappear { breathe = false }
            }
            Circle().fill(model.phase == .recording ? AnyShapeStyle(AppTheme.heroGradient)
                                                      : AnyShapeStyle(AppTheme.violetSoft))
            if model.phase == .analyzing {
                ProgressView().controlSize(.large).tint(AppTheme.accent)
            } else if model.phase == .done, let count = model.result?.count {
                VStack(spacing: 0) {
                    Text("\(count)")
                        .font(.system(size: 56, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(AppTheme.accent)
                    Text("counted").font(.subheadline).foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: model.phase == .recording ? "mic.fill" : "wind")
                    .font(.system(size: 50, weight: .semibold))
                    .foregroundStyle(model.phase == .recording ? .white : AppTheme.accent)
            }
        }
        .frame(width: 170, height: 170)
        .frame(maxWidth: .infinity)
        .accessibilityElement()
        .accessibilityLabel(model.result?.count.map { "Counted to \($0)" } ?? "Breath test")
    }

    @ViewBuilder
    private var results: some View {
        if let result = model.result, !result.metrics.isEmpty {
            ResultInterpretationList(latest: result.metrics, keys: Exercise.breath.metricKeys)

            // PLAN.pdf Section 11: a low count shows the breathing safety message, saved or not.
            if let count = result.count, Double(count) < NextStepsEngine.lowBreathCount {
                Card {
                    Label(BreathingSafety.message, systemImage: "lungs.fill")
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .overlay(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                    .stroke(AppTheme.coral.opacity(0.5), lineWidth: 2))
            }

            Card {
                Label("How to read this", systemImage: "info.circle.fill")
                    .font(.headline)
                    .foregroundStyle(AppTheme.accent)
                Text("What matters most is your own trend: compare with your earlier tests, done the same way. If your count drops over a few weeks, or is under \(Int(NextStepsEngine.lowBreathCount)), mention it to your care team.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                Button("Redo") { model.redo() }
                    .buttonStyle(SecondaryButtonStyle())
                if model.saved {
                    Button("Done") { dismiss() }
                        .buttonStyle(PrimaryButtonStyle())
                } else {
                    Button("Save") { model.save(in: modelContext) }
                        .buttonStyle(PrimaryButtonStyle())
                }
            }

            if model.saved {
                NextStepsPanel(limit: 3)
                    .padding(.top, 8)
            }
        } else {
            Button("Try again") { model.redo() }
                .buttonStyle(PrimaryButtonStyle())
        }
    }
}

#Preview {
    NavigationStack { BreathTestView() }
        .modelContainer(for: [VoiceSession.self, MotorSession.self, FunctionCheck.self, Phrase.self, Profile.self], inMemory: true)
}
