//
//  AppDelegate.swift
//  Dualo
//
//  When a model download finishes or fails while Dualo isn't running, iOS relaunches
//  it in the background to hand over the result (see ModelDownloader).
//

import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        guard identifier == ModelDownloader.sessionIdentifier else {
            completionHandler()
            return
        }
        ModelDownloader.shared.backgroundEventsCompletionHandler = completionHandler
        _ = LocalModelManager.shared // Reconnects to the session, which then delivers the events
    }
}
