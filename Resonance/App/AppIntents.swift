//
//  AppIntents.swift
//  Resonance
//
//  Shortcuts that work without touching the app:
//  - "Sound the Resonance alert": opens Resonance and starts the loud alert.
//  - "Open the Talk board": opens Resonance on the Talk tab.
//  They appear in the Shortcuts app and Siri, and can be put on the Action button or on
//  Back Tap (Settings > Accessibility > Touch > Back Tap), so a caregiver can set up a
//  double tap on the back of the phone that sounds the alert.
//
//  Uses AppIntents, an Apple framework not listed in CLAUDE.md. It adds no network code.
//

import AppIntents
import Foundation
import Observation
import SwiftUI
import SwiftData
import UIKit

/// Lets shortcuts ask the running app to show something.
@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()
    var showAlert = false

    func openTalk() {
        UserDefaults.standard.set(AppTab.talk.rawValue, forKey: "selectedTab")
    }
}

/// The alert's own window controller, so it can be told apart from SwiftUI's sheets.
final class AlertHostingController: UIHostingController<AnyView> {}

/// Shows the alert full screen above anything else that is open.
@MainActor
enum AlertPresenter {
    /// How many alert screens are open (one closing while another opens can briefly be 2).
    static var openCount = 0
    /// True while any alert screen is showing (from a shortcut or the Talk board).
    static var isShowing: Bool { openCount > 0 }

    /// Returns false if nothing could present yet (for example during launch), so the
    /// caller can try again.
    @discardableResult
    static func present(container: ModelContainer) -> Bool {
        if isShowing { return true }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed { top = presented }
        guard let top, top.view.window != nil else { return false }
        if top is AlertHostingController { return true }
        // Something is still animating in or out: UIKit would refuse, so let the caller retry.
        guard top.transitionCoordinator == nil, top.presentedViewController == nil else { return false }
        let host = AlertHostingController(rootView: AnyView(EmptyView()))
        host.rootView = AnyView(EmergencyAlertView(onStop: { [weak host] in
            host?.dismiss(animated: true)
        }).modelContainer(container))
        host.modalPresentationStyle = .fullScreen
        top.present(host, animated: true)
        return true
    }
}

struct SoundAlertIntent: AppIntent {
    static let title: LocalizedStringResource = "Sound the Resonance alert"
    static let description = IntentDescription("Opens Resonance and plays the loud alert to get attention nearby. It does not contact emergency services.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.openTalk()
        AppRouter.shared.showAlert = true
        return .result()
    }
}

struct OpenTalkBoardIntent: AppIntent {
    static let title: LocalizedStringResource = "Open the Talk board"
    static let description = IntentDescription("Opens Resonance on the Talk board.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.openTalk()
        return .result()
    }
}

struct ResonanceShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: SoundAlertIntent(),
                    phrases: ["Sound the alert in \(.applicationName)", "\(.applicationName) alert",
                              "Get help with \(.applicationName)"],
                    shortTitle: "Sound the alert",
                    systemImageName: "exclamationmark.triangle.fill")
        AppShortcut(intent: OpenTalkBoardIntent(),
                    phrases: ["Open \(.applicationName) Talk board", "Talk with \(.applicationName)"],
                    shortTitle: "Talk board",
                    systemImageName: "bubble.left.and.bubble.right.fill")
    }
}
