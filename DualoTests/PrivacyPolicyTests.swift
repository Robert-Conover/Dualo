//
//  PrivacyPolicyTests.swift
//  DualoTests
//
//  The privacy policy in Settings and the one published from site/privacy.html
//  must say the same thing. Reads the page from the repo, so it's skipped when
//  the tests run somewhere the source isn't, like a device.
//

import Foundation
import Testing
@testable import Dualo

struct PrivacyPolicyTests {
    private static let pageURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("site/privacy.html")

    private static var pageExists: Bool {
        FileManager.default.fileExists(atPath: pageURL.path)
    }

    /// The page's visible text, with tags removed and spaces collapsed
    private func pageText() throws -> String {
        let html = try String(contentsOf: Self.pageURL, encoding: .utf8)
        let withoutComments = html.replacing(#/<!--[\s\S]*?-->/#, with: "")
        let withoutTags = withoutComments.replacing(#/<[^>]+>/#, with: " ")
        return collapsed(withoutTags)
    }

    /// The text a reader sees: Markdown links reduced to their words
    private func plain(_ markdown: String) -> String {
        collapsed(markdown.replacing(#/\[([^\]]+)\]\([^)]+\)/#) { String($0.output.1) })
    }

    private func collapsed(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            // Tags removed before punctuation leave a space in front of it
            .replacing(#/ ([.,?])/#) { String($0.output.1) }
    }

    @Test(.enabled(if: pageExists))
    func websiteMatchesTheAppsPolicy() throws {
        let page = try pageText()
        #expect(page.contains("Effective \(PrivacyPolicy.effectiveDate)"))
        for section in PrivacyPolicy.sections {
            #expect(page.contains(section.title), "Website is missing the heading \"\(section.title)\"")
            for paragraph in section.paragraphs {
                let text = plain(paragraph)
                #expect(page.contains(text), "Website is missing: \(text)")
            }
        }
    }

    @Test(.enabled(if: pageExists))
    func websiteHasNoSectionsTheAppLacks() throws {
        let html = try String(contentsOf: Self.pageURL, encoding: .utf8)
        let headings = html.matches(of: #/<h2>([^<]+)<\/h2>/#).map { String($0.output.1) }
        #expect(headings == PrivacyPolicy.sections.map(\.title))
    }
}
