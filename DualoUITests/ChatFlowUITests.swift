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
        XCUIDevice.shared.orientation = .portrait // The taps and swipes assume portrait
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

    private var stubReplies: XCUIElementQuery {
        app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'STUB-END'"))
    }

    func testEditingLastMessageReplacesItAndItsReply() {
        startChat(with: "Original question")
        waitForReplyToFinish()

        // Cancelling leaves the chat as it was
        text(containing: "Original question").press(forDuration: 1)
        app.buttons["Edit"].tap()
        let composer = element("chatComposer")
        XCTAssertEqual(composer.value as? String, "Original question")
        element("cancelEditingButton").tap()
        XCTAssertFalse(app.staticTexts["Editing message"].waitForExistence(timeout: 2))
        XCTAssertNotEqual(composer.value as? String, "Original question")

        text(containing: "Original question").press(forDuration: 1)
        app.buttons["Edit"].tap()
        XCTAssertTrue(app.staticTexts["Editing message"].waitForExistence(timeout: 5))
        composer.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "question".count) + "answer")
        element("chatSendButton").tap()

        XCTAssertTrue(text(containing: "Original answer").waitForExistence(timeout: 5), "Edited message missing")
        waitForReplyToFinish()
        XCTAssertFalse(text(containing: "Original question").exists, "Original message wasn't replaced")
        XCTAssertEqual(stubReplies.count, 1, "Original reply wasn't replaced")
    }

    func testRegeneratingLastReply() {
        startChat(with: "Tell me something")
        waitForReplyToFinish()

        element("regenerateButton").tap()
        XCTAssertTrue(text(containing: "Take 2.").waitForExistence(timeout: 10), "Reply wasn't regenerated")
        waitForReplyToFinish()
        XCTAssertEqual(stubReplies.count, 1, "Old reply is still there")
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

    func testSearchFindsEarlierMessagesInAChat() {
        // The title is the first four words, so "zebracorn" is only findable in the message
        startChat(with: "Tell me about the zebracorn please")
        waitForReplyToFinish()
        app.buttons["Back"].firstMatch.tap()

        let conversations = app.buttons["Conversations"]
        XCTAssertTrue(conversations.waitForExistence(timeout: 10), "Conversations button not found")
        conversations.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), "Search field not found")
        search.tap()
        search.typeText("Zebracorn")

        let snippet = element("conversationSearchSnippet")
        XCTAssertTrue(snippet.waitForExistence(timeout: 5), "No search result with a snippet")
        XCTAssertTrue(snippet.label.contains("zebracorn"), "Snippet: \(snippet.label)")

        search.typeText("xyz")
        XCTAssertTrue(text(containing: "No Results").waitForExistence(timeout: 5), "No-results message missing")
    }

    func testPinnedChatsStayAboveRecentsAndPersistAcrossLaunches() {
        let keyword = "pin-\(UUID().uuidString.prefix(8))"
        let olderTitle = "\(keyword) Older"
        let newerTitle = "\(keyword) Newer"

        startChat(with: olderTitle)
        waitForReplyToFinish()
        app.buttons["Back"].firstMatch.tap()
        startChat(with: newerTitle)
        waitForReplyToFinish()
        app.buttons["Back"].firstMatch.tap()

        func showMatchingChats() {
            let conversations = app.buttons["Conversations"]
            XCTAssertTrue(conversations.waitForExistence(timeout: 10))
            conversations.tap()
            let search = app.searchFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 5))
            search.tap()
            search.typeText(keyword)
        }

        func row(_ title: String) -> XCUIElement {
            app.buttons.matching(NSPredicate(
                format: "identifier BEGINSWITH 'conversationRow-' AND label CONTAINS %@", title
            )).firstMatch
        }

        showMatchingChats()
        let older = row(olderTitle)
        let newer = row(newerTitle)
        XCTAssertTrue(older.waitForExistence(timeout: 5))
        XCTAssertTrue(newer.exists)
        XCTAssertLessThan(newer.frame.minY, older.frame.minY)

        older.press(forDuration: 1)
        app.buttons["Pin"].tap()
        let pinned = NSPredicate(format: "value == 'Pinned'")
        expectation(for: pinned, evaluatedWith: older)
        waitForExpectations(timeout: 5)
        XCTAssertLessThan(older.frame.minY, newer.frame.minY, "Pinned chat didn't move above newer chats")

        app.terminate()
        app.launch()
        showMatchingChats()
        XCTAssertTrue(older.waitForExistence(timeout: 5))
        XCTAssertEqual(older.value as? String, "Pinned", "Pin wasn't saved")
        XCTAssertLessThan(older.frame.minY, newer.frame.minY)

        // A partial right swipe exposes the leading action without invoking a full swipe.
        older.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: older.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        let unpin = app.buttons["Unpin"]
        XCTAssertTrue(unpin.waitForExistence(timeout: 5))
        unpin.tap()
        let unpinned = NSPredicate(format: "value != 'Pinned'")
        expectation(for: unpinned, evaluatedWith: older)
        waitForExpectations(timeout: 5)
        XCTAssertLessThan(newer.frame.minY, older.frame.minY, "Unpinning changed the chat's recency")

        app.terminate()
        app.launch()
        showMatchingChats()
        XCTAssertTrue(older.waitForExistence(timeout: 5))
        XCTAssertNotEqual(older.value as? String, "Pinned", "Unpin wasn't saved")
        XCTAssertLessThan(newer.frame.minY, older.frame.minY)
    }

    func testFirstCloudMessageAsksBeforeSendingToOpenAI() {
        app.terminate()
        app.launchArguments.append("-UITestAskCloudConsent")
        app.launch()

        startChat(with: "Hello cloud")
        let allow = element("cloudConsentAllowButton")
        let decline = element("cloudConsentDeclineButton")
        XCTAssertTrue(decline.waitForExistence(timeout: 5), "Didn't ask before sending to OpenAI")

        decline.tap()
        let retry = text(containing: "Tap to retry")
        XCTAssertTrue(retry.waitForExistence(timeout: 5), "Declined message should stay, unsent")
        XCTAssertFalse(stubEnd.exists, "Message was sent without permission")

        retry.tap()
        XCTAssertTrue(allow.waitForExistence(timeout: 5), "Retrying didn't ask again")
        allow.tap()
        waitForReplyToFinish()

        sendInChat("Second message")
        XCTAssertFalse(allow.waitForExistence(timeout: 2), "Asked again after being allowed")
    }

    func testDictatedMessageCanBeSent() {
        // Under -UITestStubAPI, dictation "hears" StubVoiceTranscriber.phrase
        let mic = element("homeMicButton")
        XCTAssertTrue(mic.waitForExistence(timeout: 10), "Mic button not found")
        mic.tap()

        let composer = element("homeComposer")
        let heard = NSPredicate(format: "value == %@", "Hello from voice input")
        expectation(for: heard, evaluatedWith: composer)
        waitForExpectations(timeout: 5)

        mic.tap() // Stop: the final result adds punctuation
        let final = NSPredicate(format: "value == %@", "Hello from voice input.")
        expectation(for: final, evaluatedWith: composer)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(mic.label, "Dictate", "Mic didn't return to idle")

        element("homeSendButton").tap()
        XCTAssertTrue(text(containing: "Hello from voice input.").waitForExistence(timeout: 10), "Dictated message wasn't sent")
        waitForReplyToFinish()
        XCTAssertTrue(element("chatMicButton").exists, "Chat mic button missing")
    }

    func testCloudModelChatOffersImageAttachments() {
        XCTAssertTrue(element("homeAttachButton").waitForExistence(timeout: 10), "Home attach button missing")
        assertAttachmentChoicesOpenNear(element("homeAttachButton"))
        startChat(with: "Hello")
        waitForReplyToFinish()
        XCTAssertTrue(element("chatAttachButton").exists, "Chat attach button missing")
        assertAttachmentChoicesOpenNear(element("chatAttachButton"))
    }

    /// The choices used to open in a popover at the top of the screen, far from the button
    private func assertAttachmentChoicesOpenNear(_ button: XCUIElement) {
        button.tap()
        let library = app.buttons["Photo Library"]
        XCTAssertTrue(library.waitForExistence(timeout: 5), "Attachment choices didn't open")
        XCTAssertTrue(app.buttons["Take Photo"].exists)
        XCTAssertLessThan(abs(library.frame.midY - button.frame.midY), 250,
                          "Choices opened at y \(library.frame.midY), far from the button at y \(button.frame.midY)")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap() // Close the menu
        XCTAssertTrue(library.waitForNonExistence(timeout: 5))
    }
}
