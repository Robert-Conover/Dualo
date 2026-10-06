//
//  ChatFlowUITests.swift
//  DualoUITests
//
//  Drives the chat screen against the app's StubAPIService (see UITestSupport),
//  so sending, stopping, retrying and the toolbar menus run without an API key.
//

import XCTest

final class ChatFlowUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITestStubAPI"]
        app.launch()
    }

    override func tearDownWithError() throws {
        // Keep a screenshot of the final state with every run
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - Helpers

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private func text(containing substring: String) -> XCUIElement {
        app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", substring)).firstMatch
    }

    private var stubEnd: XCUIElement { text(containing: "STUB-END") }

    /// Sends a first message from the home screen, which opens a new chat.
    private func startChat(with message: String) {
        let composer = element("homeComposer")
        XCTAssertTrue(composer.waitForExistence(timeout: 10), "Home composer not found")
        composer.tap()
        composer.typeText(message)
        element("homeSendButton").tap()
        XCTAssertTrue(element("chatSendButton").waitForExistence(timeout: 10), "Chat screen did not open")
    }

    private func sendInChat(_ message: String) {
        let composer = element("chatComposer")
        composer.tap()
        composer.typeText(message)
        element("chatSendButton").tap()
    }

    private func waitForReplyToFinish(timeout: TimeInterval = 20) {
        XCTAssertTrue(stubEnd.waitForExistence(timeout: timeout), "Stubbed reply never finished")
        let idle = NSPredicate(format: "label == %@", "Send")
        expectation(for: idle, evaluatedWith: element("chatSendButton"))
        waitForExpectations(timeout: 5)
    }

    // MARK: - Tests

    func testFirstMessageFromHomeStreamsFullReply() {
        startChat(with: "Hello there")

        XCTAssertTrue(text(containing: "Hello there").exists, "User message missing")
        XCTAssertEqual(element("chatSendButton").label, "Stop", "Should show Stop while streaming")
        waitForReplyToFinish()
        XCTAssertTrue(text(containing: "stubbed reply").exists)
        XCTAssertFalse(app.staticTexts["Sending..."].exists)
    }

    func testFollowUpMessageInSameChat() {
        startChat(with: "First")
        waitForReplyToFinish()

        sendInChat("Second")
        XCTAssertTrue(text(containing: "Second").waitForExistence(timeout: 5))
        let bothReplies = NSPredicate(format: "count == 2")
        expectation(for: bothReplies, evaluatedWith: app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'STUB-END'")))
        waitForExpectations(timeout: 20)
    }

    func testStoppingMidReplyKeepsPartialText() {
        startChat(with: "[drip] Please stop me")
        XCTAssertTrue(text(containing: "This is a").waitForExistence(timeout: 10), "Reply never started")

        let stopButton = element("chatSendButton")
        XCTAssertEqual(stopButton.label, "Stop", "Reply finished before the test could stop it")
        stopButton.tap()
        sleep(7) // The full [drip] reply would finish in this time if stop didn't work

        XCTAssertTrue(text(containing: "This is a").exists, "Partial reply was lost")
        XCTAssertFalse(stubEnd.exists, "Reply kept streaming after stop")
        XCTAssertFalse(app.staticTexts["Cancelled"].exists, "Message with partial reply shouldn't be cancelled")
        XCTAssertEqual(element("chatSendButton").label, "Send")
    }

    func testStoppingBeforeFirstWordCancelsMessage() {
        startChat(with: "[slow] hello")
        element("chatSendButton").tap() // Stop before the 3s first word

        XCTAssertTrue(app.staticTexts["Cancelled"].waitForExistence(timeout: 5), "Message not marked cancelled")
        sleep(4)
        XCTAssertFalse(text(containing: "This is a").exists, "Reply arrived after stop")
    }

    func testFailedMessageCanBeRetried() {
        startChat(with: "[fail] hello")

        // Dismiss the error alert, then retry from the bubble
        let alert = app.alerts["Error"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "Error alert not shown")
        alert.buttons["OK"].tap()

        let retry = text(containing: "Tap to retry")
        XCTAssertTrue(retry.waitForExistence(timeout: 5), "Failed state not shown")
        retry.tap()

        waitForReplyToFinish()
        XCTAssertFalse(text(containing: "Failed to send").exists)
    }

    func testScrollToBottomButtonAppearsAndWorks() {
        startChat(with: "[long] hello")
        waitForReplyToFinish(timeout: 30)
        sleep(1)
        XCTAssertTrue(stubEnd.isHittable, "Chat jumped away from the end of the reply when it finished")

        // The reply is one text element that stays partly visible, so just scroll up a few times
        for _ in 0..<3 {
            app.swipeDown()
        }

        let scrollButton = app.buttons["Scroll to bottom"]
        XCTAssertTrue(scrollButton.waitForExistence(timeout: 5), "Scroll-to-bottom button never appeared")
        scrollButton.tap()

        XCTAssertTrue(stubEnd.waitForExistence(timeout: 5))
        let hidden = NSPredicate(format: "exists == false")
        expectation(for: hidden, evaluatedWith: scrollButton)
        waitForExpectations(timeout: 5)
    }

    func testRenameChat() {
        startChat(with: "Rename me")
        waitForReplyToFinish()

        app.buttons["Options"].tap()
        app.buttons["Rename Chat"].tap()

        let alert = app.alerts["Rename Chat"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        let field = alert.textFields.firstMatch
        XCTAssertFalse((field.value as? String ?? "").isEmpty, "Rename field should start with the current title")
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 60))
        field.typeText("Renamed By UI Test")
        alert.buttons["Rename"].tap()

        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: alert)
        waitForExpectations(timeout: 5)
    }

    func testExportFormatsOpenShareSheet() {
        startChat(with: "Export me")
        waitForReplyToFinish()

        for format in ["PDF", "Markdown", "Text"] {
            app.buttons["Options"].tap()
            app.buttons["Export as \(format)"].tap()

            XCTAssertFalse(app.alerts["Export Error"].waitForExistence(timeout: 2), "Export as \(format) failed")
            let shareSheet = app.otherElements["ActivityListView"]
            XCTAssertTrue(shareSheet.waitForExistence(timeout: 10), "Share sheet didn't open for \(format)")

            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "Share sheet - \(format)"
            shot.lifetime = .keepAlways
            add(shot)

            // Dismiss the share sheet
            if app.buttons["Close"].exists {
                app.buttons["Close"].tap()
            } else {
                app.swipeDown(velocity: .fast)
            }
            let gone = NSPredicate(format: "exists == false")
            expectation(for: gone, evaluatedWith: shareSheet)
            waitForExpectations(timeout: 10)
        }
    }
}
