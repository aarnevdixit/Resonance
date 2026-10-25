//
//  NotificationHandler.swift
//  Resonance
//
//  Handles taps on Resonance notifications:
//  - care reminders show as banners even while the app is open (iOS hides them otherwise);
//  - "Done" adds a line to the Family activity ("Take medicine: done at 9:02 AM");
//  - "Remind me in 10 min" schedules one more reminder.
//  Everything stays on this iPhone.
//

import Foundation
import SwiftData
import UserNotifications

final class NotificationHandler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationHandler()

    /// Set at launch so "Done" can save to the app's data.
    var container: ModelContainer?

    func install(container: ModelContainer) {
        self.container = container
        UNUserNotificationCenter.current().delegate = self
        CareSchedule.registerActions()
    }

    // Show reminders while the app is in front, too.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let content = response.notification.request.content
        let title = content.userInfo["title"] as? String ?? content.title
        switch response.actionIdentifier {
        case CareSchedule.doneAction:
            let text = CareSchedule.doneLogText(title: title, at: Date())
            DispatchQueue.main.async { [weak self] in
                self?.logDone(text)
                completionHandler()
            }
        case CareSchedule.snoozeAction:
            let again = UNMutableNotificationContent()
            again.title = content.title
            again.body = content.body
            again.sound = .default
            again.categoryIdentifier = CareSchedule.categoryID
            again.userInfo = content.userInfo
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(CareSchedule.snoozeMinutes * 60),
                                                            repeats: false)
            center.add(UNNotificationRequest(identifier: "resonance.snooze.\(UUID().uuidString)",
                                             content: again, trigger: trigger)) { _ in completionHandler() }
        default:
            completionHandler()
        }
    }

    @MainActor
    private func logDone(_ text: String) {
        guard let container else { return }
        let context = container.mainContext
        context.insert(CareEvent(kind: CareMessage.Kind.care.rawValue, text: text, recipients: ""))
        try? context.save()
    }
}
