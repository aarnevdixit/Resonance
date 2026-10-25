//
//  MotorLabModel.swift
//  Resonance
//
//  Runs the Motor Lab (PLAN.pdf Section 10): tapping with the right hand,
//  tapping with the left hand, tracing a spiral, then a 15-second steadiness hold.
//

import Foundation
import Observation
import QuartzCore
import SwiftData

@MainActor
@Observable
final class MotorLabModel {

    enum Step: Int, CaseIterable {
        case intro, tapRight, tapLeft, spiral, hold, results
    }

    enum Phase: Equatable {
        case ready
        case countdown(Int)
        case running
        case done
    }

    static let tapSeconds = 10.0
    static let holdSeconds = 15.0
    static let spiralSeconds = 30.0

    var step: Step = .intro
    var phase: Phase = .ready
    private(set) var remaining: Double = 0
    private(set) var tapCount = 0
    var message: String?

    private(set) var right: TapResult?
    private(set) var left: TapResult?
    private(set) var steadiness: SteadinessResult?
    private(set) var spiral: SpiralResult?
    /// The finger path while tracing, for drawing (pt, relative to the spiral centre).
    private(set) var spiralTrace: [SpiralSample] = []
    private(set) var saved = false

    @ObservationIgnored private var taps: [TapEvent] = []
    @ObservationIgnored private var startTime: CFTimeInterval = 0
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private let motion = MotionRecorder()

    var progress: Double {
        Double(step.rawValue) / Double(Step.allCases.count - 1)
    }

    var currentDuration: Double {
        switch step {
        case .hold: return Self.holdSeconds
        case .spiral: return Self.spiralSeconds
        default: return Self.tapSeconds
        }
    }

    // MARK: Running a test

    func start() {
        message = nil
        taps = []
        tapCount = 0
        spiralTrace = []
        runTask?.cancel()
        runTask = Task { [weak self] in
            for n in [3, 2, 1] {
                self?.phase = .countdown(n)
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            guard let self else { return }
            self.phase = .running
            self.startTime = CACurrentMediaTime()
            if self.step == .hold { self.motion.start() }

            let duration = self.currentDuration
            while !Task.isCancelled {
                let elapsed = CACurrentMediaTime() - self.startTime
                self.remaining = max(0, duration - elapsed)
                if elapsed >= duration { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            if Task.isCancelled { return }
            await self.finish()
        }
    }

    /// Called by the tapping screen for every touch.
    func recordTap(target: Int?) {
        guard phase == .running, step == .tapRight || step == .tapLeft else { return }
        taps.append(TapEvent(time: CACurrentMediaTime() - startTime, target: target))
        tapCount += 1
    }

    /// Called by the spiral screen as the finger moves.
    func recordSpiral(x: Double, y: Double) {
        guard phase == .running, step == .spiral else { return }
        spiralTrace.append(SpiralSample(time: CACurrentMediaTime() - startTime, x: x, y: y))
    }

    /// Lifting the finger after tracing most of the spiral ends the test early.
    func spiralLifted() {
        guard phase == .running, step == .spiral,
              SpiralAnalyzer.coverage(spiralTrace) >= 0.9 else { return }
        runTask?.cancel()
        Task { await finish() }
    }

    private func finish() async {
        switch step {
        case .spiral:
            spiral = SpiralAnalyzer.analyze(spiralTrace)
            if spiral == nil {
                message = "Not enough of the spiral was traced. Try to follow the line from the center to the outside."
            }
        case .tapRight:
            right = usable(TapAnalyzer.analyze(taps, duration: Self.tapSeconds))
        case .tapLeft:
            left = usable(TapAnalyzer.analyze(taps, duration: Self.tapSeconds))
        case .hold:
            motion.stop()
            let samples = motion.samples
            if samples.isEmpty {
                message = "Motion sensors aren't available here (they only work on a real iPhone)."
            } else {
                let result = await Task.detached(priority: .userInitiated) {
                    SteadinessAnalyzer.analyze(samples)
                }.value
                steadiness = result
                if result == nil { message = "Not enough motion data was recorded. You can try again." }
            }
        default:
            break
        }
        phase = .done
    }

    // MARK: Navigation

    func redo() {
        runTask?.cancel()
        motion.stop()
        message = nil
        phase = .ready
        switch step {
        case .tapRight: right = nil
        case .tapLeft: left = nil
        case .spiral: spiral = nil; spiralTrace = []
        case .hold: steadiness = nil
        default: break
        }
    }

    func next() {
        message = nil
        phase = .ready
        if let nextStep = Step(rawValue: step.rawValue + 1) { step = nextStep }
    }

    func cancel() {
        runTask?.cancel()
        motion.stop()
    }

    /// No taps on the targets means the test didn't happen (not a tap speed of 0): save nothing.
    private func usable(_ result: TapResult) -> TapResult? {
        guard result.validTaps > 0 else {
            message = "No taps on the circles were recorded. You can try again, or continue."
            return nil
        }
        return result
    }

    // MARK: Results

    var allMetrics: [String: Double] {
        var m: [String: Double] = [:]
        if let right { m[MetricKey.tapRateR] = right.rate }
        if let left { m[MetricKey.tapRateL] = left.rate }
        let hands = [right, left].compactMap { $0 }
        if !hands.isEmpty {
            let totalTaps = hands.reduce(0) { $0 + $1.totalTaps }
            let hits = hands.reduce(0.0) { $0 + $1.accuracy / 100 * Double($1.totalTaps) }
            if totalTaps > 0 { m[MetricKey.tapAccuracy] = hits / Double(totalTaps) * 100 }
            let cvs = hands.compactMap(\.cv)
            if !cvs.isEmpty { m[MetricKey.tapCV] = cvs.reduce(0, +) / Double(cvs.count) }
        }
        if let spiral { m.merge(spiral.metrics) { $1 } }
        if let steadiness { m.merge(steadiness.metrics) { $1 } }
        return m
    }

    func save(in context: ModelContext) {
        guard !saved, !allMetrics.isEmpty else { return }
        let session = MotorSession(date: Date(), metrics: allMetrics)
        context.insert(session)
        try? context.save()
        saved = true
    }
}
