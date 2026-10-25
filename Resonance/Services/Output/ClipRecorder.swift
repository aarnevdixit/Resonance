//
//  ClipRecorder.swift
//  Resonance
//
//  Records a phrase in the user's own voice as an .m4a file (message banking,
//  PLAN.pdf Section 14). Files live in Documents/Bank on this iPhone.
//  - Shows a live level while recording.
//  - Refuses a recording that is too quiet to be useful (the microphone was covered,
//    or nothing was said), so a tile never plays silence.
//
//  Change from the plan: automatic silence trimming is left out to keep this simple and
//  reliable; the recording stops as soon as the user taps Stop.
//

import Foundation
import AVFoundation
import Observation

@MainActor
@Observable
final class ClipRecorder {
    private(set) var isRecording = false
    private(set) var recordingFor: PersistentIdentifierBox?
    /// Live loudness in dBFS (about -60 quiet … 0 loud).
    private(set) var level: Float = -60
    private(set) var seconds: Double = 0
    var errorMessage: String?

    /// The loudest moment must reach this, or the clip is treated as silent.
    static let minimumPeak: Float = -40

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var currentFileName: String?
    @ObservationIgnored private var peak: Float = -160
    @ObservationIgnored private var meterTask: Task<Void, Never>?

    /// Starts recording a new clip. Returns the file name that will be written.
    func start(for id: PersistentIdentifierBox) -> String? {
        errorMessage = nil
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            let name = BankFiles.newFileName()
            let url = try BankFiles.url(for: name)
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ]
            let newRecorder = try AVAudioRecorder(url: url, settings: settings)
            newRecorder.isMeteringEnabled = true
            guard newRecorder.record() else {
                errorMessage = "Recording could not start."
                return nil
            }
            recorder = newRecorder
            currentFileName = name
            recordingFor = id
            isRecording = true
            peak = -160
            seconds = 0
            startMetering()
            return name
        } catch {
            errorMessage = "Recording could not start: \(error.localizedDescription)"
            return nil
        }
    }

    private func startMetering() {
        meterTask?.cancel()
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let recorder = self.recorder else { return }
                recorder.updateMeters()
                let power = recorder.averagePower(forChannel: 0)
                self.level = power
                self.peak = max(self.peak, recorder.peakPower(forChannel: 0))
                self.seconds = recorder.currentTime
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    /// Stops recording and returns the finished file name, or nil if it was too quiet
    /// or too short (then the file is deleted and `errorMessage` explains why).
    func stop() -> String? {
        meterTask?.cancel()
        meterTask = nil
        let duration = recorder?.currentTime ?? 0
        recorder?.stop()
        recorder = nil
        isRecording = false
        recordingFor = nil
        level = -60
        guard let name = currentFileName else { return nil }
        currentFileName = nil

        if peak < Self.minimumPeak || duration < 0.4 {
            if let url = try? BankFiles.url(for: name) { try? FileManager.default.removeItem(at: url) }
            errorMessage = duration < 0.4
                ? "That was too short. Tap record, say the phrase, then tap stop."
                : "We couldn't hear you. Check that the microphone isn't covered and try again."
            return nil
        }
        return name
    }

    /// Stops without keeping anything (leaving the screen mid-recording).
    func cancel() {
        guard isRecording else { return }
        if let name = stop(), let url = try? BankFiles.url(for: name) {
            try? FileManager.default.removeItem(at: url)
        }
        errorMessage = nil
    }
}

/// Wraps a phrase's text so the recorder knows which row is recording.
struct PersistentIdentifierBox: Equatable {
    let key: String
}
