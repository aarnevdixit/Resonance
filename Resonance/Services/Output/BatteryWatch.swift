//
//  BatteryWatch.swift
//  Resonance
//
//  For someone who talks through their iPhone, a flat battery means losing their voice.
//  The Talk board shows a calm warning when the battery runs low (and isn't charging),
//  with one button that asks the people nearby to plug the phone in.
//  The rules are plain Swift, unit tested in BatteryWatchTests.
//

import Foundation
import UIKit

enum BatteryAdvice: Equatable {
    case ok
    case low(percent: Int)
    case critical(percent: Int)

    static let lowLevel: Float = 0.20
    static let criticalLevel: Float = 0.10

    /// `level` is 0...1, or negative when unknown (for example in the Simulator).
    static func advice(level: Float, charging: Bool) -> BatteryAdvice {
        guard level >= 0, !charging else { return .ok }
        let percent = Int((level * 100).rounded())
        if level <= criticalLevel { return .critical(percent: percent) }
        if level <= lowLevel { return .low(percent: percent) }
        return .ok
    }

    var isWarning: Bool { self != .ok }

    /// Short text for the banner.
    var message: String? {
        switch self {
        case .ok: return nil
        case .low(let p): return "Battery \(p)%. Plug in soon so you can keep talking."
        case .critical(let p): return "Battery \(p)%. Please plug in now."
        }
    }

    /// What the button says out loud to the people nearby.
    static let spokenRequest = "My phone battery is low. Please plug it in for me."
}

/// Watches the iPhone battery. Only the Talk board uses it, while it is on screen.
@Observable
@MainActor
final class BatteryMonitor {
    private(set) var advice: BatteryAdvice = .ok
    private var observers: [NSObjectProtocol] = []

    func start() {
        guard observers.isEmpty else { return }
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        let center = NotificationCenter.default
        for name in [UIDevice.batteryLevelDidChangeNotification, UIDevice.batteryStateDidChangeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        refresh()
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        UIDevice.current.isBatteryMonitoringEnabled = false
    }

    private func refresh() {
        let device = UIDevice.current
        let charging = device.batteryState == .charging || device.batteryState == .full
        let next = BatteryAdvice.advice(level: device.batteryLevel, charging: charging)
        if next != advice { advice = next }
    }
}
