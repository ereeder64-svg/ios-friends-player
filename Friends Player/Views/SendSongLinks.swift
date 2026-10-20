//
//  SendSongLinks.swift
//  Friends Player
//

import SwiftUI

/// Menu content: one "send to a <App> user" entry per app. Each opens the
/// system share sheet (Messages, etc.). The link travels as a URL with a
/// preview -- the recipient app's icon plus a "Play <song> in <App>" title
/// -- so Messages shows a tappable icon bubble rather than a long raw
/// link. Drop inside any Menu.
struct SendSongLinks: View {
    @Environment(FavoritesSharingService.self) private var favoritesSharing
    let song: Song

    var body: some View {
        ForEach(SongShareLink.Target.allCases) { target in
            if let url = SongShareLink.url(for: song, sender: favoritesSharing.ownerDisplayName, target: target) {
                ShareLink(
                    item: url,
                    message: Text(SongShareLink.intro(for: song, sender: favoritesSharing.ownerDisplayName)),
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
}
