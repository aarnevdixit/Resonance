//
//  MotorSession.swift
//  Resonance
//
//  One completed Motor Lab check-in (PLAN.pdf Sections 8 and 10).
//

import Foundation
import SwiftData

@Model
final class MotorSession {
    var date: Date
    var metrics: [String: Double]
    var qualityFlags: [String] = []
    var isDemo: Bool = false

    init(date: Date, metrics: [String: Double]) {
        self.date = date
        self.metrics = metrics
    }
}
