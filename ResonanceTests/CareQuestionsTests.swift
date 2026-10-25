//
//  CareQuestionsTests.swift
//  ResonanceTests
//
//  The "Questions for my care team" list.
//

import Testing
import Foundation
@testable import Resonance

struct CareQuestionsTests {
    @Test func cleanTidiesSpacesAndLineBreaks() {
        #expect(CareQuestions.clean("  Should I  get\na cough assist? ") == "Should I get a cough assist?")
        #expect(CareQuestions.clean("   \n ") == nil)
    }

    @Test func cleanLimitsLength() throws {
        let long = String(repeating: "a", count: 500)
        let cleaned = try #require(CareQuestions.clean(long))
        #expect(cleaned.count == CareQuestions.maxLength)
        #expect(cleaned.hasSuffix("…"))
    }

    @Test func duplicatesIgnoreCaseAndEndPunctuation() {
        let list = ["When should I start BiPAP?"]
        #expect(CareQuestions.isDuplicate("when should i start bipap", of: list))
        #expect(CareQuestions.isDuplicate("  When should I start BiPAP?! ", of: list))
        #expect(!CareQuestions.isDuplicate("When should I start a feeding tube?", of: list))
    }

    @Test func openListSkipsAskedAndKeepsOrder() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let items: [(text: String, createdAt: Date, asked: Bool)] = [
            ("Second", t0.addingTimeInterval(60), false),
            ("Asked already", t0.addingTimeInterval(30), true),
            ("First", t0, false),
        ]
        #expect(CareQuestions.open(items) == ["First", "Second"])
    }

    @Test func asQuestionAddsAQuestionMarkOnlyWhenNeeded() {
        #expect(CareQuestions.asQuestion("Can I still drive ") == "Can I still drive?")
        #expect(CareQuestions.asQuestion("Is this normal?") == "Is this normal?")
        #expect(CareQuestions.asQuestion("Tell me about BiPAP.") == "Tell me about BiPAP.")
        #expect(CareQuestions.asQuestion("") == "")
    }

    @Test func shareTextNumbersTheQuestions() {
        #expect(CareQuestions.shareText([]) == nil)
        #expect(CareQuestions.shareText(["A?", "B?"]) == "Questions for my care team:\n1. A?\n2. B?")
    }
}
