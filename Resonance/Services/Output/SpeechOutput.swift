//
//  SpeechOutput.swift
//  Resonance
//
//  Speaks Talk board phrases (PLAN.pdf Sections 13 and 14), in this order of preference:
//  1. the user's own recorded clip (message banking),
//  2. the user's Apple Personal Voice, if they allowed Resonance to use it,
//  3. a standard system voice.
//

import Foundation
import AVFoundation

@MainActor
final class SpeechOutput {
    static let shared = SpeechOutput()

    private let synthesizer = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?

    private init() {}

    // MARK: Speaking

    func speak(_ text: String, clipFileName: String? = nil, preferPersonalVoice: Bool = true, rate: Float = 0.45) {
        stop()
        activatePlaybackSession()

        if let clipFileName, let url = try? BankFiles.url(for: clipFileName),
           FileManager.default.fileExists(atPath: url.path),
           let clipPlayer = try? AVAudioPlayer(contentsOf: url) {
            clipPlayer.volume = 1
            clipPlayer.play()
            player = clipPlayer
            return
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = min(max(rate, 0.3), 0.6)
        utterance.volume = 1
        if preferPersonalVoice, let personal = Self.personalVoice() {
            utterance.voice = personal
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        }
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        player?.stop()
        player = nil
    }

    private func activatePlaybackSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
    }

    // MARK: Personal Voice (iOS 17+)

    /// The user's Personal Voice, if they created one and allowed Resonance to use it.
    static func personalVoice() -> AVSpeechSynthesisVoice? {
        guard AVSpeechSynthesizer.personalVoiceAuthorizationStatus == .authorized else { return nil }
        return AVSpeechSynthesisVoice.speechVoices().first { $0.voiceTraits.contains(.isPersonalVoice) }
    }

    static func requestPersonalVoiceAccess() async -> AVSpeechSynthesizer.PersonalVoiceAuthorizationStatus {
        await withCheckedContinuation { continuation in
            AVSpeechSynthesizer.requestPersonalVoiceAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    static var personalVoiceStatusText: String {
        switch AVSpeechSynthesizer.personalVoiceAuthorizationStatus {
        case .authorized:
            return personalVoice() == nil ? "Allowed, but no Personal Voice was found on this iPhone." : "Ready"
        case .denied:
            return "Not allowed (or not supported on this iPhone)"
        case .unsupported:
            return "Not supported here (Personal Voice needs a recent iPhone, not the Simulator)"
        case .notDetermined:
            return "Not set up yet"
        @unknown default:
            return "Unknown"
        }
    }
}

/// Where own-voice recordings are stored: Documents/Bank.
enum BankFiles {
    static func directory() throws -> URL {
        let docs = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        let dir = docs.appendingPathComponent("Bank", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func url(for fileName: String) throws -> URL {
        try directory().appendingPathComponent(fileName)
    }

    static func newFileName() -> String {
        "\(UUID().uuidString).m4a"
    }
}
