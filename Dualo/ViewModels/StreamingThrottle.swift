//
//  StreamingThrottle.swift
//  Dualo
//

import Foundation

/// Decides when a streaming reply should be saved to disk and when it should be
/// pushed to the UI, so per-token updates don't cause excessive I/O and redraws.
struct StreamingThrottle {
    struct Decision: Equatable {
        var persist: Bool
        var updateUI: Bool
    }

    var persistInterval: TimeInterval = AppConstants.UI.streamingPersistInterval
    var persistCharThreshold = AppConstants.UI.streamingPersistCharThreshold
    var uiUpdateInterval: TimeInterval = AppConstants.UI.streamingUIUpdateInterval

    private var lastPersistTime: Date = .distantPast
    private var lastPersistedLength = 0
    private var lastUIUpdateTime: Date = .distantPast

    /// Decides what to do with the reply now that it is `length` characters long,
    /// and records the decision. `force` saves and updates regardless (end of stream).
    mutating func check(length: Int, at now: Date = Date(), force: Bool = false) -> Decision {
        let persist = force
            || now.timeIntervalSince(lastPersistTime) >= persistInterval
            || length - lastPersistedLength >= persistCharThreshold
        if persist {
            lastPersistTime = now
            lastPersistedLength = length
        }

        let updateUI = force || now.timeIntervalSince(lastUIUpdateTime) >= uiUpdateInterval
        if updateUI {
            lastUIUpdateTime = now
        }

        return Decision(persist: persist, updateUI: updateUI)
    }
}
