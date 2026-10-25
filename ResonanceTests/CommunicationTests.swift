//
//  CommunicationTests.swift
//  ResonanceTests
//
//  Pain sentences, switch scanning, blink detection, phone numbers and family messages.
//

import Testing
import Foundation
@testable import Resonance

struct PainPhraseTests {
    @Test func fullSentence() {
        #expect(PainPhrase.sentence(area: .back, level: 7) == "I'm in pain. My back hurts. It's a 7 out of 10, bad.")
    }

    @Test func pluralAreasUseHurt() {
        #expect(PainArea.feet.sentence == "My feet hurt.")
        #expect(PainArea.allOver.sentence == "I hurt all over.")
        #expect(PainArea.throat.sentence == "My throat hurts.")
    }

    @Test func partsAreOptional() {
        #expect(PainPhrase.sentence(area: nil, level: nil) == "I'm in pain.")
        #expect(PainPhrase.sentence(area: nil, level: 10) == "I'm in pain. It's a 10 out of 10, the worst.")
    }

    @Test func eightTakesAn() {
        #expect(PainPhrase.levelSentence(8) == "It's an 8 out of 10, very bad.")
    }

    @Test func levelsAreClampedAndNamed() {
        #expect(PainPhrase.levelSentence(14) == "It's a 10 out of 10, the worst.")
        #expect(PainPhrase.word(for: 2) == "mild")
        #expect(PainPhrase.word(for: 5) == "moderate")
    }

    @Test func boardFitsTwelveAreas() {
        #expect(PainArea.board.count == 12)
    }
}

struct ScannerTests {
    let rows = [["yes", "no", "pain"], ["keyboard"], ["a", "b"]]

    @Test func rowsLightUpInTurn() {
        var s = Scanner(groups: rows)
        #expect(s.highlighted == ["yes", "no", "pain"])
        s.advance()
        #expect(s.highlighted == ["keyboard"])
        s.advance(); s.advance()
        #expect(s.highlighted == ["yes", "no", "pain"])   // wraps around
    }

    @Test func choosingARowThenAButton() {
        var s = Scanner(groups: rows)
        #expect(s.select() == nil)            // opens the first row
        #expect(s.highlighted == ["yes"])
        s.advance()
        #expect(s.highlighted == ["no"])
        #expect(s.select() == "no")
        #expect(s.level == .groups)           // starts again from the top
        #expect(s.highlighted == ["yes", "no", "pain"])
    }

    @Test func singleButtonRowActivatesDirectly() {
        var s = Scanner(groups: rows)
        s.advance()
        #expect(s.select() == "keyboard")
    }

    @Test func goesBackToRowsAfterTwoPasses() {
        var s = Scanner(groups: rows)
        s.advance(); s.advance()              // third row
        _ = s.select()
        for _ in 0..<4 { s.advance() }        // two passes of two buttons
        #expect(s.level == .groups)
        #expect(s.highlighted == ["a", "b"])  // back on the same row
    }

    @Test func updatingWithSameRowsKeepsPlace() {
        var s = Scanner(groups: rows)
        s.advance()
        s.update(groups: rows)
        #expect(s.highlighted == ["keyboard"])
        s.update(groups: [["x"]])
        #expect(s.highlighted == ["x"])
    }

    @Test func emptyRowsAreIgnored() {
        var s = Scanner(groups: [[], ["only"]])
        #expect(s.select() == "only")
        var empty = Scanner(groups: [])
        empty.advance()
        #expect(empty.select() == nil)
        #expect(empty.highlighted.isEmpty)
    }
}

struct BlinkDetectorTests {
    /// Eyes closed from `start` for `length` seconds, sampled at 60 Hz. Returns the events.
    func run(_ d: inout BlinkDetector, start: Double, length: Double, alert: Bool = false) -> [BlinkDetector.Event] {
        var events: [BlinkDetector.Event] = []
        var t = start
        while t < start + length {
            if let e = d.update(eyesClosed: true, now: t, alertEnabled: alert) { events.append(e) }
            t += 1.0 / 60
        }
        if let e = d.update(eyesClosed: false, now: start + length, alertEnabled: alert) { events.append(e) }
        return events
    }

    @Test func normalBlinkIsIgnored() {
        var d = BlinkDetector()
        #expect(run(&d, start: 0, length: 0.2).isEmpty)
    }

    @Test func longBlinkSelects() {
        var d = BlinkDetector()
        #expect(run(&d, start: 0, length: 0.7) == [.select])
    }

    @Test func restingEyesDoNothing() {
        var d = BlinkDetector()
        #expect(run(&d, start: 0, length: 2.2).isEmpty)
    }

    @Test func eyesClosedAlertOnlyWhenEnabled() {
        var off = BlinkDetector()
        #expect(run(&off, start: 0, length: 3.5, alert: false).isEmpty)
        var on = BlinkDetector()
        #expect(run(&on, start: 0, length: 3.5, alert: true) == [.alert])   // once, and no select on opening
    }

    @Test func cooldownStopsDoubleSelect() {
        var d = BlinkDetector()
        #expect(run(&d, start: 0, length: 0.6) == [.select])
        #expect(run(&d, start: 0.7, length: 0.45).isEmpty)       // within the 0.6 s cooldown
        #expect(run(&d, start: 3, length: 0.6) == [.select])
    }
}

struct CareMessageTests {
    let date = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func phoneNumbersAreCleaned() {
        #expect(PhoneNumber.dialable("(555) 010-2030") == "5550102030")
        #expect(PhoneNumber.dialable("+1 555 010 2030") == "+15550102030")
        #expect(PhoneNumber.isValid("911") && !PhoneNumber.isValid("12"))
    }

    @Test func alertNamesThePersonAndIsHonest() {
        let text = CareMessage.alert(name: "Sam", date: date)
        #expect(text.contains("Sam needs help now"))
        #expect(text.contains("not a call to emergency services"))
        #expect(CareMessage.alert(name: " ", date: date).contains("Your family member"))
    }

    @Test func relayQuotesTheWords() {
        #expect(CareMessage.relay("I'm thirsty ", name: "Sam", date: date).contains("Sam says: \"I'm thirsty\""))
    }

    @Test func messagesWithoutANameStayNatural() {
        #expect(CareMessage.quick("I'm okay.", name: " ", date: date).hasPrefix("I'm okay."))
        #expect(CareMessage.quick("I'm okay.", name: "Sam", date: date).hasPrefix("Sam: I'm okay."))
        #expect(CareMessage.relay("Yes", name: "", date: date).hasPrefix("💬 \"Yes\""))
    }

    @Test func smsLinkEncodesTheBody() throws {
        let one = try #require(CareMessage.smsURL(numbers: ["(555) 010-2030"], body: "Hi & bye"))
        #expect(one.absoluteString == "sms:5550102030&body=Hi%20%26%20bye")
        let many = try #require(CareMessage.smsURL(numbers: ["111", "222"], body: "Hi"))
        #expect(many.absoluteString == "sms:/open?addresses=111,222&body=Hi")
    }

    @Test func shortcutLinkCarriesNameAndMessage() throws {
        let url = try #require(AlertShortcut.url(name: "Resonance Alert", message: "Help & come"))
        #expect(url.absoluteString == "shortcuts://run-shortcut?name=Resonance%20Alert&input=text&text=Help%20%26%20come")
        #expect(AlertShortcut.url(name: "  ", message: "Hi") == nil)
        #expect(AlertShortcut.testMessage(name: "Sam").contains("only a test"))
    }

    @Test func telLink() {
        #expect(CareMessage.telURL("555-0102")?.absoluteString == "tel:5550102")
        #expect(CareMessage.telURL("abc") == nil)
    }

    @Test func dailyUpdateMentionsChangesWithCareWording() {
        let text = CareMessage.dailyUpdate(name: "Sam", date: date, functionIndex: 91.6,
                                           doneThisWeek: ["Voice Lab"], changes: ["Syllable rate"], feeling: "Good")
        #expect(text.contains("Function Index: 92"))
        #expect(text.contains("Changes to note: Syllable rate"))
        #expect(text.contains("does not diagnose"))
        let calm = CareMessage.dailyUpdate(name: "Sam", date: date, functionIndex: nil,
                                           doneThisWeek: [], changes: [], feeling: nil)
        #expect(calm.contains("No measures changed more than usual."))
    }
}
