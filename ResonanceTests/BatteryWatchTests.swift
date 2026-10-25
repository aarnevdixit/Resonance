//
//  BatteryWatchTests.swift
//  ResonanceTests
//
//  When the Talk board warns about a low battery.
//

import Testing
@testable import Resonance

struct BatteryWatchTests {
    @Test func plentyOfBatteryIsFine() {
        #expect(BatteryAdvice.advice(level: 0.8, charging: false) == .ok)
        #expect(BatteryAdvice.advice(level: 0.21, charging: false) == .ok)
    }

    @Test func lowAndCriticalLevels() {
        #expect(BatteryAdvice.advice(level: 0.2, charging: false) == .low(percent: 20))
        #expect(BatteryAdvice.advice(level: 0.15, charging: false) == .low(percent: 15))
        #expect(BatteryAdvice.advice(level: 0.1, charging: false) == .critical(percent: 10))
        #expect(BatteryAdvice.advice(level: 0.03, charging: false) == .critical(percent: 3))
    }

    @Test func chargingOrUnknownNeverWarns() {
        #expect(BatteryAdvice.advice(level: 0.05, charging: true) == .ok)
        #expect(BatteryAdvice.advice(level: -1, charging: false) == .ok)   // Simulator
    }

    @Test func messagesNameThePercent() {
        #expect(BatteryAdvice.ok.message == nil)
        #expect(BatteryAdvice.low(percent: 18).message?.contains("18%") == true)
        #expect(BatteryAdvice.critical(percent: 7).message == "Battery 7%. Please plug in now.")
    }
}
