//
//  SettingsUITests.swift
//  DualoUITests
//
//  Settings that aren't covered elsewhere. LocalModelUITests checks what the
//  generation stats toggle does in a chat.
//

import XCTest

final class SettingsUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait // The taps and swipes assume portrait
        app = XCUIApplication()
        app.launchArguments = ["-UITestStubAPI"]
        app.launch()
    }

    override func tearDownWithError() throws {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testGenerationStatsToggleRemembersItsSetting() throws {
        openSettings()
        let toggle = app.switches["generationStatsToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "Generation Stats toggle not found")
        let original = toggle.value as? String
        defer { setToggle(to: original) } // Leave the setting as the tests found it

        toggle.switches.firstMatch.tap()
        let flipped = toggle.value as? String
        XCTAssertNotEqual(flipped, original, "Toggle didn't switch")

        app.terminate()
        app.launch()
        openSettings()
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, flipped, "Setting wasn't saved")
    }

    func testPrivacyPolicyOpensFromSettings() {
        openSettings()
        let row = app.buttons["privacyPolicyRow"]
        XCTAssertTrue(app.switches["generationStatsToggle"].waitForExistence(timeout: 5), "Settings didn't open")
        // The About section is at the bottom of Settings
        for _ in 0..<5 where !row.isHittable {
            app.swipeUp()
        }
        row.tap()
        XCTAssertTrue(app.navigationBars["Privacy Policy"].waitForExistence(timeout: 5), "Privacy policy didn't open")
        XCTAssertTrue(app.staticTexts["The short version"].exists, "Policy text missing")
    }

    func testSendingToOpenAICanBeSwitchedOff() {
        // Stubbed launches start with sending to OpenAI allowed
        openSettings()
        let toggle = app.switches["cloudConsentToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "Send Chats to OpenAI toggle not found")
        for _ in 0..<5 where !toggle.isHittable {
            app.swipeUp()
        }
        XCTAssertEqual(toggle.value as? String, "1")

        toggle.switches.firstMatch.tap()
        expectation(for: NSPredicate(format: "value == '0'"), evaluatedWith: toggle)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(app.staticTexts["Asks before the first message"].exists)
    }

    private func openSettings() {
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10), "Settings button not found")
        settings.tap()
    }

    private func setToggle(to value: String?) {
        let toggle = app.switches["generationStatsToggle"]
        if toggle.value as? String != value {
            toggle.switches.firstMatch.tap()
        }
    }
}
