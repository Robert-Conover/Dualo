//
//  NetworkError.swift
//  Dualo
//
//  Created by Robert Conover on 8/11/25.
//

import Foundation

enum NetworkError: LocalizedError {
    case invalidURL
    case invalidAPIKey
    case invalidResponse
    case invalidRequest(String)
    case decodingError
    case serverError(String)
    case rateLimitExceeded
    case quotaExceeded
    case networkUnavailable
    case unknown(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .invalidAPIKey:
            return "Invalid or missing API key"
        case .invalidResponse:
            return "Invalid response from server"
        case .invalidRequest(let message):
            return "Invalid request: \(message)"
        case .decodingError:
            return "Failed to decode response"
        case .serverError(let message):
            return "Server error: \(message)"
        case .rateLimitExceeded:
            return "Rate limit exceeded. Please try again later."
        case .quotaExceeded:
            return "API quota exceeded"
        case .networkUnavailable:
            return "Network connection unavailable"
        case .unknown(let error):
            return "An unknown error occurred: \(error.localizedDescription)"
        }
    }
}