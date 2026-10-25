//
//  BreathingSafety.swift
//  Resonance
//
//  The breathing safety rule and its exact message (PLAN.pdf Section 11). Kept in a
//  plain Swift file so every screen and the Next Steps engine use the same words.
//

import Foundation

enum BreathingSafety {
    /// PLAN.pdf Section 11: show the message when breathing is 0 or 1,
    /// or dropped by 2 or more points since the last check.
    static func shouldWarn(current: Int, previous: Int?) -> Bool {
        if current <= 1 { return true }
        if let previous, previous - current >= 2 { return true }
        return false
    }

    static let message = "Breathing changes are important. Please contact your care team. If you are having trouble breathing right now, call 911."
}
