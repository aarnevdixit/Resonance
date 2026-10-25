//
//  FeelingTests.swift
//  ResonanceTests
//
//  Feeling sentences and the weekly feelings summary for family.
//

import Testing
import Foundation
@testable import Resonance

struct FeelingTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func sentencesReadNaturally() {
        #expect(FeelingPhrase.sentence(.sad) == "I feel sad.")
        #expect(FeelingPhrase.sentence(.tired, intensity: .aLittle) == "I feel a little tired.")
        #expect(FeelingPhrase.sentence(.scared, intensity: .very) == "I feel very scared.")
        #expect(FeelingPhrase.sentence(.okay) == "I'm okay.")
    }

    @Test func followUpOnlyWhenItHelps() {
        #expect(FeelingPhrase.full(.lonely) == "I feel lonely. Please sit with me.")
        #expect(FeelingPhrase.full(.happy) == "I feel happy.")
    }

    @Test func boardHasNineFacesAndEveryFeelingHasAnEmoji() {
        #expect(Feeling.board.count == 9)
        #expect(Feeling.allCases.allSatisfy { !$0.emoji.isEmpty })
    }

    @Test func summaryCountsTheLastWeekMostFrequentFirst() {
        let day = 86_400.0
        let entries: [(date: Date, feeling: String)] = [
            (now.addingTimeInterval(-1 * day), "tired"),
            (now.addingTimeInterval(-2 * day), "tired"),
            (now.addingTimeInterval(-3 * day), "happy"),
            (now.addingTimeInterval(-10 * day), "sad"),       // older than a week
            (now.addingTimeInterval(-1 * day), "not-a-feeling"),
        ]
        let counts = FeelingSummary.recent(entries, now: now)
        #expect(counts == [.init(feeling: .tired, times: 2), .init(feeling: .happy, times: 1)])
        #expect(FeelingSummary.line(counts) == "Feelings shared this week: tired (2), happy (1)")
        #expect(FeelingSummary.line([]) == nil)
    }

    @Test func tiesGoToTheMostRecent() {
        let entries: [(date: Date, feeling: String)] = [
            (now.addingTimeInterval(-5 * 86_400), "sad"),
            (now.addingTimeInterval(-3_600), "happy"),
        ]
        #expect(FeelingSummary.recent(entries, now: now).first?.feeling == .happy)
    }
}
