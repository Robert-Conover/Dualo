//
//  ChatTitleTests.swift
//  DualoTests
//
//  Tidying the titles a local model writes for its chats. GGUFServiceIntegrationTests has
//  the real model write one.
//

import Testing
@testable import Dualo

struct ChatTitleTests {
    @Test func plainTitleIsKept() {
        #expect(GGUFService.cleanTitle("Trip to Japan") == "Trip to Japan")
    }

    @Test func labelQuotesAndMarkdownAreRemoved() {
        #expect(GGUFService.cleanTitle("Title: \"Trip to Japan\"") == "Trip to Japan")
        #expect(GGUFService.cleanTitle("**Title:** Trip to Japan") == "Trip to Japan")
        #expect(GGUFService.cleanTitle("# Trip to Japan.") == "Trip to Japan")
    }

    @Test func onlyTheFirstLineIsTheTitle() {
        #expect(GGUFService.cleanTitle("\nTrip to Japan\n\nHere are some ideas for your trip.") == "Trip to Japan")
    }

    @Test func longTitleIsCutToAFewWords() {
        #expect(GGUFService.cleanTitle("A detailed seven day plan for visiting Japan in the spring") == "A detailed seven day plan for visiting Japan")
    }

    @Test func questionMarkIsKept() {
        #expect(GGUFService.cleanTitle("What Is Swift?") == "What Is Swift?")
    }

    @Test func thinkingAndEmptyOutputGiveNoTitle() {
        #expect(GGUFService.cleanTitle("<think>Hmm</think>Trip to Japan") == "Trip to Japan")
        #expect(GGUFService.cleanTitle("...") == nil)
        #expect(GGUFService.cleanTitle("  \n ") == nil)
    }
}
