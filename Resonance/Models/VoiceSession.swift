//
//  VoiceSession.swift
//  Resonance
//
//  One completed Voice Lab check-in (PLAN.pdf Sections 8 and 9).
//  Metrics are stored by key (see MetricDefinitions.swift) so new measures
//  can be added without changing the database schema.
//

import Foundation
import SwiftData

@Model
final class VoiceSession {
    var date: Date
    var metrics: [String: Double]
    var vowelFile: String?          // file names in Documents/Audio
    var eeeFile: String?            // held "eee" (added for the two-vowel Speech Change model)
    var ddkFile: String?
    var readingFile: String?
    var transcript: String?
    var speechChangeScore: Double?  // 0-100, stretch task T21
    var qualityFlags: [String] = [] // e.g. "too_noisy", "too_short"
    var isDemo: Bool = false
    /// "voiceLab" for the full Voice Lab, "breath" for the breath test on its own.
    var kind: String = "voiceLab"

    init(date: Date, metrics: [String: Double]) {
        self.date = date
        self.metrics = metrics
    }
}
