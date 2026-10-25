//
//  Explanations.swift
//  Resonance
//
//  Plain-language text that connects every measurement and exercise to why it matters.
//  Used by "Why this test?" before an exercise and "What this means" after it.
//  Wording rule (PLAN.pdf Section 21): describe change, never diagnose.
//

import Foundation

/// What a measurement shows, in everyday words.
struct MetricExplanation {
    /// One sentence: what this number measures.
    let measures: String
    /// One sentence: what it usually means when it gets worse.
    let whenWorse: String
}

enum Explanations {

    static func metric(_ key: String) -> MetricExplanation? { metrics[key] }

    static let metrics: [String: MetricExplanation] = [
        MetricKey.mpt: .init(
            measures: "How long you can hold a steady \"ahh\" on one breath.",
            whenWorse: "A shorter hold can mean weaker breathing muscles or less control of the voice box."),
        MetricKey.f0Mean: .init(
            measures: "The average pitch of your voice.",
            whenWorse: "Pitch on its own varies from person to person; a big shift from your baseline is worth noting."),
        MetricKey.f0StdSemi: .init(
            measures: "How much your pitch wobbles while you hold \"ahh\".",
            whenWorse: "More wobble can mean the muscles that control the vocal cords are less steady."),
        MetricKey.jitter: .init(
            measures: "Tiny cycle-to-cycle changes in pitch (jitter).",
            whenWorse: "Higher jitter often sounds rougher or shakier."),
        MetricKey.shimmer: .init(
            measures: "Tiny cycle-to-cycle changes in loudness (shimmer).",
            whenWorse: "Higher shimmer often sounds breathier or less stable."),
        MetricKey.cpp: .init(
            measures: "Voice clarity: how clearly the voice stands out from breath noise.",
            whenWorse: "Lower clarity usually sounds breathier or hoarser."),
        MetricKey.f2Eee: .init(
            measures: "How high and forward your tongue reaches when you say \"eee\".",
            whenWorse: "Less reach can mean the tongue is getting weaker, which affects clear speech and swallowing."),
        MetricKey.vowelSpace: .init(
            measures: "How different your \"ahh\" and \"eee\" sound, which reflects how far the tongue and jaw move.",
            whenWorse: "A smaller vowel space makes vowels sound more alike and speech harder to understand."),
        MetricKey.ddkRate: .init(
            measures: "How fast you can repeat \"pa-ta-ka\" (lips, tongue tip, back of tongue).",
            whenWorse: "A slower rate can mean the mouth muscles are switching more slowly."),
        MetricKey.ddkCV: .init(
            measures: "How even the rhythm of your \"pa-ta-ka\" is.",
            whenWorse: "A less even rhythm can mean coordination is getting harder."),
        MetricKey.wpm: .init(
            measures: "How many words per minute you read.",
            whenWorse: "Slower reading can mean speaking takes more effort."),
        MetricKey.sylPerSec: .init(
            measures: "How many syllables per second you speak while reading.",
            whenWorse: "A lower rate can mean speech is slowing down."),
        MetricKey.pauseRatio: .init(
            measures: "How much of your reading time is pauses.",
            whenWorse: "More pausing can mean you need more breaths or more effort to speak."),
        MetricKey.intelligibility: .init(
            measures: "How many words a computer understood correctly (word clarity).",
            whenWorse: "Lower clarity suggests other people may also find speech harder to understand."),
        MetricKey.loudnessDb: .init(
            measures: "How loud your reading voice is at the phone.",
            whenWorse: "A quieter voice can mean less breath support."),
        MetricKey.speechChangeScore: .init(
            measures: SpeechChangeModel.explanation,
            whenWorse: "A score that keeps rising over several weeks can mean your voice is changing; one high score alone means little."),
        MetricKey.breathCount: .init(
            measures: "How far you can count out loud on a single breath.",
            whenWorse: "A lower count can mean the breathing muscles are getting weaker. Breathing changes are important to share with your care team."),
        MetricKey.breathSeconds: .init(
            measures: "How long you kept speaking on that single breath.",
            whenWorse: "A shorter breath can mean less breathing reserve."),
        MetricKey.tapRateR: .init(
            measures: "How fast your right index finger taps between two targets.",
            whenWorse: "Slower tapping can mean less strength or speed in the hand."),
        MetricKey.tapRateL: .init(
            measures: "How fast your left index finger taps between two targets.",
            whenWorse: "Slower tapping can mean less strength or speed in the hand."),
        MetricKey.tapAccuracy: .init(
            measures: "How many taps landed on the targets.",
            whenWorse: "Lower accuracy can mean finger control is getting harder."),
        MetricKey.tapCV: .init(
            measures: "How even the rhythm of your tapping is.",
            whenWorse: "A less even rhythm can mean coordination is getting harder."),
        MetricKey.steadyRMS: .init(
            measures: "How still you can hold the phone with your arm out.",
            whenWorse: "More movement can mean the arm and shoulder muscles tire or shake more."),
        MetricKey.fatigueRatio: .init(
            measures: "How much steadier you were at the start of the hold than at the end.",
            whenWorse: "A bigger difference can mean muscles tire faster."),
        MetricKey.tremorBand: .init(
            measures: "How much of the hand movement is a fast, regular shake (3-12 Hz).",
            whenWorse: "More shake in this band can mean more tremor or muscle twitching."),
        MetricKey.spiralError: .init(
            measures: "How far your finger strayed from the spiral line, on average.",
            whenWorse: "Straying further can mean fine finger control is getting harder."),
        MetricKey.spiralSpeed: .init(
            measures: "How fast you traced the spiral.",
            whenWorse: "Slower tracing can mean movements take more effort."),
        MetricKey.spiralTremor: .init(
            measures: "How shaky the traced line was (small back-and-forth wiggles).",
            whenWorse: "More wiggle can mean more tremor or less steady muscles."),
        MetricKey.functionTotal: .init(
            measures: "Your daily function score: speech, swallowing, hands, care, walking, stairs, breathing and energy.",
            whenWorse: "A lower score can mean daily tasks are getting harder; look at which questions changed."),
    ]
}

/// Every exercise, with what it tests and why it matters. Shown as "Why this test?".
enum Exercise: String, CaseIterable, Identifiable {
    case ahh, eee, pataka, reading, breath, tapping, spiral, hold, dailyCheck

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ahh: return "Hold \"ahh\""
        case .eee: return "Hold \"eee\""
        case .pataka: return "\"Pa-ta-ka\""
        case .reading: return "Read aloud"
        case .breath: return "Count on one breath"
        case .tapping: return "Finger tapping"
        case .spiral: return "Trace the spiral"
        case .hold: return "Hold the phone still"
        case .dailyCheck: return "Daily Function Check"
        }
    }

    /// The body system this exercise looks at.
    var tests: String {
        switch self {
        case .ahh: return "Breathing and the voice box"
        case .eee: return "Tongue movement"
        case .pataka: return "Speed of the lips and tongue"
        case .reading: return "Everyday speech"
        case .breath: return "Breathing strength"
        case .tapping: return "Hand speed and coordination"
        case .spiral: return "Fine finger control and tremor"
        case .hold: return "Arm steadiness and fatigue"
        case .dailyCheck: return "How daily life feels"
        }
    }

    var why: String {
        switch self {
        case .ahh:
            return "Your mouth stays open and still, so the app hears only your lungs and vocal cords. How long you can hold it shows breath control, and how steady it sounds shows how well the voice box is controlled."
        case .eee:
            return "To say \"eee\" the tongue must push high and forward. Comparing it with \"ahh\" shows how far your tongue really moves. Tongue weakness often appears early in ALS and affects both speech and swallowing."
        case .pataka:
            return "Pa uses the lips, ta the tip of the tongue, and ka the back of the tongue. Repeating them fast is a standard speech-clinic test of how quickly and evenly those muscles switch."
        case .reading:
            return "Reading a short passage measures real speech: speaking rate, pauses, and how many words a computer can understand. It is the closest test to everyday talking."
        case .breath:
            return "Counting out loud on one breath is a quick bedside check many clinics use for breathing strength. Breathing muscles can weaken in ALS, and catching changes early helps your care team plan support in time."
        case .tapping:
            return "Tapping two targets as fast as you can measures speed, accuracy and rhythm for each hand separately, so changes in one hand show up clearly."
        case .spiral:
            return "Tracing a spiral needs smooth, continuous finger control. It shows accuracy, speed and small shakes that are hard to notice by eye."
        case .hold:
            return "Holding the phone out with your arm extended shows steadiness, tremor, and how quickly the muscles tire."
        case .dailyCheck:
            return "Eight quick questions cover speech, swallowing, hands, self-care, walking, stairs, breathing and energy. They capture how changes feel in real life, which no sensor can measure."
        }
    }

    /// The metrics this exercise produces.
    var metricKeys: [String] {
        switch self {
        case .ahh: return [MetricKey.mpt, MetricKey.f0StdSemi, MetricKey.jitter, MetricKey.shimmer, MetricKey.cpp]
        case .eee: return [MetricKey.f2Eee, MetricKey.vowelSpace]
        case .pataka: return [MetricKey.ddkRate, MetricKey.ddkCV]
        case .reading: return [MetricKey.wpm, MetricKey.pauseRatio, MetricKey.intelligibility]
        case .breath: return [MetricKey.breathCount, MetricKey.breathSeconds]
        case .tapping: return [MetricKey.tapRateR, MetricKey.tapRateL, MetricKey.tapAccuracy, MetricKey.tapCV]
        case .spiral: return [MetricKey.spiralError, MetricKey.spiralSpeed, MetricKey.spiralTremor]
        case .hold: return [MetricKey.steadyRMS, MetricKey.fatigueRatio, MetricKey.tremorBand]
        case .dailyCheck: return [MetricKey.functionTotal]
        }
    }
}
