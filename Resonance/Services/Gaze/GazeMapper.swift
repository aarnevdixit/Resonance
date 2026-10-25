//
//  GazeMapper.swift
//  Resonance
//
//  Turns raw head (or eye) direction into a point on the screen (PLAN.pdf Section 13).
//  During calibration the user looks at 5 dots. We fit a straight-line mapping
//    screenX = ax * u + bx * v + cx
//    screenY = ay * u + by * v + cy
//  with least squares, then smooth the pointer so it doesn't jitter.
//

import Foundation
import CoreGraphics

struct GazeMapper: Codable, Equatable {
    var ax: Double, bx: Double, cx: Double
    var ay: Double, by: Double, cy: Double

    func map(_ raw: CGPoint) -> CGPoint {
        let u = Double(raw.x), v = Double(raw.y)
        return CGPoint(x: ax * u + bx * v + cx, y: ay * u + by * v + cy)
    }

    /// Fits the mapping from at least 3 calibration pairs. Returns nil if the points
    /// don't spread out enough to solve (for example, the head didn't move).
    /// Smallest head movement (in raw units) across the calibration dots.
    static let minSpread: CGFloat = 0.05

    static func fit(raw: [CGPoint], screen: [CGPoint]) -> GazeMapper? {
        guard raw.count == screen.count, raw.count >= 3 else { return nil }
        // The head must actually move during calibration; otherwise the fit is meaningless.
        let xs = raw.map(\.x), ys = raw.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max(),
              maxX - minX >= minSpread, maxY - minY >= minSpread else { return nil }

        // Normal equations: M * [a, b, c] = r, where M = sum of [u v 1]^T [u v 1].
        var m = [[Double]](repeating: [0, 0, 0], count: 3)
        var rx = [0.0, 0.0, 0.0], ry = [0.0, 0.0, 0.0]
        for (p, s) in zip(raw, screen) {
            let row = [Double(p.x), Double(p.y), 1.0]
            for i in 0..<3 {
                for j in 0..<3 { m[i][j] += row[i] * row[j] }
                rx[i] += row[i] * Double(s.x)
                ry[i] += row[i] * Double(s.y)
            }
        }
        guard let solX = solve3(m, rx), let solY = solve3(m, ry) else { return nil }
        return GazeMapper(ax: solX[0], bx: solX[1], cx: solX[2], ay: solY[0], by: solY[1], cy: solY[2])
    }

    /// Solves a 3x3 linear system with Cramer's rule.
    static func solve3(_ m: [[Double]], _ r: [Double]) -> [Double]? {
        func det(_ a: [[Double]]) -> Double {
            a[0][0] * (a[1][1] * a[2][2] - a[1][2] * a[2][1])
            - a[0][1] * (a[1][0] * a[2][2] - a[1][2] * a[2][0])
            + a[0][2] * (a[1][0] * a[2][1] - a[1][1] * a[2][0])
        }
        let d = det(m)
        guard abs(d) > 1e-12 else { return nil }
        var result = [0.0, 0.0, 0.0]
        for col in 0..<3 {
            var replaced = m
            for row in 0..<3 { replaced[row][col] = r[row] }
            result[col] = det(replaced) / d
        }
        return result
    }

    // MARK: Saving between launches

    private static let storageKey = "gazeMapper"

    static func load() -> GazeMapper? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(GazeMapper.self, from: data)
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}

/// Exponential smoothing: new = 0.25 * raw + 0.75 * previous.
struct PointerSmoother {
    var alpha: CGFloat = 0.25
    private(set) var current: CGPoint?

    mutating func add(_ p: CGPoint) -> CGPoint {
        guard let prev = current else { current = p; return p }
        let next = CGPoint(x: alpha * p.x + (1 - alpha) * prev.x,
                           y: alpha * p.y + (1 - alpha) * prev.y)
        current = next
        return next
    }

    mutating func reset() { current = nil }
}
