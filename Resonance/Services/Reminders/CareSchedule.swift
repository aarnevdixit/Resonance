//
//  CareSchedule.swift
//  Resonance
//
//  Daily care reminders for the person and their helpers: medicines, turning in bed,
//  water, mouth care, breathing equipment. Each one is a repeating local notification
//  on this iPhone (nothing is sent anywhere).
//  The timing logic is plain Swift, unit tested in CareScheduleTests.
//

import Foundation
import SwiftData
import UserNotifications

@Model
final class CareReminder {
    var identifier: String = UUID().uuidString
    var title: String
    var kind: String          // CareReminderKind.rawValue
    var hour: Int
    var minute: Int
    var enabled: Bool = true
    var createdAt: Date = Date()

    init(title: String, kind: CareReminderKind, hour: Int, minute: Int) {
        self.title = title
        self.kind = kind.rawValue
        self.hour = hour
        self.minute = minute
    }

    var reminderKind: CareReminderKind { CareReminderKind(rawValue: kind) ?? .other }
    var timeText: String { CareSchedule.timeText(hour: hour, minute: minute) }
}

enum CareReminderKind: String, CaseIterable, Identifiable {
    case medication, reposition, water, mouthCare, breathing, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .medication: return "Medicine"
        case .reposition: return "Turning"
        case .water: return "Water"
        case .mouthCare: return "Mouth care"
        case .breathing: return "Breathing"
        case .other: return "Other"
        }
    }

    var icon: String {
        switch self {
        case .medication: return "pills.fill"
        case .reposition: return "bed.double.fill"
        case .water: return "drop.fill"
        case .mouthCare: return "mouth.fill"
        case .breathing: return "lungs.fill"
        case .other: return "bell.fill"
        }
    }

    /// A sensible first title for the add form.
    var suggestedTitle: String {
        switch self {
        case .medication: return "Take medicine"
        case .reposition: return "Help me change position"
        case .water: return "Drink some water"
        case .mouthCare: return "Mouth care"
        case .breathing: return "Check breathing equipment"
        case .other: return ""
        }
    }
}

enum CareSchedule {
    static func timeText(hour: Int, minute: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let date = Calendar.current.date(from: components) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    struct Upcoming: Equatable {
        var title: String
        var date: Date
    }

    /// The next time each enabled reminder goes off after `now` (today, or tomorrow if it
    /// already passed), soonest first.
    static func upcoming(_ items: [(title: String, hour: Int, minute: Int, enabled: Bool)],
                         now: Date, calendar: Calendar = .current) -> [Upcoming] {
        items.compactMap { item -> Upcoming? in
            guard item.enabled,
                  (0...23).contains(item.hour), (0...59).contains(item.minute),
                  let today = calendar.date(bySettingHour: item.hour, minute: item.minute, second: 0, of: now) else { return nil }
            let next = today > now ? today : (calendar.date(byAdding: .day, value: 1, to: today) ?? today)
            return Upcoming(title: item.title, date: next)
        }
        .sorted { $0.date < $1.date }
    }

    // MARK: Notifications

    static func notificationID(_ reminder: CareReminder) -> String { "resonance.care.\(reminder.identifier)" }

    // Buttons on the reminder notification (touch and hold it, or pull it down).
    static let categoryID = "resonance.care"
    static let doneAction = "resonance.care.done"
    static let snoozeAction = "resonance.care.snooze"
    static let snoozeMinutes = 10

    /// Registers the Done / Remind me later buttons. Safe to call more than once.
    static func registerActions() {
        let done = UNNotificationAction(identifier: doneAction, title: "Done", options: [])
        let snooze = UNNotificationAction(identifier: snoozeAction,
                                          title: "Remind me in \(snoozeMinutes) min", options: [])
        let category = UNNotificationCategory(identifier: categoryID, actions: [done, snooze],
                                              intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    /// The line added to the Family activity when a reminder is marked done.
    static func doneLogText(title: String, at date: Date) -> String {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(clean.isEmpty ? "Care reminder" : clean): done at \(date.formatted(date: .omitted, time: .shortened))"
    }

    /// Asks for permission the first time. Returns false if notifications are off.
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Schedules (or reschedules) one daily reminder; removes it when disabled.
    static func sync(_ reminder: CareReminder) async {
        let center = UNUserNotificationCenter.current()
        let id = notificationID(reminder)
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard reminder.enabled else { return }
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = "Resonance care reminder, \(reminder.timeText)"
        content.sound = .default
        content.categoryIdentifier = categoryID
        content.userInfo = ["title": reminder.title]
        var components = DateComponents()
        components.hour = reminder.hour
        components.minute = reminder.minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    static func remove(_ reminder: CareReminder) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationID(reminder)])
    }
}
