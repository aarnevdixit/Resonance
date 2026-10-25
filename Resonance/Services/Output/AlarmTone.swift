//
//  AlarmTone.swift
//  Resonance
//
//  The alert's attention sounds and light:
//  - a two-tone siren made in code (no sound files), played between the spoken calls;
//  - the iPhone's flashlight blinking in time with the screen.
//  Both fail quietly on devices without them (the Simulator has no flashlight).
//

import Foundation
import AVFoundation

@MainActor
final class AlarmTone {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var buffer: AVAudioPCMBuffer?
    private var prepared = false

    /// Builds the siren: 880 Hz and 660 Hz alternating every 0.25 s, with soft edges
    /// so it doesn't click.
    static func makeSiren(sampleRate: Double = 44_100, seconds: Double = 2.0) -> [Float] {
        let count = Int(sampleRate * seconds)
        var samples = [Float](repeating: 0, count: count)
        let segment = Int(sampleRate * 0.25)
        let fade = Int(sampleRate * 0.01)
        var phase = 0.0
        for i in 0..<count {
            let high = (i / segment) % 2 == 0
            let frequency = high ? 880.0 : 660.0
            phase += 2 * Double.pi * frequency / sampleRate
            let position = i % segment
            let edge = min(position, segment - 1 - position)
            let envelope = edge < fade ? Double(edge) / Double(fade) : 1
            samples[i] = Float(sin(phase) * 0.8 * envelope)
        }
        return samples
    }

    private func prepare() {
        guard !prepared else { return }
        prepared = true
        let siren = Self.makeSiren()
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1),
              let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(siren.count)),
              let channel = pcm.floatChannelData?[0] else { return }
        pcm.frameLength = AVAudioFrameCount(siren.count)
        siren.withUnsafeBufferPointer { source in
            if let base = source.baseAddress { channel.update(from: base, count: siren.count) }
        }
        buffer = pcm
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    /// Plays the siren once (about 2 seconds).
    func play() {
        prepare()
        guard let buffer else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try session.setActive(true)
            if !engine.isRunning { try engine.start() }
            player.scheduleBuffer(buffer, at: nil, options: [.interrupts])
            player.play()
        } catch {
            // No sound device (rare): the spoken call and flashing screen still work.
        }
    }

    func stop() {
        // Stop can come before the siren was ever set up (in the first seconds of an alert).
        guard player.engine != nil else { return }
        player.stop()
        if engine.isRunning { engine.stop() }
    }
}

/// Blinks the iPhone's flashlight. Does nothing where there is no torch.
enum Flashlight {
    static func set(_ on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch, device.isTorchAvailable else { return }
        do {
            try device.lockForConfiguration()
            if on {
                try device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
            } else {
                device.torchMode = .off
            }
            device.unlockForConfiguration()
        } catch {
            // The camera may be in use; the flashing screen is enough.
        }
    }
}
