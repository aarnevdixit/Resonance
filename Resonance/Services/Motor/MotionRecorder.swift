//
//  MotionRecorder.swift
//  Resonance
//
//  Records device motion at 100 Hz for the steadiness hold (PLAN.pdf Section 10).
//  Motion sensors only work on a real iPhone, not in the Simulator.
//

import Foundation
import CoreMotion

final class MotionRecorder {
    private let manager = CMMotionManager()
    private(set) var samples: [MotionSample] = []

    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    func start() {
        samples = []
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 100
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let a = motion.userAcceleration
            self.samples.append(MotionSample(t: motion.timestamp, x: a.x, y: a.y, z: a.z))
        }
    }

    func stop() {
        if manager.isDeviceMotionActive {
            manager.stopDeviceMotionUpdates()
        }
    }
}
