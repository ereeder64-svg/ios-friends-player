//
//  SendSongLinks.swift
//  Friends Player
//

import SwiftUI

/// Menu content: one "send to a <App> user" entry per app.
///
/// To someone running this same app it sends an iMessage bubble (app icon +
/// song title, no visible link) via SongMessageComposer. To the other app --
/// or wherever Messages isn't available, like the simulator -- it falls back
/// to the share sheet with the intro line and a plain text link, since a
/// bubble only opens on a phone that has this app's Messages extension.
/// Drop inside any Menu.
struct SendSongLinks: View {
    @Environment(FavoritesSharingService.self) private var favoritesSharing
    let song: Song

    var body: some View {
        ForEach(SongShareLink.Target.allCases) { target in
            if target == .current && SongMessageComposer.canSendBubble {
                Button {
                    SongMessageComposer.shared.present(song: song, sender: favoritesSharing.ownerDisplayName)
                } label: {
                    Label("Send to \(target.appName) User", systemImage: "paperplane")
                }
            } else {
                ShareLink(
                    item: SongShareLink.message(
                        for: song,
                        sender: favoritesSharing.ownerDisplayName,
                        target: target
                    ),
                    preview: SharePreview(
                        "Play \(SongShareLink.title(of: song)) in \(target.appName)",
                        icon: Image(target.iconAssetName)
                    )
                ) {
                    Label("Send Link to \(target.appName) User", systemImage: "link")
                }
            }
        }
    }
}
