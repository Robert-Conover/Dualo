//
//  KeychainQueryBuilder.swift
//  Dualo
//
//  Centralized Keychain query construction to eliminate duplicate code.
//

import Foundation
import Security

/// Builder for creating Keychain query dictionaries
struct KeychainQueryBuilder {
    private let service: String

    init(service: String) {
        self.service = service
    }

    /// Create a base query for a specific account
    func baseQuery(for account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    /// Create a query for saving data
    func saveQuery(for account: String, data: Data) -> [String: Any] {
        var query = baseQuery(for: account)
        query[kSecValueData as String] = data
        return query
    }

    /// Create a query for loading data
    func loadQuery(for account: String) -> [String: Any] {
        var query = baseQuery(for: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return query
    }

    /// Create a query for deleting an item
    func deleteQuery(for account: String) -> [String: Any] {
        baseQuery(for: account)
    }
}
