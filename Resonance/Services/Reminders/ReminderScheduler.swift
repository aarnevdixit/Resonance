//
//  ReminderScheduler.swift
//  Resonance
//
//  Weekly check-in reminder (PLAN.pdf Section 15), scheduled on the iPhone itself.
//

import Foundation
import UserNotifications

enum ReminderScheduler {
    static let weeklyID = "resonance.weekly"

    /// Asks permission (first time), then schedules a repeating weekly reminder.
    /// weekday: 1 = Sunday ... 7 = Saturday.
    static func scheduleWeekly(weekday: Int, hour: Int, minute: Int) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return false }

        center.removePendingNotificationRequests(withIdentifiers: [weeklyID])

        let content = UNMutableNotificationContent()
        content.title = "Time for your weekly check-in"
        content.body = "Voice, breath, movement and daily questions take about 6 minutes."
        content.sound = .default

        var components = DateComponents()
        components.weekday = weekday
        components.hour = hour
        components.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: weeklyID, content: content, trigger: trigger)
        do {
            try await center.add(request)
            return true
        } catch {
            return false
        }
    }

    static func cancelWeekly() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [weeklyID])
    }
}
