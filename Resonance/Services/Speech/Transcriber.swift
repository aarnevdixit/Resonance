//
//  Transcriber.swift
//  Resonance
//
//  Transcribes a recorded .wav file with Apple's Speech framework and returns each word
//  with its timing (PLAN.pdf Section 9, Task C).
//
//  Privacy: recognition runs on the iPhone. If on-device recognition is not available,
//  the caller must ask the user before passing allowServer: true, because server
//  recognition sends the audio to Apple.
//

import Foundation
import Speech

enum TranscriberError: LocalizedError {
    case notAuthorized
    case unavailable
    case onDeviceUnavailable
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Speech recognition is turned off for Resonance. You can turn it on in Settings > Privacy & Security > Speech Recognition."
        case .unavailable:
            return "Speech recognition is not available right now."
        case .onDeviceUnavailable:
            return "On-device speech recognition is not available on this iPhone."
        case .failed(let message):
            return "Transcription failed: \(message)"
        }
    }
}

enum Transcriber {
    static let locale = Locale(identifier: "en-US")

    /// Asks for speech recognition permission (system prompt the first time).
    static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    /// True when this iPhone can transcribe without sending audio off the device.
    static var supportsOnDevice: Bool {
        SFSpeechRecognizer(locale: locale)?.supportsOnDeviceRecognition ?? false
    }

    /// Transcribes the file and returns words with timestamps.
    static func transcribe(fileURL: URL, allowServer: Bool = false) async throws -> [WordSegment] {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw TranscriberError.notAuthorized
        }
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw TranscriberError.unavailable
        }
        if !recognizer.supportsOnDeviceRecognition && !allowServer {
            throw TranscriberError.onDeviceUnavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: fileURL)
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.taskHint = .dictation
        request.contextualStrings = TextAligner.normalize(ReadingPassage.text)

        // The recognizer and its task are kept alive until a result arrives, and a timeout makes
        // sure the screen never waits forever on "Analyzing…".
        return try await withCheckedThrowingContinuation { continuation in
            let gate = ResumeGate()
            gate.task = recognizer.recognitionTask(with: request) { result, error in
                // Referencing the recognizer here keeps it alive until the task calls back.
                withExtendedLifetime(recognizer) {}
                if let error {
                    if gate.claim() { continuation.resume(throwing: TranscriberError.failed(error.localizedDescription)) }
                    return
                }
                guard let result, result.isFinal else { return }
                let segments = result.bestTranscription.segments.map {
                    WordSegment(word: $0.substring, start: $0.timestamp, duration: $0.duration)
                }
                if gate.claim() { continuation.resume(returning: segments) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + timeoutSeconds) {
                if gate.claim() {
                    gate.cancelTask()
                    continuation.resume(throwing: TranscriberError.failed("Speech recognition took too long."))
                }
            }
        }
    }

    /// Longest wait for a transcript (the reading passage is about a minute of audio).
    static let timeoutSeconds: Double = 60
}

/// Makes sure a continuation is resumed only once, even if the recognizer calls back twice.
/// Every access goes through the lock, so it is safe to share across threads.
private final class ResumeGate: @unchecked Sendable {
    private var used = false
    private let lock = NSLock()
    private var _task: SFSpeechRecognitionTask?

    var task: SFSpeechRecognitionTask? {
        get { lock.lock(); defer { lock.unlock() }; return _task }
        set { lock.lock(); _task = newValue; lock.unlock() }
    }

    func cancelTask() { task?.cancel() }

    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if used { return false }
        used = true
        return true
    }
}
