//
//  StreamingThrottleTests.swift
//  DualoTests
//

import Foundation
import Testing
@testable import Dualo

struct StreamingThrottleTests {

    private let start = Date(timeIntervalSinceReferenceDate: 1_000)

    private func at(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }

    @Test func firstChunkPersistsAndUpdatesUI() {
        var throttle = StreamingThrottle()
        #expect(throttle.check(length: 5, at: start) == .init(persist: true, updateUI: true))
    }

    @Test func quickSmallChunksAreHeldBack() {
        var throttle = StreamingThrottle()
        _ = throttle.check(length: 5, at: start)
        #expect(throttle.check(length: 20, at: at(0.01)) == .init(persist: false, updateUI: false))
    }

    @Test func uiUpdatesAfterItsIntervalWithoutPersisting() {
        var throttle = StreamingThrottle()
        _ = throttle.check(length: 5, at: start)
        let decision = throttle.check(length: 20, at: at(AppConstants.UI.streamingUIUpdateInterval + 0.001))
        #expect(decision == .init(persist: false, updateUI: true))
    }

    @Test func persistsAfterItsInterval() {
        var throttle = StreamingThrottle()
        _ = throttle.check(length: 5, at: start)
        let decision = throttle.check(length: 20, at: at(AppConstants.UI.streamingPersistInterval + 0.001))
        #expect(decision.persist)
    }

    @Test func persistsOnceEnoughNewCharactersArrive() {
        var throttle = StreamingThrottle()
        _ = throttle.check(length: 5, at: start)
        let threshold = AppConstants.UI.streamingPersistCharThreshold
        #expect(throttle.check(length: 5 + threshold - 1, at: at(0.01)).persist == false)
        #expect(throttle.check(length: 5 + threshold, at: at(0.02)).persist)
    }

    @Test func charThresholdCountsFromLastPersist() {
        var throttle = StreamingThrottle()
        let threshold = AppConstants.UI.streamingPersistCharThreshold
        _ = throttle.check(length: 0, at: start)
        _ = throttle.check(length: threshold, at: at(0.01)) // persists
        #expect(throttle.check(length: threshold + 1, at: at(0.02)).persist == false)
    }

    @Test func forceAlwaysPersistsAndUpdates() {
        var throttle = StreamingThrottle()
        _ = throttle.check(length: 5, at: start)
        #expect(throttle.check(length: 6, at: start, force: true) == .init(persist: true, updateUI: true))
    }
}
