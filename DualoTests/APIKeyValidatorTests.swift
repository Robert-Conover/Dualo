//
//  APIKeyValidatorTests.swift
//  DualoTests
//

import Testing
@testable import Dualo

struct APIKeyValidatorTests {

    /// Long enough to pass the length check.
    private let validKey = "sk-" + String(repeating: "a", count: 40)

    @Test func emptyKeyIsValid() {
        #expect(APIKeyValidator.validationError(for: "") == nil)
        #expect(APIKeyValidator.validationError(for: "  \n") == nil)
    }

    @Test func wellFormedKeyIsValid() {
        #expect(APIKeyValidator.validationError(for: validKey) == nil)
    }

    @Test func surroundingWhitespaceIsIgnored() {
        #expect(APIKeyValidator.validationError(for: "  \(validKey)\n") == nil)
    }

    @Test func wrongPrefixIsRejected() {
        let error = APIKeyValidator.validationError(for: "pk-" + String(repeating: "a", count: 40))
        #expect(error?.contains("sk-") == true)
    }

    @Test func shortKeyIsRejected() {
        let error = APIKeyValidator.validationError(for: "sk-123")
        #expect(error?.contains("too short") == true)
    }

    @Test func lengthCheckCanBeDeferredWhileTyping() {
        #expect(APIKeyValidator.validationError(for: "sk-123", checkLength: false) == nil)
    }

    @Test func prefixIsCheckedEvenWhileTyping() {
        #expect(APIKeyValidator.validationError(for: "abc", checkLength: false) != nil)
    }

    @Test func minimumLengthBoundary() {
        let minLength = AppConstants.Security.openaiKeyMinLength
        let atMinimum = "sk-" + String(repeating: "a", count: minLength - 3)
        let belowMinimum = String(atMinimum.dropLast())

        #expect(APIKeyValidator.validationError(for: atMinimum) == nil)
        #expect(APIKeyValidator.validationError(for: belowMinimum) != nil)
    }

    @Test func normalizedTrimsWhitespaceAndNewlines() {
        #expect(APIKeyValidator.normalized(" \(validKey)\n") == validKey)
    }
}
