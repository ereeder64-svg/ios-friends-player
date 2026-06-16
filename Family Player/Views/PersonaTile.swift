//
//  PersonaTile.swift
//  Family Player
//

import SwiftUI

struct PersonaTile: View {
    let persona: Persona

    private var representativeArt: String? {
        persona.albums
            .sorted { $0.title < $1.title }
            .lazy
            .compactMap { $0.artworkCachePath }
            .first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            AlbumArtworkView(
                cachePath: representativeArt,
                title: persona.name,
                cornerRadius: 8
            )
            Text(persona.name)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(persona.albums.count) album\(persona.albums.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
