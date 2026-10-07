//
//  CustomInstructionsUITests.swift
//  DualoUITests
//
//  Edits custom instructions in Settings. LocalModelUITests checks that a real
//  model follows them.
//

import XCTest

final class CustomInstructionsUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITestStubAPI"]
        app.launch()
    }

    override func tearDownWithError() throws {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private var row: XCUIElement { element("customInstructionsRow") }
    private var field: XCUIElement { element("customInstructionsField") }

    private func openCustomInstructions() {
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10), "Settings button not found")
        settings.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Custom Instructions row not found")
        row.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Instructions field not found")
    }

    private func clearIfSet() {
        let clear = app.buttons["Clear Instructions"]
        if clear.exists { clear.tap() }
    }

    func testInstructionsAreSavedAcrossLaunches() {
        openCustomInstructions()
        clearIfSet()
        field.tap()
        field.typeText("Answer like a pirate.")
        app.navigationBars.buttons.element(boundBy: 0).tap() // Back to Settings

        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("Answer like a pirate."), "Row label: \(row.label)")

        app.terminate()
        app.launch()
        openCustomInstructions()
        XCTAssertEqual(field.value as? String, "Answer like a pirate.")

        app.buttons["Clear Instructions"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("Off"), "Row label: \(row.label)")
    }
}
