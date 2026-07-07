//
//  Family_PlayerApp.swift
//  Family Player
//
//  Created by Eric Reeder on 6/16/26.
//

import SwiftUI
import SwiftData

@main
struct Family_PlayerApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Persona.self,
            Album.self,
            Song.self,
            Playlist.self,
            PlaylistEntry.self,
            ShareBookmark.self,
        ])
        // Private CloudKit database sync -- each user's own iCloud account,
        // across their own devices only (not shared between family members).
        // Uses the container declared in the entitlements file
        // (iCloud.com.luxrecta.Family-Player).
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

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(sharedModelContainer)
    }
}
