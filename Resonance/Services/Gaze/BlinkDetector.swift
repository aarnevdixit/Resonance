//
//  BlinkDetector.swift
//  Resonance
//
//  Turns "eyes closed / open" from the TrueDepth camera into deliberate signals:
//  - a long blink (eyes closed 0.4 to 1.5 seconds) chooses the highlighted button;
//  - keeping the eyes closed for the alert time (default 3 seconds) sounds the alert,
//    if the person turned that on.
//  Normal blinks (about 0.1 to 0.3 seconds) are ignored, and so is resting with the eyes
//  closed between 1.5 seconds and the alert time.
//  Plain Swift, unit tested in BlinkDetectorTests.
//

import Foundation

struct BlinkDetector: Equatable {
    enum Event: Equatable { case select, alert }

    var selectMin = 0.4
    var selectMax = 1.5
    var alertAfter = 3.0
    var cooldown = 0.6

    private var closedSince: Double?
    private var alertSent = false
    private var cooldownUntil = 0.0

    /// How long the eyes have been closed (0 when open), for progress rings.
    func closedDuration(now: Double) -> Double {
        closedSince.map { now - $0 } ?? 0
    }

    /// Call on every camera frame. `alertEnabled` turns the eyes-closed alert on or off.
    mutating func update(eyesClosed: Bool, now: Double, alertEnabled: Bool) -> Event? {
        if eyesClosed {
            if closedSince == nil { closedSince = now }
            if alertEnabled, !alertSent, let start = closedSince, now - start >= alertAfter {
                alertSent = true
                return .alert
            }
            return nil
        }
        // Eyes just opened: was it a deliberate long blink?
        defer { closedSince = nil; alertSent = false }
        guard let start = closedSince, !alertSent, now >= cooldownUntil else { return nil }
        let duration = now - start
        if duration >= selectMin && duration <= selectMax {
            cooldownUntil = now + cooldown
            return .select
        }
        return nil
    }

    mutating func reset() {
        closedSince = nil
        alertSent = false
    }
}
