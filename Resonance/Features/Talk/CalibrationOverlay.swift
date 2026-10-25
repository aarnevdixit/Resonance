//
//  CalibrationOverlay.swift
//  Resonance
//
//  5-point calibration for the head pointer (PLAN.pdf Section 13).
//  The user points their face at each dot in turn. We record about 1 second of head
//  direction per dot, take the median, and fit a GazeMapper. The overlay covers the
//  Talk board exactly, so dot positions are in the board's coordinate space.
//

import SwiftUI

struct CalibrationOverlay: View {
    let tracker: FaceTracker
    let onFinish: (GazeMapper?) -> Void

    @State private var index = 0
    @State private var message = "Point your nose at the dot and hold still."
    @State private var task: Task<Void, Never>?
    @State private var pulse = false

    var body: some View {
        GeometryReader { geo in
            let targets = Self.targets(in: geo.size)
            ZStack {
                AppTheme.canvas.opacity(0.98)

                VStack(spacing: 12) {
                    IconBadge(systemImage: "face.smiling", size: 56)
                    Text("Calibrating head pointer")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                    Text(message)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Button("Cancel") {
                        task?.cancel()
                        onFinish(nil)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .frame(width: 200)
                }
                .padding()
                .position(x: geo.size.width / 2, y: geo.size.height * 0.33)

                if index < targets.count {
                    ZStack {
                        Circle()
                            .stroke(AppTheme.accent.opacity(0.35), lineWidth: 3)
                            .frame(width: 70, height: 70)
                            .scaleEffect(pulse ? 1.2 : 0.8)
                            .opacity(pulse ? 0 : 1)
                            .animation(.easeOut(duration: 1.1).repeatForever(autoreverses: false), value: pulse)
                        Circle()
                            .fill(AppTheme.accent)
                            .frame(width: 34, height: 34)
                            .overlay(Circle().stroke(.white, lineWidth: 4))
                            .shadow(color: AppTheme.violetDeep.opacity(0.35), radius: 6, y: 3)
                    }
                    .position(targets[index])
                        .animation(.easeInOut(duration: 0.3), value: index)
                        .accessibilityLabel("Calibration dot \(index + 1) of \(targets.count)")
                }
            }
            .onAppear {
                pulse = true
                tracker.start()
                task = Task { await run(targets: targets) }
            }
            .onDisappear { task?.cancel() }
        }
    }

    /// Center, then four corners 15% in from the edges.
    static func targets(in size: CGSize) -> [CGPoint] {
        let insetX = size.width * 0.15, insetY = size.height * 0.15
        return [
            CGPoint(x: size.width / 2, y: size.height / 2),
            CGPoint(x: insetX, y: insetY),
            CGPoint(x: size.width - insetX, y: insetY),
            CGPoint(x: insetX, y: size.height - insetY),
            CGPoint(x: size.width - insetX, y: size.height - insetY),
        ]
    }

    @MainActor
    private func run(targets: [CGPoint]) async {
        var rawPoints: [CGPoint] = []
        for (i, _) in targets.enumerated() {
            index = i
            message = "Dot \(i + 1) of \(targets.count): point your nose at it and hold still."
            try? await Task.sleep(for: .milliseconds(700))     // time to move to the dot
            var samples: [CGPoint] = []
            for _ in 0..<30 {                                    // about 1 second
                if Task.isCancelled { return }
                if let raw = tracker.raw, tracker.faceVisible { samples.append(raw) }
                try? await Task.sleep(for: .milliseconds(33))
            }
            guard samples.count >= 10 else {
                message = "We couldn't see your face. Hold the phone in front of you and try again."
                try? await Task.sleep(for: .seconds(2))
                onFinish(nil)
                return
            }
            rawPoints.append(CGPoint(x: median(samples.map(\.x)), y: median(samples.map(\.y))))
        }
        index = targets.count
        let mapper = GazeMapper.fit(raw: rawPoints, screen: targets)
        message = mapper == nil ? "Calibration didn't work. Try moving your head a little more." : "Done!"
        try? await Task.sleep(for: .milliseconds(600))
        onFinish(mapper)
    }

    private func median(_ values: [CGFloat]) -> CGFloat {
        let s = values.sorted()
        return s.isEmpty ? 0 : s[s.count / 2]
    }
}
