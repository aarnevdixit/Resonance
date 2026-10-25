//
//  CareScheduleTests.swift
//  ResonanceTests
//
//  Which care reminder comes next.
//

import Testing
import Foundation
@testable import Resonance

struct CareScheduleTests {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }()

    /// Oct 24, 2026, 12:30 in Los Angeles.
    var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 12, minute: 30))!
    }

    @Test func laterTodayComesBeforeTomorrow() {
        let items: [(title: String, hour: Int, minute: Int, enabled: Bool)] = [
            ("Morning medicine", 8, 0, true),     // already passed: tomorrow
            ("Reposition", 14, 0, true),          // later today
            ("Evening medicine", 20, 30, true),
        ]
        let next = CareSchedule.upcoming(items, now: now, calendar: calendar)
        #expect(next.map(\.title) == ["Reposition", "Evening medicine", "Morning medicine"])
        #expect(calendar.component(.day, from: next[2].date) == 25)
    }

    @Test func disabledAndInvalidTimesAreSkipped() {
        let items: [(title: String, hour: Int, minute: Int, enabled: Bool)] = [
            ("Off", 14, 0, false),
            ("Bad hour", 25, 0, true),
            ("Bad minute", 10, 75, true),
        ]
        #expect(CareSchedule.upcoming(items, now: now, calendar: calendar).isEmpty)
    }

    @Test func exactlyNowMovesToTomorrow() {
        let items: [(title: String, hour: Int, minute: Int, enabled: Bool)] = [("Now", 12, 30, true)]
        let next = CareSchedule.upcoming(items, now: now, calendar: calendar)
        #expect(calendar.component(.day, from: next[0].date) == 25)
    }

    @Test func doneLineNamesTheReminderAndTime() {
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 9, minute: 2))!
        let text = CareSchedule.doneLogText(title: "  Take medicine ", at: date)
        #expect(text.hasPrefix("Take medicine: done at "))
        #expect(CareSchedule.doneLogText(title: "", at: date).hasPrefix("Care reminder: done at "))
    }

    @Test func careEventsHaveTheirOwnKind() {
        #expect(CareMessage.Kind(rawValue: "care") == .care)
        #expect(CareMessage.Kind.care.title == "Care")
    }

    @Test func everyKindHasATitleAndIcon() {
        for kind in CareReminderKind.allCases {
            #expect(!kind.label.isEmpty && !kind.icon.isEmpty)
        }
    }

    @Test func suggestedTitlesExistExceptOther() {
        for kind in CareReminderKind.allCases where kind != .other {
            #expect(!kind.suggestedTitle.isEmpty)
        }
        #expect(CareReminderKind.other.suggestedTitle.isEmpty)
    }

    @Test func midnightReminderIsTomorrowAtMidnight() {
        let items: [(title: String, hour: Int, minute: Int, enabled: Bool)] = [("Night", 0, 0, true)]
        let next = CareSchedule.upcoming(items, now: now, calendar: calendar)
        #expect(calendar.component(.day, from: next[0].date) == 25)
        #expect(calendar.component(.hour, from: next[0].date) == 0)
    }
}
