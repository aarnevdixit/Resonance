//
//  BankedClip.swift
//  Resonance
//
//  A phrase recorded in the user's own voice (PLAN.pdf Sections 8 and 14).
//

import Foundation
import SwiftData

@Model
final class BankedClip {
    var fileName: String    // Documents/Bank/<uuid>.m4a
    var label: String
    var recordedAt: Date

    init(fileName: String, label: String) {
        self.fileName = fileName
        self.label = label
        self.recordedAt = Date()
    }
}
