//
//  HTTPErrorHandlerTests.swift
//  DualoTests
//

import Foundation
import Testing
@testable import Dualo

struct HTTPErrorHandlerTests {

    private func response(_ statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/models")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
    }

    private func errorBody(message: String, type: String? = nil, code: String? = nil) -> Data {
        var error: [String: Any] = ["message": message]
        error["type"] = type
        error["code"] = code
        return try! JSONSerialization.data(withJSONObject: ["error": error])
    }

    @Test(arguments: [200, 201, 204, 302])
    func nonErrorStatusDoesNotThrow(statusCode: Int) throws {
        try HTTPErrorHandler.handleResponse(response(statusCode), data: Data())
    }

    @Test func unauthorizedMapsToInvalidAPIKey() {
        let error = #expect(throws: NetworkError.self) {
            try HTTPErrorHandler.handleResponse(response(401), data: Data())
        }
        guard case .invalidAPIKey? = error else {
            Issue.record("Expected .invalidAPIKey, got \(String(describing: error))")
            return
        }
    }

    @Test func insufficientQuotaMapsToQuotaExceeded() {
        let body = errorBody(
            message: "You exceeded your current quota, please check your plan and billing details.",
            type: "insufficient_quota",
            code: "insufficient_quota"
        )
        let error = #expect(throws: NetworkError.self) {
            try HTTPErrorHandler.handleResponse(response(429), data: body)
        }
        guard case .quotaExceeded? = error else {
            Issue.record("Expected .quotaExceeded, got \(String(describing: error))")
            return
        }
    }

    @Test func ordinaryRateLimitMapsToRateLimitExceeded() {
        let body = errorBody(message: "Rate limit reached", type: "requests", code: "rate_limit_exceeded")
        let error = #expect(throws: NetworkError.self) {
            try HTTPErrorHandler.handleResponse(response(429), data: body)
        }
        guard case .rateLimitExceeded? = error else {
            Issue.record("Expected .rateLimitExceeded, got \(String(describing: error))")
            return
        }
    }

    @Test(arguments: [Data(), Data("not json".utf8)])
    func rateLimitWithUnreadableBodyMapsToRateLimitExceeded(body: Data) {
        let error = #expect(throws: NetworkError.self) {
            try HTTPErrorHandler.handleResponse(response(429), data: body)
        }
        guard case .rateLimitExceeded? = error else {
            Issue.record("Expected .rateLimitExceeded, got \(String(describing: error))")
            return
        }
    }

    @Test func serverErrorIncludesProviderDetails() {
        let body = errorBody(message: "The model does not exist", type: "invalid_request_error", code: "model_not_found")
        let error = #expect(throws: NetworkError.self) {
            try HTTPErrorHandler.handleResponse(response(404), data: body)
        }
        guard case .serverError(let message)? = error else {
            Issue.record("Expected .serverError, got \(String(describing: error))")
            return
        }
        #expect(message.contains("The model does not exist"))
        #expect(message.contains("invalid_request_error"))
        #expect(message.contains("model_not_found"))
    }

    @Test func serverErrorWithoutBodyFallsBackToStatusCode() {
        let error = #expect(throws: NetworkError.self) {
            try HTTPErrorHandler.handleResponse(response(503), data: Data())
        }
        guard case .serverError(let message)? = error else {
            Issue.record("Expected .serverError, got \(String(describing: error))")
            return
        }
        #expect(message == "HTTP 503")
    }
}
