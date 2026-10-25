//
//  AudioRecorder.swift
//  Resonance
//
//  Records the microphone as 44.1 kHz mono Float32 audio for the Voice Lab
//  (PLAN.pdf Section 9, "Recording setup").
//  - Keeps every sample in memory for analysis (`samples`).
//  - Writes the same audio to a .wav file in Documents/Audio.
//  - Publishes a live level (dBFS) about 10-20 times a second for the on-screen meter.
//
//  The audio session uses mode .measurement, which turns off automatic gain and
//  noise processing that would distort the measurements.
//

import Foundation
import AVFoundation
import Accelerate
import Observation

@Observable
final class AudioRecorder {
    // Values the UI reads.
    private(set) var level: Float = -160          // live loudness in dBFS
    private(set) var isRecording = false
    private(set) var samples: [Float] = []        // mono, 44.1 kHz
    private(set) var fileURL: URL?
    var errorMessage: String?

    /// Seconds of audio captured so far.
    var duration: Double { Double(samples.count) / DSP.sampleRate }

    // Audio plumbing (not observed by the UI).
    private let engine = AVAudioEngine()
    @ObservationIgnored private var file: AVAudioFile?
    @ObservationIgnored private var converter: AVAudioConverter?
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?
    @ObservationIgnored private var routeObserver: NSObjectProtocol?
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: DSP.sampleRate,
        channels: 1,
        interleaved: false
    )

    // MARK: Permission

    /// Asks for microphone permission (shows the system prompt the first time).
    static func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    // MARK: Recording

    /// Starts recording into a new .wav file. `name` is used as the file name prefix.
    func start(name: String = "recording") {
        guard !isRecording else { return }
        errorMessage = nil
        samples = []
        level = -160

        // Never touch the microphone without permission: show a calm message instead.
        guard AVAudioApplication.shared.recordPermission == .granted else {
            errorMessage = "Microphone access is off. Turn it on in Settings > Privacy & Security > Microphone > Resonance."
            return
        }

        guard let targetFormat else {
            errorMessage = "Could not set up the audio format."
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
            try session.setActive(true)

            let input = engine.inputNode
            let inputFormat = input.outputFormat(forBus: 0)
            guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
                errorMessage = "No microphone is available."
                cleanUp()   // also turns the audio session back off
                return
            }

            guard let newConverter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
                errorMessage = "Could not set up audio conversion."
                cleanUp()
                return
            }
            converter = newConverter

            let url = try AudioFiles.newRecordingURL(prefix: name)
            let newFile = try AVAudioFile(
                forWriting: url,
                settings: targetFormat.settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
            file = newFile
            fileURL = url

            input.removeTap(onBus: 0)
            // The audio thread gets its own references, so stopping on the main thread can
            // never pull the converter or file out from under a callback that is running.
            input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
                self?.process(buffer, converter: newConverter, file: newFile)
            }

            engine.prepare()
            try engine.start()
            isRecording = true
            // A phone call or Siri stops the microphone: end the recording cleanly instead of
            // leaving the screen waiting on a frozen level meter.
            interruptionObserver = NotificationCenter.default.addObserver(
                forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
            ) { [weak self] note in
                guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
                self?.errorMessage = "Recording stopped because something else used the audio (for example a call). You can try again."
                self?.stop()
            }
            // Headphones or AirPods connecting stops the engine: end cleanly with a message.
            routeObserver = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
            ) { [weak self] _ in
                guard let self, self.isRecording else { return }
                self.errorMessage = "The microphone changed during recording (for example headphones). Please try again."
                self.stop()
            }
        } catch {
            errorMessage = "Recording could not start: \(error.localizedDescription)"
            cleanUp()
        }
    }

    /// Stops recording and closes the file. `samples` and `fileURL` stay available.
    func stop() {
        guard isRecording else { return }
        cleanUp()
        isRecording = false
        level = -160
    }

    private func cleanUp() {
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        interruptionObserver = nil
        if let routeObserver { NotificationCenter.default.removeObserver(routeObserver) }
        routeObserver = nil
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        file = nil          // releasing the AVAudioFile finishes writing the .wav
        converter = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: Processing (runs on the audio thread)

    private func process(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter, file: AVAudioFile) {
        guard let targetFormat else { return }

        // Convert the microphone's native format to 44.1 kHz mono Float32.
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var suppliedInput = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if suppliedInput {
                inputStatus.pointee = .noDataNow
                return nil
            }
            suppliedInput = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, conversionError == nil,
              let channel = output.floatChannelData, output.frameLength > 0 else { return }

        let count = Int(output.frameLength)
        let chunk = Array(UnsafeBufferPointer(start: channel[0], count: count))

        var rms: Float = 0
        vDSP_rmsqv(channel[0], 1, &rms, vDSP_Length(count))
        let db = DSP.toDB(rms)

        try? file.write(from: output)

        DispatchQueue.main.async { [weak self] in
            guard let self, self.isRecording else { return }
            self.samples.append(contentsOf: chunk)
            self.level = db
        }
    }
}

/// Where recordings are stored on the device.
enum AudioFiles {
    /// Documents/Audio, created if needed.
    static func audioDirectory() throws -> URL {
        let docs = try FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let dir = docs.appendingPathComponent("Audio", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// A new unique .wav file URL, e.g. Documents/Audio/vowel-2026-10-24-101530.wav
    static func newRecordingURL(prefix: String) throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let stamp = formatter.string(from: Date())
        return try audioDirectory().appendingPathComponent("\(prefix)-\(stamp).wav")
    }
}
