//
//  AlertShortcut.swift
//  Resonance
//
//  Hands-free texts to family. iOS never lets an app send a text by itself, but the
//  Shortcuts app can: a shortcut's "Send Message" action sends without asking when
//  "Show When Run" is turned off. So a helper builds one shortcut, "Resonance Alert",
//  once; when the alert starts, Resonance runs it and passes the alert text as its input.
//  The shortcut sends the text (optionally with the current location) and opens
//  Resonance again. Messages go through the iPhone's own Messages app, so Resonance
//  itself still sends nothing over the internet.
//  The URL building is plain Swift, unit tested in CommunicationTests.
//

import Foundation

enum AlertShortcut {
    static let defaultName = "Resonance Alert"

    private static let allowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&+=?#")
        return set
    }()

    /// shortcuts://run-shortcut?name=…&input=text&text=…
    static func url(name: String, message: String) -> URL? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let encodedName = trimmed.addingPercentEncoding(withAllowedCharacters: allowed),
              let encodedText = message.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "shortcuts://run-shortcut?name=\(encodedName)&input=text&text=\(encodedText)")
    }

    /// Sent by the "Test it" button, so family know it isn't real.
    static func testMessage(name: String) -> String {
        let who = name.trimmingCharacters(in: .whitespaces)
        return "✅ Test of the Resonance alert\(who.isEmpty ? "" : " from \(who)"). No need to come; this is only a test."
    }

    /// Setup steps shown in Hands-free settings.
    static let setupSteps: [(title: String, detail: String)] = [
        ("Open the Shortcuts app", "It comes with every iPhone. Tap + to make a new shortcut and name it \"Resonance Alert\"."),
        ("Add \"Send Message\"", "Search for Send Message. Set the message to \"Shortcut Input\" and choose the family members to text."),
        ("Turn off \"Show When Run\"", "Tap the arrow on the Send Message action and turn off Show When Run, so it sends without a tap."),
        ("Optional: add your location", "Add \"Get Current Location\" before Send Message and put the location in the message."),
        ("Come back to Resonance", "Add \"Open App\" > Resonance as the last action, so the alert screen comes back."),
        ("Test it here", "Turn on the switch above and tap Test. Family get a message that says it's only a test."),
    ]
}
