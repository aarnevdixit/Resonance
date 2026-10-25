//
//  CareContact.swift
//  Resonance
//
//  Family members and caregivers who receive alerts, needs and messages by text,
//  and who can be called with one tap. Stored only on this iPhone.
//

import Foundation
import SwiftData

@Model
final class CareContact {
    var name: String
    var phone: String
    var relation: String          // "Daughter", "Husband", "Nurse"…
    var isPrimary: Bool = false   // called first from the alert screen
    var receivesAlerts: Bool = true
    var createdAt: Date = Date()

    init(name: String, phone: String, relation: String = "", isPrimary: Bool = false) {
        self.name = name
        self.phone = phone
        self.relation = relation
        self.isPrimary = isPrimary
    }

    /// "Mom" → "M", "Ana Lopez" → "AL".
    var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first.map { String($0).uppercased() } }
        return letters.isEmpty ? "?" : letters.joined()
    }

    /// "Kate Bell" → "Kate", for short button labels.
    var firstName: String {
        name.split(separator: " ").first.map(String.init) ?? name
    }

    /// Digits and a leading + only, for tel: and sms: links.
    var dialable: String { PhoneNumber.dialable(phone) }
}

/// Something sent to (or shown for) family: an alert, a need, a message or a call.
@Model
final class CareEvent {
    var date: Date
    var kind: String        // "alert", "need", "message", "call", "update"
    var text: String
    var recipients: String  // names, comma separated

    init(kind: String, text: String, recipients: String, date: Date = Date()) {
        self.kind = kind
        self.text = text
        self.recipients = recipients
        self.date = date
    }
}

enum PhoneNumber {
    /// Keeps digits and a leading "+", so "(555) 010-2030" becomes "5550102030".
    static func dialable(_ raw: String) -> String {
        var out = ""
        for (i, ch) in raw.trimmingCharacters(in: .whitespaces).enumerated() {
            if ch.isNumber { out.append(ch) } else if ch == "+" && i == 0 { out.append(ch) }
        }
        return out
    }

    /// A number is usable when it has at least 3 digits (short codes and full numbers).
    static func isValid(_ raw: String) -> Bool {
        dialable(raw).filter(\.isNumber).count >= 3
    }
}
