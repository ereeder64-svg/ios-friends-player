//
//  AlbumTile.swift
//  Family Player
//

import SwiftUI

struct AlbumTile: View {
    let album: Album

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            AlbumArtworkView(
                cachePath: album.artworkCachePath,
                title: album.title,
                cornerRadius: 8
            )
            Text(album.title)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let persona = album.persona {
                Text(persona.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
