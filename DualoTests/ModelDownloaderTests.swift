//
//  ModelDownloaderTests.swift
//  DualoTests
//
//  The parts of model downloads that don't need the network: remembering where a
//  stopped download got to, telling a relaunched app's downloads apart, and what the
//  user is told when one fails.
//

import Foundation
import Testing
@testable import Dualo

struct ResumeDataStoreTests {
    private let store = ResumeDataStore(directory: FileManager.default.temporaryDirectory
        .appendingPathComponent("ResumeDataStoreTests-\(UUID().uuidString)", isDirectory: true))

    @Test func keepsWhatEachModelGotUntilItsRemoved() {
        store.save(Data("first".utf8), for: "qwen")
        store.save(Data("second".utf8), for: "phi")

        #expect(store.load(for: "qwen") == Data("first".utf8))
        #expect(store.load(for: "phi") == Data("second".utf8))

        store.remove(for: "qwen")
        #expect(store.load(for: "qwen") == nil)
        #expect(store.load(for: "phi") != nil)
    }

    @Test func savingAgainReplacesTheOldData() {
        store.save(Data("old".utf8), for: "qwen")
        store.save(Data("new".utf8), for: "qwen")
        #expect(store.load(for: "qwen") == Data("new".utf8))
    }

    @Test func modelIdsWithSlashesStayInTheDirectory() {
        store.save(Data("data".utf8), for: "org/model")
        #expect(store.load(for: "org/model") == Data("data".utf8))
    }
}

struct DownloadTagTests {
    @Test func survivesTheTaskDescription() {
        let tag = DownloadTag(modelId: "Qwen3.5-0.8B-Q4_K_M", destinationPath: "/var/Models/Qwen3.5-0.8B-Q4_K_M.gguf")
        #expect(DownloadTag(tag.encoded) == tag)
    }

    @Test func ignoresTasksItDidntTag() {
        #expect(DownloadTag(nil) == nil)
        #expect(DownloadTag("something else") == nil)
    }
}

struct DownloadFailureMessageTests {
    @Test func lostConnectionSaysItCanContinue() {
        let message = ModelDownloader.failureMessage(for: URLError(.networkConnectionLost), canResume: true)
        #expect(message == "The connection was lost. Try again to pick up where it left off.")
    }

    @Test func doesntPromiseToContinueWithoutResumeData() {
        let message = ModelDownloader.failureMessage(for: URLError(.notConnectedToInternet), canResume: false)
        #expect(message == "The connection was lost.")
    }

    @Test func closingTheAppPausesTheDownload() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled, userInfo: [
            NSURLErrorBackgroundTaskCancelledReasonKey: NSURLErrorCancelledReasonUserForceQuitApplication
        ])
        let message = ModelDownloader.failureMessage(for: error, canResume: true)
        #expect(message == "The download paused when Dualo was closed. Try again to pick up where it left off.")
    }

    @Test func serverErrorsKeepTheirReason() {
        let error = LocalModelError.downloadFailed("The server returned an error (404).")
        #expect(ModelDownloader.failureMessage(for: error, canResume: false) == "The server returned an error (404).")
    }
}
