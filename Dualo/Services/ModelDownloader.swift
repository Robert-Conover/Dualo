//
//  ModelDownloader.swift
//  Dualo
//
//  Downloads model files in a background URLSession, so a download keeps going
//  when the user leaves Dualo and finishes even if the system closes the app: iOS
//  relaunches it in the background to hand over the file (see AppDelegate). A
//  download that fails or is cut off keeps what it got as resume data, so starting
//  it again picks up from there. LocalModelManager turns its events into model states.
//

import Foundation
import OSLog

final class ModelDownloader: NSObject, @unchecked Sendable {
    static let shared = ModelDownloader()

    static var sessionIdentifier: String {
        (Bundle.main.bundleIdentifier ?? "io.conov.Dualo") + ".modelDownloads"
    }

    enum Event {
        case progress(modelId: String, fraction: Double)
        /// The file is already at the destination it was started with
        case finished(modelId: String, file: URL)
        case failed(modelId: String, error: Error)
    }

    /// Set by AppDelegate when iOS relaunches the app for this session's events;
    /// called once they've all been handled, so iOS can suspend the app again
    @MainActor var backgroundEventsCompletionHandler: (() -> Void)?

    private let resumeData = ResumeDataStore()
    private var eventHandler: (@MainActor (Event) -> Void)?
    private var session: URLSession!

    /// Delegate calls arrive one at a time on this queue, which owns the state below
    private let delegateQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = "ModelDownloader"
        return queue
    }()
    private var finishedFiles: [Int: URL] = [:]
    private var httpErrors: [Int: Int] = [:]
    private var cancelledModelIds: Set<String> = []
    private var lastReportedFraction: [Int: Double] = [:]

    private override init() {
        super.init()
    }

    /// Connects to the background session and starts delivering events, including those
    /// for downloads that finished or failed while the app wasn't running
    @MainActor
    func activate(onEvent: @escaping @MainActor (Event) -> Void) {
        guard session == nil else { return }
        eventHandler = onEvent
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        configuration.isDiscretionary = false // The user is waiting for it
        configuration.sessionSendsLaunchEvents = true
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: delegateQueue)
    }

    /// Starts downloading `url` to `destination`, from where an earlier attempt stopped if it can
    func start(modelId: String, from url: URL, to destination: URL) {
        let task: URLSessionDownloadTask
        if let data = resumeData.load(for: modelId) {
            Logger.localModels.info("Resuming download of \(modelId, privacy: .public)")
            task = session.downloadTask(withResumeData: data)
        } else {
            task = session.downloadTask(with: url)
        }
        resumeData.remove(for: modelId)
        task.taskDescription = DownloadTag(modelId: modelId, destinationPath: destination.path).encoded
        delegateQueue.addOperation { [self] in cancelledModelIds.remove(modelId) }
        task.resume()
    }

    /// Stops a download and throws away what it got
    func cancel(modelId: String) {
        resumeData.remove(for: modelId)
        session.getAllTasks { [self] tasks in
            delegateQueue.addOperation { [self] in
                cancelledModelIds.insert(modelId)
                for task in tasks where DownloadTag(task.taskDescription)?.modelId == modelId {
                    task.cancel()
                }
            }
        }
    }

    /// Whether starting `modelId` again would pick up where it stopped
    func canResume(modelId: String) -> Bool {
        resumeData.load(for: modelId) != nil
    }

    /// Downloads still running in the session, by model, with how far along they are
    func activeDownloads() async -> [String: Double] {
        let tasks = await session.allTasks
        var active: [String: Double] = [:]
        for task in tasks where task.state == .running || task.state == .suspended {
            guard let tag = DownloadTag(task.taskDescription) else { continue }
            let expected = task.countOfBytesExpectedToReceive
            active[tag.modelId] = expected > 0 ? Double(task.countOfBytesReceived) / Double(expected) : 0
        }
        return active
    }

    private func send(_ event: Event) {
        Task { @MainActor [eventHandler] in eventHandler?(event) }
    }

    /// What to tell the user about a failed download
    static func failureMessage(for error: Error, canResume: Bool) -> String {
        let nsError = error as NSError
        let continueHint = canResume ? " Try again to pick up where it left off." : ""
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled,
           nsError.userInfo[NSURLErrorBackgroundTaskCancelledReasonKey] as? Int == NSURLErrorCancelledReasonUserForceQuitApplication {
            return "The download paused when Dualo was closed." + continueHint
        }
        switch (error as? URLError)?.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            return "The connection was lost." + continueHint
        case .timedOut:
            return "The download timed out." + continueHint
        default:
            if case LocalModelError.downloadFailed(let reason) = error {
                return reason
            }
            return error.localizedDescription + continueHint
        }
    }
}

// MARK: - URLSessionDownloadDelegate

extension ModelDownloader: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0, let tag = DownloadTag(downloadTask.taskDescription) else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        // A tenth of a percent at a time is plenty for a progress bar
        guard fraction - lastReportedFraction[downloadTask.taskIdentifier, default: -1] >= 0.001 else { return }
        lastReportedFraction[downloadTask.taskIdentifier] = fraction
        send(.progress(modelId: tag.modelId, fraction: fraction))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The file at `location` is deleted when this returns, so it's moved now
        guard let tag = DownloadTag(downloadTask.taskDescription) else { return }
        if let response = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(response.statusCode) {
            httpErrors[downloadTask.taskIdentifier] = response.statusCode
            return
        }
        let destination = URL(fileURLWithPath: tag.destinationPath)
        do {
            let fileManager = FileManager.default
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: location, to: destination)
            finishedFiles[downloadTask.taskIdentifier] = destination
        } catch {
            Logger.localModels.error("Couldn't save downloaded model: \(String(describing: error), privacy: .public)")
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let id = task.taskIdentifier
        let finishedFile = finishedFiles.removeValue(forKey: id)
        let httpError = httpErrors.removeValue(forKey: id)
        lastReportedFraction[id] = nil
        guard let tag = DownloadTag(task.taskDescription) else { return }

        if let error {
            if cancelledModelIds.remove(tag.modelId) != nil { return } // Cancelled by the user
            if let data = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
                resumeData.save(data, for: tag.modelId)
            }
            Logger.localModels.error("Download of \(tag.modelId, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            send(.failed(modelId: tag.modelId, error: error))
        } else if let httpError {
            send(.failed(modelId: tag.modelId, error: LocalModelError.downloadFailed("The server returned an error (\(httpError)).")))
        } else if let finishedFile {
            Logger.localModels.info("Downloaded \(tag.modelId, privacy: .public)")
            send(.finished(modelId: tag.modelId, file: finishedFile))
        } else {
            send(.failed(modelId: tag.modelId, error: LocalModelError.downloadFailed("The file couldn't be saved.")))
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            backgroundEventsCompletionHandler?()
            backgroundEventsCompletionHandler = nil
        }
    }
}

// MARK: - Download Tag

/// Which model a session task downloads and where its file goes, kept in the task's
/// description so a relaunched app can tell its downloads apart
struct DownloadTag: Codable, Equatable {
    let modelId: String
    let destinationPath: String

    init(modelId: String, destinationPath: String) {
        self.modelId = modelId
        self.destinationPath = destinationPath
    }

    init?(_ description: String?) {
        guard let data = description?.data(using: .utf8),
              let tag = try? JSONDecoder().decode(DownloadTag.self, from: data) else { return nil }
        self = tag
    }

    var encoded: String {
        String(decoding: (try? JSONEncoder().encode(self)) ?? Data(), as: UTF8.self)
    }
}

// MARK: - Resume Data

/// What a stopped download got so far, one file per model, so trying again (even after a
/// relaunch) continues it. Kept in Caches: losing it only means starting over.
struct ResumeDataStore {
    let directory: URL

    init(directory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ModelDownloads", isDirectory: true)) {
        self.directory = directory
    }

    func save(_ data: Data, for modelId: String) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url(for: modelId), options: .atomic)
        } catch {
            Logger.localModels.error("Couldn't save resume data: \(String(describing: error), privacy: .public)")
        }
    }

    func load(for modelId: String) -> Data? {
        try? Data(contentsOf: url(for: modelId))
    }

    func remove(for modelId: String) {
        try? FileManager.default.removeItem(at: url(for: modelId))
    }

    private func url(for modelId: String) -> URL {
        let safeName = modelId.replacingOccurrences(of: "/", with: "_")
        return directory.appendingPathComponent(safeName).appendingPathExtension("resumedata")
    }
}
