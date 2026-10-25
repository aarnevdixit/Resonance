//
//  NextStepsEngine.swift
//  Resonance
//
//  Turns results into a short, prioritized list of things to do next, each linked to the
//  part of the app that helps. This is what connects the features into one loop:
//
//      Measure  ->  Understand  ->  Act  ->  Keep talking
//
//  Plain Swift, no UI, so every rule is unit tested (NextStepsEngineTests).
//  Wording rule (PLAN.pdf Section 21): suggest, never diagnose.
//

import Foundation

/// Where a next step takes the person.
enum StepDestination: String, Hashable {
    case weeklyCheckIn, voiceLab, breathTest, motorLab, functionCheck
    case voiceBank, talkBoard, headControl, careReport, trends, family
}

enum StepPriority: Int, Comparable {
    case urgent = 0, important = 1, suggested = 2, celebrate = 3
    static func < (a: StepPriority, b: StepPriority) -> Bool { a.rawValue < b.rawValue }
}

struct NextStep: Identifiable, Equatable {
    let id: String
    let priority: StepPriority
    let icon: String          // SF Symbol name
    let title: String
    let detail: String
    let actionLabel: String
    let destination: StepDestination?
}

/// Everything the engine looks at. Built from saved data by `PlanContext.make` (PlanContext.swift).
struct PlanContext {
    var now = Date()
    var lastVoiceLab: Date?
    var lastBreathTest: Date?
    var lastMotorLab: Date?
    var lastFunctionCheck: Date?
    var voiceLabCount = 0
    var motorLabCount = 0
    var insights: [MetricInsight] = []
    /// Answers 0...4 of the latest and previous Daily Function Check (8 questions each).
    var latestAnswers: [Int]?
    var previousAnswers: [Int]?
    var latestBreathCount: Double?
    var bankedPhrases = 0
    var totalPhrases = 0
    var usesHeadControl = false
    var hasDemoDataOnly = false
    /// People on the Family tab (alerts and messages go to them).
    var familyCount = 0
}

enum NextStepsEngine {

    // Daily Function Check question positions.
    static let qSpeech = 0, qSwallow = 1, qHands = 2, qCare = 3, qWalk = 4, qStairs = 5, qBreath = 6, qEnergy = 7

    static let speechKeys: Set<String> = [MetricKey.mpt, MetricKey.ddkRate, MetricKey.wpm, MetricKey.intelligibility,
                                          MetricKey.f2Eee, MetricKey.vowelSpace, MetricKey.cpp, MetricKey.speechChangeScore,
                                          MetricKey.pauseRatio, MetricKey.sylPerSec]
    static let handKeys: Set<String> = [MetricKey.tapRateR, MetricKey.tapRateL, MetricKey.tapAccuracy, MetricKey.tapCV,
                                        MetricKey.spiralError, MetricKey.spiralSpeed, MetricKey.spiralTremor]
    static let breathKeys: Set<String> = [MetricKey.breathCount, MetricKey.breathSeconds]

    /// A single count below this on one breath is worth mentioning to the care team.
    static let lowBreathCount = 20.0

    static func steps(for c: PlanContext, limit: Int = 6) -> [NextStep] {
        var out: [NextStep] = []
        let changed = Set(c.insights.filter { $0.status == .noticeableChange }.map(\.def.key))
        let improved = c.insights.filter { $0.status == .improved }

        func answer(_ q: Int) -> Int? {
            guard let a = c.latestAnswers, a.count == 8 else { return nil }
            return a[q]
        }
        func dropped(_ q: Int) -> Bool {
            guard let a = c.latestAnswers, let p = c.previousAnswers, a.count == 8, p.count == 8 else { return false }
            return p[q] - a[q] >= 2
        }
        func daysSince(_ d: Date?) -> Double? { d.map { c.now.timeIntervalSince($0) / 86_400 } }
        func due(_ d: Date?, every days: Double) -> Bool { (daysSince(d) ?? .infinity) >= days }

        // 1. Breathing comes first: it is the most important change to act on quickly.
        let breathAnswerLow = (answer(qBreath).map { $0 <= 1 } ?? false) || dropped(qBreath)
        let breathMeasureLow = !changed.isDisjoint(with: breathKeys)
            || (c.latestBreathCount.map { $0 < lowBreathCount } ?? false)
        if breathAnswerLow || breathMeasureLow {
            out.append(NextStep(
                id: "breathing-care-team", priority: .urgent, icon: "lungs.fill",
                title: "Talk to your care team about breathing",
                detail: BreathingSafety.message + " Your breathing answers or breath test changed; sharing your Care Report helps them plan support early.",
                actionLabel: "Open Care Report", destination: .careReport))
            if due(c.lastBreathTest, every: 3) {
                out.append(NextStep(
                    id: "breathing-retest", priority: .important, icon: "wind",
                    title: "Repeat the breath test",
                    detail: "A second measurement in the next few days shows whether this is a real change or just a tired day.",
                    actionLabel: "Start breath test", destination: .breathTest))
            }
        }

        // 2. Speech changing: bank your voice while it is strong, and practise the Talk board.
        let speechChanged = !changed.isDisjoint(with: speechKeys)
        let speechAnswerLow = (answer(qSpeech).map { $0 <= 2 } ?? false) || dropped(qSpeech)
        let unbanked = max(0, c.totalPhrases - c.bankedPhrases)
        if speechChanged || speechAnswerLow {
            if unbanked > 0 {
                out.append(NextStep(
                    id: "bank-voice", priority: .important, icon: "music.mic",
                    title: "Record your phrases in your own voice",
                    detail: "Your speech measures changed. You've recorded \(c.bankedPhrases) of \(c.totalPhrases) phrases. Recording them now, while your voice is strong, keeps the Talk board sounding like you.",
                    actionLabel: "Open Voice Bank", destination: .voiceBank))
            }
            out.append(NextStep(
                id: "practise-talk", priority: .suggested, icon: "bubble.left.and.bubble.right.fill",
                title: "Practice with the Talk board",
                detail: "Getting comfortable with it now makes it easier to use on tired days. Try a few phrases and the keyboard.",
                actionLabel: "Open Talk", destination: .talkBoard))
        }

        // 3. Swallowing.
        if (answer(qSwallow).map { $0 <= 2 } ?? false) || dropped(qSwallow) {
            out.append(NextStep(
                id: "swallowing", priority: .important, icon: "fork.knife",
                title: "Mention swallowing to your care team",
                detail: "Coughing, drooling or harder swallowing are worth raising early. A speech-language pathologist can suggest safer ways to eat and drink.",
                actionLabel: "Open Care Report", destination: .careReport))
        }

        // 4. Hands changing: hands-free control keeps the Talk board usable.
        let handsChanged = !changed.isDisjoint(with: handKeys)
        let handsAnswerLow = (answer(qHands).map { $0 <= 2 } ?? false) || dropped(qHands)
        if (handsChanged || handsAnswerLow) && !c.usesHeadControl {
            out.append(NextStep(
                id: "head-control", priority: .important, icon: "face.smiling",
                title: "Try hands-free control",
                detail: "Your hand measures changed. The Talk board can follow your head, or light up buttons in turn for a single switch or a long blink, so you can talk without tapping.",
                actionLabel: "Set up hands-free", destination: .headControl))
        }

        // 5. Walking and stairs.
        if [qWalk, qStairs].contains(where: { (answer($0).map { $0 <= 2 } ?? false) || dropped($0) }) {
            out.append(NextStep(
                id: "mobility", priority: .suggested, icon: "figure.walk",
                title: "Ask about mobility support",
                detail: "A physical or occupational therapist can suggest aids and home changes that save energy and prevent falls.",
                actionLabel: "Open Care Report", destination: .careReport))
        }

        // 6. Any noticeable change: share the report before the next clinic visit.
        if !changed.isEmpty && !out.contains(where: { $0.destination == .careReport }) {
            out.append(NextStep(
                id: "share-report", priority: .important, icon: "doc.richtext.fill",
                title: "Share your Care Report",
                detail: "\(changed.count == 1 ? "1 measure has" : "\(changed.count) measures have") changed more than your usual variation. A one-page report helps your care team see it at your next visit.",
                actionLabel: "Open Care Report", destination: .careReport))
        }

        // 7. Check-ins that are due. One combined step when several are due.
        var dueNames: [String] = []
        if due(c.lastVoiceLab, every: 7) { dueNames.append("Voice Lab") }
        if due(c.lastBreathTest, every: 7) { dueNames.append("breath test") }
        if due(c.lastMotorLab, every: 7) { dueNames.append("Motor Lab") }
        if due(c.lastFunctionCheck, every: 1) { dueNames.append("Daily Function Check") }
        if dueNames.count >= 2 {
            let building = min(c.voiceLabCount, c.motorLabCount) < InsightsEngine.baselineSessions
            out.append(NextStep(
                id: "weekly-check-in", priority: building ? .important : .suggested, icon: "checklist.checked",
                title: building ? "Build your baseline" : "This week's check-in",
                detail: building
                    ? "Resonance compares you with yourself. After 3 weekly check-ins it can tell real changes from normal ups and downs. Due now: \(dueNames.joined(separator: ", "))."
                    : "Due now: \(dueNames.joined(separator: ", ")). About 6 minutes in total.",
                actionLabel: "Start check-in", destination: .weeklyCheckIn))
        } else if let only = dueNames.first {
            let dest: StepDestination = only == "Voice Lab" ? .voiceLab
                : only == "breath test" ? .breathTest
                : only == "Motor Lab" ? .motorLab : .functionCheck
            out.append(NextStep(
                id: "due-\(dest.rawValue)", priority: .suggested, icon: "clock.badge.checkmark",
                title: "Due: \(only)",
                detail: "Keeping the same day each week makes your trends more reliable.",
                actionLabel: "Start", destination: dest))
        }

        // 8. Voice banking is worth starting early even when nothing has changed.
        if !out.contains(where: { $0.id == "bank-voice" }) && c.totalPhrases > 0 && c.bankedPhrases < min(5, c.totalPhrases) {
            out.append(NextStep(
                id: "bank-voice-early", priority: .suggested, icon: "music.mic",
                title: "Start your Voice Bank",
                detail: "Record your most-used phrases in your own voice now. It takes about a minute for five phrases, and the Talk board will play them as you.",
                actionLabel: "Open Voice Bank", destination: .voiceBank))
        }

        // 8b. Alerts and messages need someone to go to.
        if c.familyCount == 0 {
            out.append(NextStep(
                id: "add-family", priority: .suggested, icon: "person.2.fill",
                title: "Add someone who helps you",
                detail: "A family member or caregiver gets your alerts and messages as texts, and you can call them with one tap from the Talk board.",
                actionLabel: "Open Family", destination: .family))
        }

        // 9. Good news is worth saying.
        if let best = improved.first {
            out.append(NextStep(
                id: "improved-\(best.def.key)", priority: .celebrate, icon: "sparkles",
                title: "\(best.def.name) improved",
                detail: "Your last two check-ins were better than your usual range. Keep doing what's working.",
                actionLabel: "See trend", destination: .trends))
        }

        if out.isEmpty {
            out.append(NextStep(
                id: "all-caught-up", priority: .celebrate, icon: "checkmark.seal.fill",
                title: "You're all caught up",
                detail: "Everything is within your normal range and your check-ins are up to date. See you at your next check-in.",
                actionLabel: "See trends", destination: .trends))
        }

        // Stable order: priority first, then the order the rules added them.
        let ordered = out.enumerated().sorted { a, b in
            a.element.priority == b.element.priority ? a.offset < b.offset : a.element.priority < b.element.priority
        }.map(\.element)
        return Array(ordered.prefix(limit))
    }
}
