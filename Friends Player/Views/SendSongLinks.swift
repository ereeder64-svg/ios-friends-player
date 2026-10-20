//
//  SendSongLinks.swift
//  Friends Player
//

import SwiftUI

/// Menu content: one "send to a <App> user" entry per app. Each opens the
/// system share sheet (Messages, etc.) with a link that opens that app on
/// the recipient's phone and plays this song. Drop inside any Menu.
struct SendSongLinks: View {
    @Environment(FavoritesSharingService.self) private var favoritesSharing
    let song: Song

    var body: some View {
        ForEach(SongShareLink.Target.allCases) { target in
            ShareLink(
                item: SongShareLink.message(
                    for: song,
                    sender: favoritesSharing.ownerDisplayName,
                    target: target
                )
            ) {
                Label("Send to \(target.appName) User", systemImage: "paperplane")
            }
        }
    }
}
