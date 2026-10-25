//
//  VoiceLabModel.swift
//  Resonance
//
//  Runs the Voice Lab flow (PLAN.pdf Section 9):
//  intro -> quiet calibration -> Task A (held "ahh") -> Task A2 (held "eee")
//  -> Task B ("pa-ta-ka") -> Task C (reading) -> results, then saves a VoiceSession.
//
//  Change from the plan: the plan had one held vowel. A held "eee" was added because the
//  tongue position it needs (its second formant, F2) carries information the "ahh" lacks,
//  and the Speech Change model uses both vowels.
//

import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class VoiceLabModel {

    enum Step: Int, CaseIterable {
        case intro, calibration, vowel, vowelEee, ddk, reading, results
    }

    enum TaskState: Equatable {
        case ready, recording, analyzing, done
    }

    // MARK: State the UI reads

    var step: Step = .intro
    var taskState: TaskState = .ready
    var message: String?
    var permissionProblem: String?
    var askServerTranscription = false

    let recorder = AudioRecorder()

    private(set) var noiseFloor: Float = -60
    private(set) var tooNoisy = false
    private(set) var vowel: VowelResult?
    /// Model inputs from the held "ahh" and "eee" (nil if unusable), and the AI Speech Change Score.
    private(set) var ahhAnalysis: VowelAnalysis?
    private(set) var eeeAnalysis: VowelAnalysis?
    private(set) var eeeFile: String?
    private(set) var speechChangeScore: Double?
    private(set) var ddk: DDKResult?
    private(set) var reading: ReadingResult?
    /// True when the words weren't recognized for a reason other than the person's speech
    /// (skipped, permission off, recognizer unavailable or timed out).
    private(set) var transcriptSkipped = false
    private(set) var vowelFile: String?
    private(set) var ddkFile: String?
    private(set) var readingFile: String?
    private(set) var saved = false

    /// Seconds remaining for timed tasks (pa-ta-ka).
    private(set) var countdown: Double = 0

    // MARK: Settings

    static let calibrationSeconds = 1.2
    static let vowelMaxSeconds = 30.0
    static let vowelSilenceToStop = 1.5
    static let ddkSeconds = 8.0
    static let readingMaxSeconds = 90.0

    @ObservationIgnored private var monitorTask: Task<Void, Never>?

    var progress: Double {
        Double(step.rawValue) / Double(Step.allCases.count - 1)
    }

    // MARK: Permissions

    func begin() async {
        permissionProblem = nil
        let mic = await AudioRecorder.requestPermission()
        guard mic else {
            permissionProblem = "Microphone access is off. Turn it on in Settings > Privacy & Security > Microphone > Resonance."
            return
        }
        _ = await Transcriber.requestAuthorization()
        step = .calibration
        startCalibration()
    }

    // MARK: Step 0: calibration

    func startCalibration() {
        taskState = .recording
        recorder.start(name: "calibration")
        guard recorderStarted() else { return }
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.calibrationSeconds))
            guard let self, !Task.isCancelled else { return }
            self.recorder.stop()
            let frames = DSP.frameRMSdB(self.recorder.samples)
            // Lower limit of -70 dB, like the other analyzers: a microphone that starts with pure
            // zeros would otherwise make silence count as voice.
            self.noiseFloor = frames.isEmpty ? -60 : max(DSP.percentile(frames, 10), -70)
            self.tooNoisy = VoiceAnalyzer.isTooNoisy(calibrationSamples: self.recorder.samples)
            self.deleteCurrentFile()   // the calibration audio is not needed
            self.taskState = .done
        }
    }

    // MARK: Task A: held vowel

    func startVowel() {
        message = nil
        taskState = .recording
        recorder.start(name: step == .vowelEee ? "eee" : "vowel")
        guard recorderStarted() else { return }
        let threshold = noiseFloor + 15
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            var heardVoice = false
            var silentFor = 0.0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self else { return }
                // Stopped from outside (an interruption): finish with what was recorded.
                if !self.recorder.isRecording { self.finishVowel(); return }
                if self.recorder.level > threshold {
                    heardVoice = true
                    silentFor = 0
                } else if heardVoice {
                    silentFor += 0.1
                }
                if (heardVoice && silentFor >= Self.vowelSilenceToStop) || self.recorder.duration >= Self.vowelMaxSeconds {
                    self.finishVowel()
                    return
                }
            }
        }
    }

    /// An interrupted recording (for example a phone call) is thrown away, never analyzed or
    /// saved. The task goes back to its start with a calm message so the person can try again.
    private func discardIfInterrupted() -> Bool {
        guard let interruption = recorder.errorMessage else { return false }
        monitorTask?.cancel()
        if recorder.isRecording { recorder.stop() }
        if let url = recorder.fileURL { try? FileManager.default.removeItem(at: url) }
        taskState = .ready
        message = interruption
        return true
    }

    func finishVowel() {
        guard taskState == .recording else { return }
        if discardIfInterrupted() { return }
        monitorTask?.cancel()
        recorder.stop()
        taskState = .analyzing
        let samples = recorder.samples
        let floor = noiseFloor
        let isEee = step == .vowelEee
        if isEee {
            eeeFile = recorder.fileURL?.lastPathComponent
        } else {
            vowelFile = recorder.fileURL?.lastPathComponent
        }
        Task {
            let (result, analysis) = await Task.detached(priority: .userInitiated) {
                (VoiceAnalyzer.analyzeVowel(samples, noiseFloor: floor), VowelAnalysis.analyze(samples))
            }.value
            // Quality gate: a recording that is too short or has no steady voice (measured
            // against the room's real noise floor) never feeds the AI model.
            let usable = !result.flags.contains(QualityFlag.tooShort) && !result.flags.contains(QualityFlag.noPitch)
            if isEee {
                self.eeeAnalysis = usable ? analysis : nil
            } else {
                // Metrics such as phonation time come from the "ahh" only.
                self.vowel = result
                self.ahhAnalysis = usable ? analysis : nil
            }
            self.speechChangeScore = SpeechChangeModel.score(ahh: self.ahhAnalysis, eee: self.eeeAnalysis)
            self.taskState = .done
            if result.flags.contains(QualityFlag.tooShort) {
                self.message = "That was very short. If you can, try again and hold the sound a little longer."
            } else if result.flags.contains(QualityFlag.noPitch) {
                self.message = "We couldn't hear a steady tone. You can try again, or continue."
            }
        }
    }

    // MARK: Task B: pa-ta-ka

    func startDDK() {
        message = nil
        taskState = .recording
        countdown = Self.ddkSeconds
        recorder.start(name: "ddk")
        guard recorderStarted() else { return }
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            let started = Date()
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self else { return }
                if !self.recorder.isRecording { self.finishDDK(); return }
                let elapsed = Date().timeIntervalSince(started)
                self.countdown = max(0, Self.ddkSeconds - elapsed)
                if elapsed >= Self.ddkSeconds {
                    self.finishDDK()
                    return
                }
            }
        }
    }

    func finishDDK() {
        guard taskState == .recording else { return }
        if discardIfInterrupted() { return }
        monitorTask?.cancel()
        recorder.stop()
        taskState = .analyzing
        let samples = recorder.samples
        let floor = noiseFloor
        ddkFile = recorder.fileURL?.lastPathComponent
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                VoiceAnalyzer.analyzeDDK(samples, noiseFloor: floor)
            }.value
            self.ddk = result
            self.taskState = .done
            if result.flags.contains(QualityFlag.tooFewSyllables) {
                self.message = "We heard only a few syllables. You can try again, or continue."
            }
        }
    }

    // MARK: Task C: reading

    func startReading() {
        message = nil
        transcriptSkipped = false
        taskState = .recording
        recorder.start(name: "reading")
        guard recorderStarted() else { return }
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard let self else { return }
                if !self.recorder.isRecording { await self.finishReading(); return }
                if self.recorder.duration >= Self.readingMaxSeconds {
                    await self.finishReading()
                    return
                }
            }
        }
    }

    func finishReading(allowServer: Bool = false) async {
        if taskState == .recording {
            if discardIfInterrupted() { return }
            monitorTask?.cancel()
            recorder.stop()
            readingFile = recorder.fileURL?.lastPathComponent
        }
        taskState = .analyzing
        let samples = recorder.samples

        guard let url = recorder.fileURL else {
            reading = ReadingAnalyzer.analyze(segments: [], samples: samples)
            taskState = .done
            return
        }

        // Ask before sending audio to Apple's servers (PLAN.pdf Section 9).
        if !Transcriber.supportsOnDevice && !allowServer {
            askServerTranscription = true
            return
        }

        do {
            let segments = try await Transcriber.transcribe(fileURL: url, allowServer: allowServer)
            reading = ReadingAnalyzer.analyze(segments: segments, samples: samples)
            if reading?.flags.contains(QualityFlag.noSpeech) == true {
                message = "We couldn't recognize the reading. You can try again, or continue."
            }
        } catch {
            reading = ReadingAnalyzer.analyze(segments: [], samples: samples)
            transcriptSkipped = true
            message = error.localizedDescription
        }
        taskState = .done
    }

    /// The user chose not to use server transcription: keep loudness only.
    func skipTranscription() {
        askServerTranscription = false
        reading = ReadingAnalyzer.analyze(segments: [], samples: recorder.samples)
        transcriptSkipped = true
        message = "Reading speed and word clarity were skipped, so nothing left this iPhone."
        taskState = .done
    }

    // MARK: Navigation

    func redo() {
        monitorTask?.cancel()
        if recorder.isRecording { recorder.stop() }
        deleteCurrentFile()
        message = nil
        taskState = .ready
        switch step {
        case .vowel: vowel = nil; vowelFile = nil; ahhAnalysis = nil; speechChangeScore = nil
        case .vowelEee: eeeAnalysis = nil; eeeFile = nil; speechChangeScore = nil
        case .ddk: ddk = nil; ddkFile = nil
        case .reading: reading = nil; readingFile = nil; transcriptSkipped = false
        default: break
        }
    }

    func next() {
        message = nil
        taskState = .ready
        if let nextStep = Step(rawValue: step.rawValue + 1) {
            step = nextStep
        }
    }

    func cancel() {
        monitorTask?.cancel()
        if recorder.isRecording { recorder.stop() }
        // Leaving without saving: don't keep voice recordings nobody will use.
        if !saved {
            for name in [vowelFile, eeeFile, ddkFile, readingFile].compactMap({ $0 }) {
                if let url = try? AudioFiles.audioDirectory().appendingPathComponent(name) {
                    try? FileManager.default.removeItem(at: url)
                }
            }
            if let url = recorder.fileURL { try? FileManager.default.removeItem(at: url) }
        }
    }

    // MARK: Results

    var allMetrics: [String: Double] {
        var m: [String: Double] = [:]
        if let vowel { m.merge(vowel.metrics) { $1 } }
        if let ahhAnalysis { m[MetricKey.cpp] = ahhAnalysis.features.cpp }
        let named = SpeechChangeInput.named(ahh: ahhAnalysis, eee: eeeAnalysis)
        if let f2 = named["F2_i"] { m[MetricKey.f2Eee] = f2 }
        if let space = named["vowelSpace"] { m[MetricKey.vowelSpace] = space }
        if let speechChangeScore { m[MetricKey.speechChangeScore] = speechChangeScore }
        if let ddk { m.merge(ddk.metrics) { $1 } }
        if let reading { m.merge(reading.metrics) { $1 } }
        return m
    }

    var allFlags: [String] {
        var flags: [String] = []
        if tooNoisy { flags.append(QualityFlag.tooNoisy) }
        flags += vowel?.flags ?? []
        flags += ddk?.flags ?? []
        // A skipped transcript is not "no speech": don't mark the session with a quality warning.
        flags += (reading?.flags ?? []).filter { !(transcriptSkipped && $0 == QualityFlag.noSpeech) }
        return Array(Set(flags)).sorted()
    }

    func save(in context: ModelContext) {
        guard !saved else { return }
        let session = VoiceSession(date: Date(), metrics: allMetrics)
        session.vowelFile = vowelFile
        session.eeeFile = eeeFile
        session.ddkFile = ddkFile
        session.readingFile = readingFile
        session.transcript = reading?.transcript
        session.qualityFlags = allFlags
        session.speechChangeScore = speechChangeScore
        context.insert(session)
        try? context.save()
        saved = true
    }

    // MARK: Helpers

    /// If the microphone could not start, go back to "ready" and explain why, instead of
    /// waiting forever on a recording that is not happening.
    private func recorderStarted() -> Bool {
        if recorder.isRecording { return true }
        monitorTask?.cancel()
        taskState = .ready
        message = recorder.errorMessage ?? "The microphone could not start. Please try again."
        return false
    }

    private func deleteCurrentFile() {
        if let url = recorder.fileURL {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
