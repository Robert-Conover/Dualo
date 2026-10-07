//
//  LocalModelUITests.swift
//  DualoUITests
//
//  Switches a chat to a real local model and chats with it. Skipped unless
//  Qwen3.5 0.8B is downloaded (see GGUFServiceIntegrationTests for setup).
//

import XCTest

final class LocalModelUITests: XCTestCase {

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

    private var sendButton: XCUIElement { element("chatSendButton") }

    private func waitForLabel(_ label: String, on element: XCUIElement, timeout: TimeInterval) {
        expectation(for: NSPredicate(format: "label == %@", label), evaluatedWith: element)
        waitForExpectations(timeout: timeout)
    }

    private func send(_ message: String) {
        let composer = element("chatComposer")
        composer.tap()
        composer.typeText(message)
        sendButton.tap()
    }

    /// Opens a chat (on the stubbed cloud model) and switches it to Qwen3.5 0.8B.
    private func openChatOnLocalModel() throws {
        let composer = element("homeComposer")
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        composer.tap()
        composer.typeText("Hello")
        element("homeSendButton").tap()
        XCTAssertTrue(sendButton.waitForExistence(timeout: 10))
        waitForLabel("Send", on: sendButton, timeout: 20)

        app.buttons.containing(NSPredicate(format: "label CONTAINS 'GPT-6.1 Sol'")).firstMatch.tap()
        let qwen = app.buttons["Qwen3.5 0.8B"]
        guard qwen.waitForExistence(timeout: 5) else {
            throw XCTSkip("Qwen3.5 0.8B isn't downloaded")
        }
        qwen.tap()
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS 'Qwen3.5 0.8B'")).firstMatch.waitForExistence(timeout: 30),
                      "Chat didn't switch to the local model")
    }

    private var pineappleTexts: XCUIElementQuery {
        app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'pineapple'"))
    }

    func testChattingWithLocalModel() throws {
        try openChatOnLocalModel()

        send("Reply with only the word: pineapple")
        waitForLabel("Send", on: sendButton, timeout: 90)

        // One match is the question, the other the model's reply
        XCTAssertGreaterThanOrEqual(pineappleTexts.count, 2, "Local model's reply is missing")
        XCTAssertFalse(app.alerts.firstMatch.exists, "An error alert appeared")
    }

    func testStoppingLocalModelThenSendingAgain() throws {
        try openChatOnLocalModel()

        send("Write a very long story about a dragon.")
        waitForLabel("Stop", on: sendButton, timeout: 10)
        sleep(4) // Let some of the story stream in
        sendButton.tap()
        waitForLabel("Send", on: sendButton, timeout: 5)

        send("Reply with only the word: pineapple")
        waitForLabel("Send", on: sendButton, timeout: 90)
        XCTAssertGreaterThanOrEqual(pineappleTexts.count, 1, "Message after stopping never went through")
        XCTAssertFalse(app.alerts.firstMatch.exists, "An error alert appeared")
    }
}
