//
//  SpeechChangeModel.swift
//  Resonance
//
//  AI Speech Change Score (PLAN.pdf Sections 12 and 21, task T21).
//
//  What it does: takes voice features and vowel formants from a held "ahh" and a held "eee"
//  (VoiceFeatures.swift, FormantTracker.swift) and returns 0-100: how much this recording resembles recordings from people with ALS
//  in the Minsk2020 research dataset. It is not a diagnosis and is most useful as a trend.
//
//  Change from the plan: the plan suggested a Create ML model trained on VOC-ALS.
//  VOC-ALS needs a Synapse account and could not be downloaded in time, so the model is
//  trained on the openly licensed Minsk2020 ALS database (Vashkevich & Rushkevich, 2021),
//  in Python with scikit-learn (Scripts/ml). The trained weights are exported as plain
//  Swift arrays (SpeechChangeModelWeights.swift), so no Core ML file is needed and the
//  math is easy to read and unit-test.
//
//  The model runs entirely on the iPhone. No network.
//

import Foundation

enum SpeechChangeModel {

    /// A decision tree stored as parallel arrays, exactly like scikit-learn's tree_ object.
    /// feature[i] < 0 marks a leaf.
    struct Tree {
        let feature: [Int]
        let threshold: [Double]
        let left: [Int]
        let right: [Int]
        let value: [Double]

        init(feature: [Double], threshold: [Double], left: [Double], right: [Double], value: [Double]) {
            self.feature = feature.map { Int($0) }
            self.threshold = threshold
            self.left = left.map { Int($0) }
            self.right = right.map { Int($0) }
            self.value = value
        }

        func evaluate(_ x: [Double]) -> Double {
            var node = 0
            while node >= 0, node < feature.count, feature[node] >= 0 {
                let f = feature[node]
                guard f < x.count else { break }
                node = x[f] <= threshold[node] ? left[node] : right[node]
            }
            return node >= 0 && node < value.count ? value[node] : 0.5
        }
    }

    enum Kind {
        case linear(coef: [Double], intercept: Double)
        case rbfSVM(supportVectors: [[Double]], dualCoef: [Double], intercept: Double, gamma: Double)
        case forest(trees: [Tree])
        case boosting(initial: Double, learningRate: Double, trees: [Tree])
    }

    // MARK: - Public API

    /// Probability-like output in 0...1 from named inputs (SpeechChangeInput.named),
    /// or nil if any input the model needs is missing.
    static func probability(named: [String: Double]) -> Double? {
        var values: [Double] = []
        for (i, name) in featureNames.enumerated() {
            if let v = named[name], v.isFinite {
                values.append(v)
            } else if isFormant(name), i < imputeMedian.count {
                // A formant can be missing in a breathy voice; use the training median,
                // exactly like scikit-learn's SimpleImputer(strategy="median") did in training.
                values.append(imputeMedian[i])
            } else {
                return nil
            }
        }
        return probability(values: values)
    }

    /// The AI Speech Change Score, 0-100, from the "ahh" and "eee" recordings.
    static func score(ahh: VowelAnalysis?, eee: VowelAnalysis?) -> Double? {
        guard let p = probability(named: SpeechChangeInput.named(ahh: ahh, eee: eee)) else { return nil }
        return (p * 100).clamped(to: 0...100)
    }

    static func probability(values raw: [Double]) -> Double? {
        guard raw.count == scalerMean.count, raw.allSatisfy(\.isFinite) else { return nil }
        // Standardize exactly like scikit-learn's StandardScaler.
        var x = [Double](repeating: 0, count: raw.count)
        for i in 0..<raw.count {
            let scale: Double = scalerScale[i] == 0 ? 1 : scalerScale[i]
            x[i] = (raw[i] - scalerMean[i]) / scale
        }

        switch kind {
        case let .linear(coef, intercept):
            var z = intercept
            for i in 0..<min(coef.count, x.count) { z += coef[i] * x[i] }
            return sigmoid(z)

        case let .rbfSVM(supportVectors, dualCoef, intercept, gamma):
            var z = intercept
            for (sv, a) in zip(supportVectors, dualCoef) {
                var d2 = 0.0
                for i in 0..<min(sv.count, x.count) { d2 += (sv[i] - x[i]) * (sv[i] - x[i]) }
                z += a * exp(-gamma * d2)
            }
            return sigmoid(z)

        case let .forest(trees):
            guard !trees.isEmpty else { return nil }
            var sum = 0.0
            for tree in trees { sum += tree.evaluate(x) }
            return sum / Double(trees.count)

        case let .boosting(initial, learningRate, trees):
            var z = initial
            for tree in trees { z += learningRate * tree.evaluate(x) }
            return sigmoid(z)
        }
    }

    // MARK: - Wording (PLAN.pdf Section 21, exact text)

    static let title = "AI Speech Change Score"
    static let explanation = "How much this recording resembles voice recordings from people with ALS in a research dataset. It is not a diagnosis and is most useful as a trend over time."

    // MARK: - Helpers

    static func isFormant(_ name: String) -> Bool {
        name.hasPrefix("F1_") || name.hasPrefix("F2_") || name == "F2ratio" || name == "vowelSpace"
    }

    static func sigmoid(_ z: Double) -> Double { 1 / (1 + exp(-z)) }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
