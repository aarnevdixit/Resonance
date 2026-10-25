//
//  ResonanceUITests.swift
//  ResonanceUITests
//
//  One quick end-to-end check: a fresh install opens on the welcome screen, and the
//  "Get started" button leads to the "Who is using Resonance?" question.
//  (Xcode's template launch-performance tests were removed: they relaunch the app many
//  times on several simulator copies and ran the Mac out of memory.)
//

import XCTest

final class ResonanceUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testOnboardingStarts() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-didOnboard", "NO"]   // always start at onboarding
        app.launch()

        let getStarted = app.buttons["Get started"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 10))
        getStarted.tap()
        XCTAssertTrue(app.staticTexts["Who is using Resonance?"].waitForExistence(timeout: 5))
    }
}
