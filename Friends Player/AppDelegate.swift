//
//  AppDelegate.swift
//  Friends Player
//

import UIKit
import CloudKit
import OSLog

private let pushLog = Logger(subsystem: "com.luxrecta.Friends-Player", category: "RemotePush")

// NSPersistentCloudKitContainer (the engine SwiftData uses under the hood
// when cloudKitDatabase: .automatic) creates its own CloudKit subscriptions
// automatically, but iOS will only actually deliver the resulting silent
// push notifications if the app has called registerForRemoteNotifications()
// at least once. Without that call, cross-device sync still eventually
// happens (each cold app launch triggers an import pass), but a change made
// on one device won't reach another device that's already running/
// foregrounded until it's relaunched -- which is exactly the "favorites/
// playlists/new tag aren't syncing" symptom being reported. This was
// missing entirely (no AppDelegate existed), so no push token was ever
// requested and CloudKit's change notifications had no way to reach a
// running app in the background.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        pushLog.debug("Registered for remote notifications (silent push for CloudKit sync is now enabled).")
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Common on the iOS Simulator (no APNs there) and if push
        // notifications aren't fully provisioned yet -- CloudKit sync will
        // fall back to cold-launch-only imports until this succeeds on a
        // real device with a valid provisioning profile.
        pushLog.error("Failed to register for remote notifications: \(error.localizedDescription, privacy: .public)")
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // NSPersistentCloudKitContainer observes CloudKit database changes
        // internally and imports automatically once woken up by this push;
        // there's nothing further to parse out of userInfo ourselves. Just
        // acknowledge the fetch so iOS knows we handled it.
        pushLog.debug("Received a remote (CloudKit) push notification.")
        completionHandler(.newData)
    }

    // Fires when the user taps a Family Favorites CKShare link (Messages,
    // Mail, wherever it was sent) and the OS routes it to this app since
    // the share belongs to this app's iCloud container. Unlike the
    // familyplayer:// deep links elsewhere in the app, no custom URL scheme
    // or onOpenURL handling is needed for this -- CloudKit share links are
    // routed by the system straight to this delegate method.
    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        pushLog.debug("userDidAcceptCloudKitShareWith: accepting a Family Favorites share invitation.")
        Task {
            await FavoritesSharingService.acceptShare(cloudKitShareMetadata)
        }
    }
}
