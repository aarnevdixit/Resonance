//
//  MetricDefinitions.swift
//  Resonance
//
//  Every measurement the app records, defined once (PLAN.pdf Section 8).
//  The Insights Engine and the charts read from this list.
//

import Foundation

enum Domain: String, CaseIterable {
    case speech, breathing, motor, daily
}

struct MetricDef: Identifiable, Hashable {
    let key: String
    let name: String
    let unit: String
    let domain: Domain
    let higherIsBetter: Bool
    let inIndex: Bool

    var id: String { key }

    init(_ key: String, _ name: String, _ unit: String, _ domain: Domain, _ higherIsBetter: Bool, _ inIndex: Bool) {
        self.key = key
        self.name = name
        self.unit = unit
        self.domain = domain
        self.higherIsBetter = higherIsBetter
        self.inIndex = inIndex
    }
}

/// key, display name, unit, domain, higherIsBetter, inFunctionIndex
let metricDefs: [MetricDef] = [
    .init("mpt",             "Max phonation time",  "s",      .speech, true,  true),
    .init("f0Mean",          "Average pitch",       "Hz",     .speech, true,  false),
    .init("f0StdSemi",       "Pitch variation",     "st",     .speech, false, false),
    .init("jitter",          "Pitch steadiness",    "%",      .speech, false, false),
    .init("shimmer",         "Loudness steadiness", "%",      .speech, false, false),
    .init("ddkRate",         "Pa-ta-ka rate",       "syl/s",  .speech, true,  true),
    .init("ddkCV",           "Pa-ta-ka rhythm",     "CV",     .speech, false, false),
    .init("wpm",             "Speaking rate",       "wpm",    .speech, true,  true),
    .init("sylPerSec",       "Syllable rate",       "syl/s",  .speech, true,  false),
    .init("pauseRatio",      "Pause time",          "%",      .speech, false, false),
    .init("intelligibility", "Word clarity",        "%",      .speech, true,  true),
    .init("loudnessDb",      "Reading loudness",    "dBFS",   .speech, true,  false),
    .init("cpp",             "Voice clarity (CPP)", "dB",     .speech, true,  false),
    .init("f2Eee",           "Tongue reach (eee)",  "kHz",    .speech, true,  false),
    .init("vowelSpace",      "Vowel space",         "kHz",    .speech, true,  false),
    .init("speechChangeScore", "AI Speech Change Score", "/100", .speech, false, false),
    .init("breathCount",     "Count on one breath", "numbers", .breathing, true, false),
    .init("breathSeconds",   "Breath length",       "s",      .breathing, true,  false),
    .init("tapRateR",        "Tap speed (right)",   "taps/s", .motor,  true,  true),
    .init("tapRateL",        "Tap speed (left)",    "taps/s", .motor,  true,  true),
    .init("tapAccuracy",     "Tap accuracy",        "%",      .motor,  true,  true),
    .init("tapCV",           "Tap rhythm",          "CV",     .motor,  false, false),
    .init("steadyRMS",       "Hold steadiness",     "mg",     .motor,  false, true),
    .init("fatigueRatio",    "Hold fatigue",        "ratio",  .motor,  false, false),
    .init("tremorBand",      "Tremor-band power",   "ratio",  .motor,  false, false),
    .init("spiralError",     "Spiral accuracy",     "pt off", .motor,  false, false),
    .init("spiralSpeed",     "Spiral speed",        "pt/s",   .motor,  true,  false),
    .init("spiralTremor",    "Spiral tremor",       "ratio",  .motor,  false, false),
    .init("functionTotal",   "Daily function",      "of 32",  .daily,  true,  true),
]

enum MetricKey {
    static let mpt = "mpt"
    static let f0Mean = "f0Mean"
    static let f0StdSemi = "f0StdSemi"
    static let jitter = "jitter"
    static let shimmer = "shimmer"
    static let ddkRate = "ddkRate"
    static let ddkCV = "ddkCV"
    static let wpm = "wpm"
    static let sylPerSec = "sylPerSec"
    static let pauseRatio = "pauseRatio"
    static let intelligibility = "intelligibility"
    static let loudnessDb = "loudnessDb"
    static let cpp = "cpp"
    static let f2Eee = "f2Eee"
    static let vowelSpace = "vowelSpace"
    static let speechChangeScore = "speechChangeScore"
    static let tapRateR = "tapRateR"
    static let tapRateL = "tapRateL"
    static let tapAccuracy = "tapAccuracy"
    static let tapCV = "tapCV"
    static let steadyRMS = "steadyRMS"
    static let fatigueRatio = "fatigueRatio"
    static let tremorBand = "tremorBand"
    static let functionTotal = "functionTotal"
    static let breathCount = "breathCount"
    static let breathSeconds = "breathSeconds"
    static let spiralError = "spiralError"
    static let spiralSpeed = "spiralSpeed"
    static let spiralTremor = "spiralTremor"
}

extension MetricDef {
    /// Look up a metric definition by key.
    static func named(_ key: String) -> MetricDef? {
        metricDefs.first { $0.key == key }
    }
}
