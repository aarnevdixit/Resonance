//
//  Profile.swift
//  Resonance
//
//  The person using the app and their settings (PLAN.pdf Section 8).
//

import Foundation
import SwiftData

@Model
final class Profile {
    var name: String
    var role: String              // "person", "caregiver", "demo"
    var onsetType: String         // "bulbar", "limb", "unsure"
    var diagnosisDate: Date?
    var dwellSeconds: Double = 1.2
    var inputMode: String = "touch"   // "touch", "head" (head pointer), "scan" (switch scanning)
    var preferPersonalVoice: Bool = true
    /// Switch scanning: seconds each item stays highlighted.
    var scanSeconds: Double = 1.5
    /// Choose with a long blink (eyes closed about half a second) in head and scan modes.
    var blinkToSelect: Bool = false
    /// Sound the alert when the eyes stay closed for `eyesClosedAlertSeconds` (camera modes only).
    var eyesClosedAlert: Bool = false
    var eyesClosedAlertSeconds: Double = 3.0
    /// When the alert starts, also start a call to the first family member.
    var autoCallOnAlert: Bool = false
    /// When the alert starts, run the "Resonance Alert" shortcut that texts family hands-free.
    var alertShortcutEnabled: Bool = false
    var alertShortcutName: String = "Resonance Alert"
    /// Speech rate for the computer voice (0.35 slow … 0.55 fast).
    var speechRate: Double = 0.45
    var createdAt: Date = Date()

    init(name: String, role: String, onsetType: String) {
        self.name = name
        self.role = role
        self.onsetType = onsetType
    }
}
