//
//  CareMessage.swift
//  Resonance
//
//  The words and links used to reach family: text messages for alerts, needs and
//  updates, and tel:/sms: links. Messages are sent by the iPhone's own Messages and
//  Phone apps after the person (or someone with them) confirms, so Resonance itself
//  never sends data over the internet.
//  Plain Swift, unit tested in CareMessageTests.
//

import Foundation

enum CareMessage {

    enum Kind: String {
        case alert, need, message, update, call, care

        var title: String {
            switch self {
            case .alert: return "Alert"
            case .need: return "Need"
            case .message: return "Message"
            case .update: return "Update"
            case .call: return "Call"
            case .care: return "Care"
            }
        }

        var icon: String {
            switch self {
            case .alert: return "exclamationmark.triangle.fill"
            case .need: return "hand.raised.fill"
            case .message: return "text.bubble.fill"
            case .update: return "heart.text.square.fill"
            case .call: return "phone.fill"
            case .care: return "checkmark.circle.fill"
            }
        }
    }

    static func timeText(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// Who is speaking: the person's first name, or "Your family member".
    static func sender(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Your family member" : trimmed
    }

    /// The emergency text.
    static func alert(name: String, date: Date) -> String {
        "🚨 \(sender(name)) needs help now. Please come or call right away. (Alert from Resonance, \(timeText(date)).) This is not a call to emergency services."
    }

    /// Something said on the Talk board, passed on to family.
    static func relay(_ text: String, name: String, date: Date) -> String {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let who = name.trimmingCharacters(in: .whitespaces)
        let prefix = who.isEmpty ? "💬 " : "💬 \(who) says: "
        return "\(prefix)\"\(clean)\" (Resonance, \(timeText(date)))"
    }

    /// A quick update chosen on the Family tab.
    static func quick(_ text: String, name: String, date: Date) -> String {
        let who = name.trimmingCharacters(in: .whitespaces)
        return who.isEmpty ? "\(text) (Resonance, \(timeText(date)))" : "\(who): \(text) (Resonance, \(timeText(date)))"
    }

    /// A short daily summary for family. Every part is optional.
    static func dailyUpdate(name: String, date: Date, functionIndex: Double?, doneThisWeek: [String],
                            changes: [String], feeling: String?, feelingsThisWeek: String? = nil) -> String {
        let day = date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        var lines = [trimmed.isEmpty ? "💜 Today's update, \(day)" : "💜 Update from \(trimmed), \(day)"]
        if let feeling { lines.append("Feeling: \(feeling)") }
        if let feelingsThisWeek { lines.append(feelingsThisWeek) }
        if let functionIndex { lines.append("Function Index: \(Int(functionIndex.rounded())) of 100 (100 = my usual level)") }
        if !doneThisWeek.isEmpty { lines.append("Check-ins this week: \(doneThisWeek.joined(separator: ", "))") }
        if changes.isEmpty {
            lines.append("No measures changed more than usual.")
        } else {
            lines.append("Changes to note: \(changes.joined(separator: ", ")). It may be worth mentioning to the care team.")
        }
        lines.append("Sent from Resonance. It tracks change; it does not diagnose.")
        return lines.joined(separator: "\n")
    }

    // MARK: Links

    private static let bodyAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&+=?#")
        return set
    }()

    /// sms: link with recipients and a prefilled message (used when Messages can't be shown in-app).
    static func smsURL(numbers: [String], body: String) -> URL? {
        let list = numbers.map(PhoneNumber.dialable).filter { !$0.isEmpty }
        guard let encoded = body.addingPercentEncoding(withAllowedCharacters: bodyAllowed) else { return nil }
        if list.count == 1 {
            return URL(string: "sms:\(list[0])&body=\(encoded)")
        }
        return URL(string: "sms:/open?addresses=\(list.joined(separator: ","))&body=\(encoded)")
    }

    static func telURL(_ number: String) -> URL? {
        let dial = PhoneNumber.dialable(number)
        guard !dial.isEmpty else { return nil }
        return URL(string: "tel:\(dial)")
    }

    /// Quick updates offered on the Family tab.
    static let quickUpdates: [(text: String, icon: String, kind: Kind)] = [
        ("I'm okay. No need to worry.", "hand.thumbsup.fill", .update),
        ("Please come when you can.", "figure.walk.arrival", .need),
        ("Please call me.", "phone.arrow.down.left.fill", .need),
        ("I need help with something, not urgent.", "hand.raised.fill", .need),
        ("I'm running low on medication.", "pills.fill", .need),
        ("I love you.", "heart.fill", .message),
    ]
}
