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
