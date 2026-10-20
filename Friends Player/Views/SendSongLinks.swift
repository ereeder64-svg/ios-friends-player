//
//  SendSongLinks.swift
//  Friends Player
//

import SwiftUI

/// Menu content: one "send to a <App> user" entry per app. Each opens the
/// system share sheet (Messages, etc.) with the intro line plus the link as
/// plain text -- Messages only builds rich icon bubbles for web (https)
/// links, so an app link always arrives as text. The recipient app's icon
/// still shows in the share sheet's header. Drop inside any Menu.
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
                ),
                preview: SharePreview(
                    "Play \(song.displayTitle) in \(target.appName)",
                    icon: Image(target.iconAssetName)
                )
            ) {
                Label("Send to \(target.appName) User", systemImage: "paperplane")
            }
        }
    }
}
