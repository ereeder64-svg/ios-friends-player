//
//  Family_PlayerApp.swift
//  Family Player
//
//  Created by Eric Reeder on 6/16/26.
//

import SwiftUI
import SwiftData
import CoreData
import OSLog

private let cloudKitSyncLog = Logger(subsystem: "com.luxrecta.Family-Player", category: "CloudKitSync")

@main
struct Family_PlayerApp: App {
    // Registers for silent push notifications so CloudKit sync (favorites,
    // playlists, "new" status, play history) reaches this device in near
    // real time instead of only refreshing on the next cold launch. See
    // AppDelegate.swift for the full rationale.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    // Private CloudKit database sync -- each user's own iCloud account,
    // across their own devices only (not shared between family members).
    // Uses the container declared in the entitlements file
    // (iCloud.com.luxrecta.Family-Player).
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Persona.self,
            Album.self,
            Song.self,
            Playlist.self,
            PlaylistEntry.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    // ShareBookmark holds a security-scoped bookmark blob, which only means
    // something to the specific device/sandbox that created it -- resolving
    // one device's bookmark on another device doesn't work, so it must
    // never sync. IMPORTANT: this is a fully separate ModelContainer, not a
    // second ModelConfiguration on the same container -- mixing a
    // CloudKit-backed configuration with a local-only one in a single
    // ModelContainer is a known SwiftData crash (immediate launch crash,
    // often with no useful console output). Two independent containers is
    // the supported way to have "some models sync, some don't."
    //
    // CRITICAL: this MUST have an explicit, distinct name. An unnamed
    // ModelConfiguration falls back to the same default store filename
    // ("default.store") regardless of its schema -- without this name,
    // this container silently pointed at the exact same SQLite file as
    // sharedModelContainer below, and the two fought over it (surfaced as
    // "no such table: ZPERSONA", "bind on a busy prepared statement", and
    // save failures -- the scan looked like it worked but nothing actually
    // persisted). Giving this one its own name gives it its own file.
    static let localOnlyModelContainer: ModelContainer = {
        let schema = Schema([ShareBookmark.self])
        let modelConfiguration = ModelConfiguration(
            "ShareBookmarksLocalStore",
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create local-only ModelContainer: \(error)")
        }
    }()

    init() {
        Self.observeCloudKitSyncEvents()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(sharedModelContainer)
    }

    // Logs every CloudKit import/export the whole app session goes through
    // (not just the one-time initial-import wait in RootView), so "is it
    // actually syncing?" is answerable by watching the Xcode console --
    // filter by subsystem "com.luxrecta.Family-Player" / category
    // "CloudKitSync" -- instead of just inferring it from the UI.
    private static func observeCloudKitSyncEvents() {
        NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else { return }
            let kind: String
            switch event.type {
            case .setup: kind = "setup"
            case .import: kind = "import"
            case .export: kind = "export"
            @unknown default: kind = "unknown"
            }
            if let endDate = event.endDate {
                if event.succeeded {
                    cloudKitSyncLog.debug("CloudKit \(kind, privacy: .public) finished at \(endDate, privacy: .public) -- succeeded.")
                } else {
                    cloudKitSyncLog.error("CloudKit \(kind, privacy: .public) finished at \(endDate, privacy: .public) -- FAILED: \(String(describing: event.error), privacy: .public)")
                }
            } else {
                cloudKitSyncLog.debug("CloudKit \(kind, privacy: .public) started.")
            }
        }
    }
}
