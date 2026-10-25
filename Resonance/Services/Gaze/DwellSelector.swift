//
//  DwellSelector.swift
//  Resonance
//
//  Selects a tile when the pointer stays on it for the dwell time (PLAN.pdf Section 13).
//  - Moving off a tile for longer than `tolerance` (150 ms) resets progress,
//    so a little jitter doesn't restart the timer.
//  - After a selection, nothing can be selected for `cooldown` (1 s).
//

import Foundation

struct DwellSelector {
    var dwell: Double
    var cooldown: Double = 1.0
    var tolerance: Double = 0.15

    private(set) var current: String?
    private var startTime: Double?
    private var lastSeen: Double?
    private var cooldownUntil: Double = 0

    init(dwell: Double) {
        self.dwell = dwell
    }

    /// Call many times a second with the tile under the pointer (or nil).
    /// Returns progress 0...1 for the current tile, and the tile id when it is selected.
    mutating func update(tile: String?, now: Double) -> (progress: Double, selected: String?) {
        if now < cooldownUntil {
            current = nil; startTime = nil; lastSeen = nil
            return (0, nil)
        }

        if let tile, tile == current, let start = startTime {
            lastSeen = now
            let progress = (now - start) / dwell
            if progress >= 1 {
                current = nil; startTime = nil; lastSeen = nil
                cooldownUntil = now + cooldown
                return (1, tile)
            }
            return (progress, nil)
        }

        // Briefly off the tile: keep the progress for a moment.
        if tile == nil, current != nil, let seen = lastSeen, let start = startTime, now - seen < tolerance {
            return ((now - start) / dwell, nil)
        }

        // A new tile (or nothing).
        current = tile
        startTime = tile == nil ? nil : now
        lastSeen = tile == nil ? nil : now
        return (0, nil)
    }

    mutating func reset() {
        current = nil; startTime = nil; lastSeen = nil
    }
}
