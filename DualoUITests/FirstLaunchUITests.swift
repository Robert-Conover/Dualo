//
//  FirstLaunchUITests.swift
//  DualoUITests
//
//  Starts the app as if freshly installed (`-UITestFirstLaunch`): no API key and no
//  downloaded model. The download only pretends, then finds Qwen3.5 0.8B already on the
//  simulator, so the tests are skipped without it (see GGUFServiceIntegrationTests).
//

import XCTest

final class FirstLaunchUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["-UITestStubAPI", "-UITestFirstLaunch", "-CustomInstructions", ""]
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

    private var downloadButton: XCUIElement { element("setupDownloadButton") }

    private func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval) {
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element)
        waitForExpectations(timeout: timeout)
    }

    /// Taps Download and waits for it to finish, skipping if the model isn't on the simulator
    private func downloadStarterModel() throws {
        XCTAssertTrue(downloadButton.waitForExistence(timeout: 10), "First launch doesn't offer the model")
        downloadButton.tap()
        XCTAssertTrue(element("setupDownloadProgress").waitForExistence(timeout: 5), "No download progress")
        waitUntilGone(element("setupDownloadProgress"), timeout: 30)
        if element("setupDownloadError").exists {
            throw XCTSkip("Qwen3.5 0.8B isn't on the simulator")
        }
    }

    func testDownloadingTheModelLetsYouChatStraightAway() throws {
        try downloadStarterModel()

        // The card gives way to the suggestions, with the model chosen and loaded
        XCTAssertTrue(app.staticTexts["Try asking"].waitForExistence(timeout: 10), "Setup card is still showing")
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS 'Qwen3.5 0.8B'")).firstMatch.waitForExistence(timeout: 10),
                      "The downloaded model isn't chosen")

        let composer = element("homeComposer")
        composer.tap()
        composer.typeText("Reply with only the word: pineapple")
        let send = element("homeSendButton")
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: send)
        waitForExpectations(timeout: 60)
        send.tap()

        let chatSend = element("chatSendButton")
        XCTAssertTrue(chatSend.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "label == 'Send'"), evaluatedWith: chatSend)
        waitForExpectations(timeout: 90)
        let pineapples = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'pineapple'"))
        XCTAssertGreaterThanOrEqual(pineapples.count, 2, "The model's reply is missing")
    }

    func testCancellingTheDownloadOffersItAgain() {
        XCTAssertTrue(downloadButton.waitForExistence(timeout: 10), "First launch doesn't offer the model")
        downloadButton.tap()
        let cancel = element("setupCancelButton")
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "No way to cancel the download")
        cancel.tap()

        XCTAssertTrue(downloadButton.waitForExistence(timeout: 5), "Download isn't offered again")
        XCTAssertFalse(app.staticTexts["Try asking"].exists, "Setup card went away without a model")
    }

    func testAPIKeyLinkOpensSettings() {
        let link = element("setupUseAPIKeyButton")
        XCTAssertTrue(link.waitForExistence(timeout: 10), "No way to use an API key instead")
        link.tap()

        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5), "Settings didn't open")
    }
}
