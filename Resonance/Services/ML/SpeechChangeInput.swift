//
//  SpeechChangeInput.swift
//  Resonance
//
//  Builds the named inputs of the Speech Change model from the two held vowels:
//  "ahh" (/a/) and "eee" (/i/). Names match the columns of Scripts/ml/speaker_table.csv,
//  so the exported model can ask for any of them by name (SpeechChangeModel.featureNames).
//

import Foundation

/// Everything measured from one held vowel.
struct VowelAnalysis: Equatable {
    var features: VoiceFeatureVector
    var f1: Double?    // kHz
    var f2: Double?    // kHz

    /// Runs the voice features and the formant tracker on one recording.
    static func analyze(_ samples: [Float]) -> VowelAnalysis? {
        guard let result = VoiceFeatures.analyze(samples) else { return nil }
        let (f1, f2) = FormantTracker.formants(signal: result.signal, frameStarts: result.frameStarts)
        return VowelAnalysis(features: result.features, f1: f1, f2: f2)
    }
}

enum SpeechChangeInput {
    /// Named values: "<feature>_a", "<feature>_i", "F1_a", "F2_a", "F1_i", "F2_i",
    /// "F2ratio" (F2 of eee / F2 of ahh) and "vowelSpace" (distance between the vowels in F1-F2).
    static func named(ahh: VowelAnalysis?, eee: VowelAnalysis?) -> [String: Double] {
        var d: [String: Double] = [:]
        if let ahh {
            for (n, v) in zip(VoiceFeatureVector.names, ahh.features.values) { d[n + "_a"] = v }
            d["F1_a"] = ahh.f1
            d["F2_a"] = ahh.f2
        }
        if let eee {
            for (n, v) in zip(VoiceFeatureVector.names, eee.features.values) { d[n + "_i"] = v }
            d["F1_i"] = eee.f1
            d["F2_i"] = eee.f2
        }
        if let f2i = d["F2_i"], let f2a = d["F2_a"], f2a > 0 {
            d["F2ratio"] = f2i / f2a
        }
        if let f1a = d["F1_a"], let f2a = d["F2_a"], let f1i = d["F1_i"], let f2i = d["F2_i"] {
            d["vowelSpace"] = ((f1a - f1i) * (f1a - f1i) + (f2a - f2i) * (f2a - f2i)).squareRoot()
        }
        return d
    }
}
