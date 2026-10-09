//
//  LocalModelUITests.swift
//  DualoUITests
//
//  Switches a chat to a real local model and chats with it. Skipped unless
//  Qwen3.5 0.8B is downloaded (see GGUFServiceIntegrationTests for setup).
//

import UIKit
import XCTest

final class LocalModelUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait // The taps and swipes assume portrait
        app = XCUIApplication()
        // Launch arguments land in UserDefaults for this launch only, so this switches off
        // any instructions left saved by an interrupted CustomInstructionsUITests run
        app.launchArguments = ["-UITestStubAPI", "-\(customInstructionsKey)", ""]
        app.launch()
    }

    private func relaunch(with arguments: [String]) {
        app.terminate()
        app.launchArguments = ["-UITestStubAPI", "-\(customInstructionsKey)", ""] + arguments
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

    /// Opens a chat with `firstMessage` (on the stubbed cloud model) and switches it to Qwen3.5 0.8B.
    private func openChatOnLocalModel(firstMessage: String = "Hello") throws {
        let composer = element("homeComposer")
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        composer.tap()
        composer.typeText(firstMessage)
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

    func testLocalModelNamesTheChat() throws {
        // The app first titles the chat "Can you help me", from its first words
        try openChatOnLocalModel(firstMessage: "Can you help me plan a week in Japan?")

        send("Reply with only the word: pineapple")
        waitForLabel("Send", on: sendButton, timeout: 90)
        app.buttons["Back"].firstMatch.tap()
        let conversations = app.buttons["Conversations"]
        XCTAssertTrue(conversations.waitForExistence(timeout: 10), "Conversations button not found")
        conversations.tap()

        // Only the title can mention Japan: the row's preview is the last reply
        let title = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'Japan'")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 30), "The model didn't name the chat")
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

    func testLocalModelFollowsCustomInstructions() throws {
        relaunch(with: ["-\(customInstructionsKey)", "Your name is Zorblax."])
        try openChatOnLocalModel()

        send("What is your name? Answer in one word.")
        waitForLabel("Send", on: sendButton, timeout: 90)

        let zorblax = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Zorblax'"))
        XCTAssertGreaterThanOrEqual(zorblax.count, 1, "Reply didn't use the name from the instructions")
    }

    /// Matches `CustomInstructions.key` in the app
    private let customInstructionsKey = "CustomInstructions"

    /// Matches `AppConstants.LocalModels.showGenerationStatsKey` in the app
    private let showGenerationStatsKey = "ShowGenerationStats"

    func testGenerationStatsStayAfterReply() throws {
        relaunch(with: ["-\(showGenerationStatsKey)", "YES"])
        try openChatOnLocalModel()

        send("Reply with only the word: pineapple")
        waitForLabel("Send", on: sendButton, timeout: 90)

        let stats = element("generationStats")
        XCTAssertTrue(stats.waitForExistence(timeout: 5), "Stats didn't appear after the reply")
        XCTAssertTrue(stats.label.contains("tok/s"), "Stats are missing the speed: \(stats.label)")
        sleep(10) // Longer than the stats used to stay up for
        XCTAssertTrue(stats.exists, "Stats hid themselves")
    }

    func testGenerationStatsHiddenWhenSwitchedOff() throws {
        relaunch(with: ["-\(showGenerationStatsKey)", "NO"])
        try openChatOnLocalModel()

        send("Reply with only the word: pineapple")
        // The live counter would show while the reply streams
        waitForLabel("Stop", on: sendButton, timeout: 10)
        XCTAssertFalse(element("generationStats").exists)
        XCTAssertFalse(app.staticTexts["tokens"].exists, "Live token counter showed while switched off")
        waitForLabel("Send", on: sendButton, timeout: 90)

        sleep(2)
        XCTAssertFalse(element("generationStats").exists, "Stats showed while switched off")
    }

    func testLongChatShowsWhereTheModelsMemoryStarts() throws {
        // The generation stats would take the context pill's place
        relaunch(with: ["-\(showGenerationStatsKey)", "NO"])
        try openChatOnLocalModel()

        // About 3,200 tokens: too long for the model to also fit the "Hello" it started with,
        // short enough to leave room for a reply. Typing it would take minutes, so it's pasted.
        let note = String(repeating: "The tide came in slowly over the grey stones near the old pier. ", count: 230)
        UIPasteboard.general.string = note + "Just say OK."
        let composer = element("chatComposer")
        composer.tap()
        composer.press(forDuration: 1.2)
        let paste = app.menuItems["Paste"].exists ? app.menuItems["Paste"] : app.buttons["Paste"]
        XCTAssertTrue(paste.waitForExistence(timeout: 5), "Paste option didn't appear")
        paste.tap()
        sendButton.tap()
        waitForLabel("Send", on: sendButton, timeout: 300)

        let divider = element("modelMemoryDivider")
        XCTAssertTrue(divider.waitForExistence(timeout: 10), "No divider where the model's memory starts")
        sleep(1) // Let the list scroll to it
        XCTAssertLessThanOrEqual(divider.frame.maxY, element("chatComposer").frame.minY,
                                 "Divider is hidden behind the composer")
        XCTAssertTrue(element("contextUsage").label.contains("Forgetting oldest"),
                      "Context pill doesn't say messages are being forgotten: \(element("contextUsage").label)")
        XCTAssertFalse(app.alerts.firstMatch.exists, "An error alert appeared")
    }

    func testLocalModelChatHasNoAttachButton() throws {
        try openChatOnLocalModel()

        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element("chatAttachButton"))
        wait(for: [gone], timeout: 5)
    }
}
