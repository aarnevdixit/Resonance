//
//  MicrophoneTestView.swift
//  Resonance
//
//  Task T03 test screen: record, watch the live level meter, then play the .wav back
//  and see basic numbers from DSP. Used to check the recorder before the Voice Lab is built.
//

import SwiftUI
import AVFoundation

struct MicrophoneTestView: View {
    @State private var recorder = AudioRecorder()
    @State private var player: AVAudioPlayer?
    @State private var permissionDenied = false
    @State private var summary: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Hold your phone about one foot (30 cm) from your mouth. Tap Record and say \"ahh\" for a few seconds.")
                    .font(.title3)
                    .multilineTextAlignment(.center)

                LevelMeterView(db: recorder.level)
                    .padding(.vertical, 8)

                Text(recorder.isRecording
                     ? String(format: "Recording… %.1f s", recorder.duration)
                     : "Not recording")
                    .font(.headline)
                    .monospacedDigit()

                if recorder.isRecording {
                    Button {
                        recorder.stop()
                        analyze()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle(color: AppTheme.danger))
                } else {
                    Button {
                        Task { await startRecording() }
                    } label: {
                        Label("Record", systemImage: "mic.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }

                if let url = recorder.fileURL, !recorder.isRecording {
                    Button {
                        play(url)
                    } label: {
                        Label("Play recording", systemImage: "play.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle(color: AppTheme.violetDeep))
                }

                if let summary {
                    Card {
                        Text("Results").font(.headline)
                        Text(summary)
                            .font(.body.monospacedDigit())
                    }
                }

                if permissionDenied {
                    Card {
                        Text("Microphone access is off. Turn it on in Settings > Privacy & Security > Microphone > Resonance.")
                            .foregroundStyle(AppTheme.warning)
                    }
                }

                if let message = recorder.errorMessage {
                    Card {
                        Text(message).foregroundStyle(AppTheme.warning)
                    }
                }
            }
            .padding(AppTheme.padding)
        }
        .screenBackground()
        .navigationTitle("Microphone test")
        .onDisappear {
            recorder.stop()
            player?.stop()
        }
    }

    private func startRecording() async {
        player?.stop()
        summary = nil
        let allowed = await AudioRecorder.requestPermission()
        permissionDenied = !allowed
        guard allowed else { return }
        recorder.start(name: "mictest")
    }

    /// Shows simple numbers so you can check the recorder and DSP are working.
    private func analyze() {
        let samples = recorder.samples
        guard !samples.isEmpty else {
            summary = "No audio was captured."
            return
        }
        let frames = DSP.frameRMSdB(samples)
        let noiseFloor = DSP.percentile(frames, 10)
        let loudest = DSP.percentile(frames, 95)
        let mask = DSP.voicedMask(frames, noiseFloor: noiseFloor)
        let longestVoice = DSP.seconds(frames: DSP.longestTrueRun(mask))
        summary = String(
            format: "Length: %.1f s\nNoise floor: %.0f dBFS\nLoudest: %.0f dBFS\nLongest voiced stretch: %.1f s",
            recorder.duration, noiseFloor, loudest, longestVoice
        )
    }

    private func play(_ url: URL) {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.play()
            player = newPlayer
        } catch {
            summary = "Could not play the recording: \(error.localizedDescription)"
        }
    }
}

#Preview {
    NavigationStack { MicrophoneTestView() }
}
