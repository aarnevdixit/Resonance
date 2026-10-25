//
//  MotorLabFlowView.swift
//  Resonance
//
//  Motor Lab screens (PLAN.pdf Section 10).
//

import SwiftUI
import SwiftData

struct MotorLabFlowView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var model = MotorLabModel()

    var body: some View {
        VStack(spacing: 0) {
            ProgressView(value: model.progress)
                .tint(AppTheme.accent)
                .padding(.horizontal, AppTheme.padding)
                .padding(.top, 8)
                .accessibilityLabel("Motor Lab progress")

            switch model.step {
            case .intro: ScrollView { intro.padding(AppTheme.padding) }
            case .tapRight: tapping(hand: "right")
            case .tapLeft: tapping(hand: "left")
            case .spiral: spiralScreen
            case .hold: ScrollView { hold.padding(AppTheme.padding) }
            case .results: ScrollView { results.padding(AppTheme.padding) }
            }
        }
        .screenBackground()
        .navigationTitle("Motor Lab")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { model.cancel() }
    }

    // MARK: Intro

    private var intro: some View {
        VStack(spacing: 20) {
            IconBadge(systemImage: "hand.tap.fill", color: AppTheme.blue, size: 88)
                .padding(.top, 8)
            Text("Three short tests, about 2 minutes.")
                .font(.system(.title2, design: .rounded).weight(.bold))
                .multilineTextAlignment(.center)
            Card {
                Label("Finger tapping with each hand (10 seconds each).", systemImage: "hand.point.up.left")
                Label("Tracing a spiral with your finger.", systemImage: "hurricane")
                Label("Holding the phone still (15 seconds).", systemImage: "iphone")
                Label("Sit the same way each week.", systemImage: "chair")
            }
            .font(.title3)
            Button("Start") { model.next() }
                .buttonStyle(PrimaryButtonStyle())
            WhyThisTestCard(exercise: .tapping, title: "Why tapping?")
            WhyThisTestCard(exercise: .spiral, title: "Why a spiral?")
            WhyThisTestCard(exercise: .hold, title: "Why hold still?")
        }
    }

    // MARK: Tapping

    private func tapping(hand: String) -> some View {
        VStack(spacing: 12) {
            Text("Use your \(hand) index finger")
                .font(.system(.title2, design: .rounded).weight(.bold))
                .padding(.top, 12)
            Text("Tap the two circles one after the other, as fast as you can.")
                .font(.title3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppTheme.padding)

            // Fixed height, so the circles never move when the countdown or timer appears.
            statusLine
                .frame(height: 76)

            TapTargetArea(enabled: model.phase == .running) { target in
                model.recordTap(target: target)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            bottomControls(result: (hand == "right" ? model.right : model.left).map {
                String(format: "%.1f taps per second, %.0f%% on target.", $0.rate, $0.accuracy)
            })
            .padding(AppTheme.padding)
        }
    }

    // MARK: Spiral

    private var spiralScreen: some View {
        VStack(spacing: 10) {
            Text("Trace the spiral")
                .font(.system(.title2, design: .rounded).weight(.bold))
                .padding(.top, 12)
            Text("Start at the center dot and follow the line outward with your index finger, without lifting it.")
                .font(.title3)
                .multilineTextAlignment(.center)
                // On small iPhones with large text the words shrink, so Redo and Next stay on screen.
                .lineLimit(4)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, AppTheme.padding)

            statusLine
                .frame(height: 64)

            SpiralCanvas(enabled: model.phase == .running, trace: model.spiralTrace,
                         onMove: { model.recordSpiral(x: $0, y: $1) },
                         onLift: { model.spiralLifted() })
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            bottomControls(result: model.spiral.map {
                String(format: "%.1f pt off the line on average, %.0f pt/s.", $0.meanError, $0.speed)
            })
            .padding(AppTheme.padding)
            .layoutPriority(1)   // the buttons keep their space; the spiral area gives way
        }
    }

    // MARK: Hold

    private var hold: some View {
        VStack(spacing: 20) {
            Text("Hold your phone still")
                .font(.system(.title2, design: .rounded).weight(.bold))
            Text("Hold the phone straight out in front of you with your arm extended, as still as you can. If you need to, rest your elbow on a table. Do it the same way each week.")
                .font(.title3)
                .multilineTextAlignment(.center)
            IconBadge(systemImage: "iphone.gen3", color: AppTheme.blue, size: 96)
            statusLine
                .frame(height: 76)
            bottomControls(result: model.steadiness.map {
                String(format: "Steadiness: %.0f mg (lower is steadier).", $0.steadyRMS)
            })
        }
    }

    // MARK: Results

    private var results: some View {
        let measured = !model.allMetrics.isEmpty
        return VStack(spacing: 18) {
            Image(systemName: measured ? "checkmark.seal.fill" : "hand.raised.slash.fill")
                .font(.system(size: 64))
                .foregroundStyle(measured ? AppTheme.mint : AppTheme.amber)
                .accessibilityHidden(true)
            Text(model.saved ? "Saved" : (measured ? "All done" : "Nothing measured"))
                .font(.system(.title, design: .rounded).weight(.bold))
            if measured {
                ResultInterpretationList(latest: model.allMetrics,
                                         keys: Exercise.tapping.metricKeys + Exercise.spiral.metricKeys
                                             + Exercise.hold.metricKeys)
                Text("These are estimates from your phone's touch screen and motion sensors. They are most useful compared with your own past results, and they are not a diagnosis.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Card {
                    Text("No taps or motion were recorded this time, so nothing was saved. You can try again whenever you're ready.")
                        .font(.title3)
                }
            }
            if model.saved || !measured {
                Button("Close") { dismiss() }
                    .buttonStyle(PrimaryButtonStyle())
            } else {
                Button("Save results") { model.save(in: modelContext) }
                    .buttonStyle(PrimaryButtonStyle())
            }
            if model.saved {
                NextStepsPanel(limit: 3)
                    .padding(.top, 8)
            }
        }
    }

    // MARK: Shared pieces

    @ViewBuilder
    private var statusLine: some View {
        // Color.clear (not EmptyView) so the fixed-height frame is kept and nothing below moves.
        switch model.phase {
        case .ready:
            Color.clear
        case .countdown(let n):
            Text("\(n)")
                .font(.system(size: 64, weight: .bold).monospacedDigit())
                .foregroundStyle(AppTheme.accent)
                .accessibilityLabel("Starting in \(n)")
        case .running:
            VStack(spacing: 6) {
                ProgressView(value: model.currentDuration - model.remaining, total: model.currentDuration)
                    .tint(AppTheme.accent)
                Text(secondsLeft(model.remaining))
                    .font(.title3.monospacedDigit())
            }
            .padding(.horizontal, AppTheme.padding)
        case .done:
            Color.clear
        }
    }

    @ViewBuilder
    private func bottomControls(result: String?) -> some View {
        switch model.phase {
        case .ready:
            Button("Start") { model.start() }
                .buttonStyle(PrimaryButtonStyle())
        case .countdown, .running:
            Button("Cancel") { model.redo() }
                .buttonStyle(SecondaryButtonStyle())
        case .done:
            VStack(spacing: 12) {
                if let message = model.message {
                    Card {
                        Label(message, systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(AppTheme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if let result {
                    Card {
                        Label(result, systemImage: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(AppTheme.ink)
                            .labelStyle(TintedIconLabelStyle())
                            .fixedSize(horizontal: false, vertical: true)
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

/// The spiral guide and the finger's path. Fixed size so every week uses the same spiral.
private struct SpiralCanvas: View {
    let enabled: Bool
    let trace: [SpiralSample]
    let onMove: (Double, Double) -> Void
    let onLift: () -> Void

    private let side = (SpiralAnalyzer.radius + 20) * 2

    var body: some View {
        let c = side / 2
        ZStack {
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                .fill(AppTheme.surface)
            Path { path in
                let pts = SpiralAnalyzer.guidePoints()
                guard let first = pts.first else { return }
                path.move(to: CGPoint(x: c + first.x, y: c + first.y))
                for p in pts.dropFirst() { path.addLine(to: CGPoint(x: c + p.x, y: c + p.y)) }
            }
            .stroke(enabled ? AppTheme.violetSoft : AppTheme.violetSoft.opacity(0.7),
                    style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round))
            Path { path in
                guard let first = trace.first else { return }
                path.move(to: CGPoint(x: c + first.x, y: c + first.y))
                for p in trace.dropFirst() { path.addLine(to: CGPoint(x: c + p.x, y: c + p.y)) }
            }
            .stroke(AppTheme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            Circle()
                .fill(AppTheme.mint)
                .frame(width: 18, height: 18)
                .position(x: c, y: c)
        }
        .frame(width: side, height: side)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard enabled else { return }
                    onMove(value.location.x - c, value.location.y - c)
                }
                .onEnded { _ in if enabled { onLift() } }
        )
        .accessibilityElement()
        .accessibilityLabel("Spiral to trace with your finger")
    }
}

/// Two 80 pt circles, centers 160 pt apart. Every touch is reported, hit or miss.
private struct TapTargetArea: View {
    let enabled: Bool
    let onTap: (Int?) -> Void

    private let diameter: CGFloat = 80
    private let spacing: CGFloat = 160

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let leftCenter = CGPoint(x: center.x - spacing / 2, y: center.y)
            let rightCenter = CGPoint(x: center.x + spacing / 2, y: center.y)

            ZStack {
                Color.clear
                ForEach([leftCenter, rightCenter], id: \.x) { c in
                    Circle()
                        .fill(enabled ? AppTheme.accent : AppTheme.violetSoft)
                        .overlay(Circle().stroke(AppTheme.accent.opacity(enabled ? 0.25 : 0), lineWidth: 10))
                        .shadow(color: AppTheme.violetDeep.opacity(enabled ? 0.3 : 0), radius: 10, y: 5)
                        .frame(width: diameter, height: diameter)
                        .position(c)
                        .animation(.easeOut(duration: 0.2), value: enabled)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        guard enabled else { return }
                        onTap(TapAnalyzer.target(at: value.location, leftCenter: leftCenter,
                                                 rightCenter: rightCenter, radius: diameter / 2))
                    }
            )
            .accessibilityElement()
            .accessibilityLabel("Tapping area with two circles")
        }
    }
}

#Preview {
    NavigationStack { MotorLabFlowView() }
        .modelContainer(for: MotorSession.self, inMemory: true)
}

/// Label with a mint icon and normal-colored text.
private struct TintedIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            configuration.icon.foregroundStyle(AppTheme.mint)
            configuration.title
        }
    }
}
