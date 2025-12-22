//
//  HTTPErrorHandler.swift
//  Dualo
//
//  Created by Robert Conover on 8/11/25.
//

import Foundation

/// Centralized HTTP error handling for API requests
struct HTTPErrorHandler {

    /// API provider type for error message parsing
    enum Provider {
        case anthropic
        case openai
    }

    /// Handles HTTP response errors and throws appropriate NetworkError
    ///
    /// - Parameters:
    ///   - response: The HTTP response from the API request
    ///   - data: The response data that may contain error details
    ///   - provider: The API provider for parsing provider-specific error formats
    /// - Throws: NetworkError with appropriate error type and detailed message
    static func handleResponse(_ response: HTTPURLResponse, data: Data, provider: Provider) throws {
        // Handle specific HTTP status codes
        if response.statusCode == 401 {
            throw NetworkError.invalidAPIKey
        } else if response.statusCode == 429 {
            throw NetworkError.rateLimitExceeded
        } else if response.statusCode >= 400 {
            // Attempt to parse provider-specific error details
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorData["error"] as? [String: Any] {

                let message = error["message"] as? String ?? "Unknown error"
                var detailedMessage = message

                // Add error type if available
                if let type = error["type"] as? String {
                    detailedMessage += " (Type: \(type))"
                }

                // Add error code for OpenAI (not present in Anthropic responses)
                if provider == .openai, let code = error["code"] as? String {
                    detailedMessage += " (Code: \(code))"
                }

                throw NetworkError.serverError(detailedMessage)
            }

            // Fallback to generic HTTP error if no provider error details found
            throw NetworkError.serverError("HTTP \(response.statusCode)")
        }
    }
}
