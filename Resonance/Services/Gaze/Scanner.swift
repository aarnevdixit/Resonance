//
//  Scanner.swift
//  Resonance
//
//  Switch scanning ("row-column scanning"), for people who can make only one movement:
//  a tap anywhere, a Bluetooth switch, or a long blink.
//  1. Rows (groups) light up one after another.
//  2. Choosing a row lights up its buttons one at a time.
//  3. Choosing a button activates it, and scanning starts again from the top.
//  If no button is chosen after two passes through a row, scanning goes back to rows.
//  Plain Swift, unit tested in ScannerTests.
//

import Foundation

struct Scanner: Equatable {
    enum Level: Equatable {
        case groups
        case items(group: Int)
    }

    private(set) var groups: [[String]] = []
    private(set) var level: Level = .groups
    private(set) var index = 0
    private var passes = 0

    /// How many passes through a row's buttons before going back to rows.
    static let passesBeforeBack = 2

    init(groups: [[String]] = []) {
        self.groups = groups.filter { !$0.isEmpty }
    }

    /// The ids highlighted right now: a whole row, or one button.
    var highlighted: Set<String> {
        guard !groups.isEmpty else { return [] }
        switch level {
        case .groups:
            return Set(groups[index % groups.count])
        case .items(let g):
            guard groups.indices.contains(g), !groups[g].isEmpty else { return [] }
            return [groups[g][index % groups[g].count]]
        }
    }

    /// Replace the rows (for example when the board switches to the keyboard).
    /// Starts again from the top only if the rows really changed.
    mutating func update(groups newGroups: [[String]]) {
        let cleaned = newGroups.filter { !$0.isEmpty }
        guard cleaned != groups else { return }
        groups = cleaned
        restart()
    }

    mutating func restart() {
        level = .groups
        index = 0
        passes = 0
    }

    /// Move the highlight to the next row or button (called on a timer).
    mutating func advance() {
        guard !groups.isEmpty else { return }
        switch level {
        case .groups:
            index = (index + 1) % groups.count
        case .items(let g):
            let count = groups[g].count
            index += 1
            if index >= count {
                index = 0
                passes += 1
                if passes >= Self.passesBeforeBack {
                    level = .groups
                    index = g
                    passes = 0
                }
            }
        }
    }

    /// The switch was pressed. Returns the id to activate, or nil if a row was opened.
    mutating func select() -> String? {
        guard !groups.isEmpty else { return nil }
        switch level {
        case .groups:
            let g = index % groups.count
            if groups[g].count == 1 {
                let id = groups[g][0]
                restart()
                return id
            }
            level = .items(group: g)
            index = 0
            passes = 0
            return nil
        case .items(let g):
            let row = groups[g]
            let id = row[index % row.count]
            restart()
            return id
        }
    }
}
