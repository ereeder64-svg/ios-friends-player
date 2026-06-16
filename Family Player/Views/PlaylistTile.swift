//
//  PlaylistTile.swift
//  Family Player
//

import SwiftUI

struct PlaylistTile: View {
    let playlist: Playlist

    private var collageArts: [String] {
        var seen = Set<String>()
        var result: [String] = []
        let sorted = playlist.entries.sorted { $0.position < $1.position }
        for entry in sorted {
            if let path = entry.song?.album?.artworkCachePath, seen.insert(path).inserted {
                result.append(path)
                if result.count == 4 { break }
            }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            PlaylistCollageView(cachePaths: collageArts, title: playlist.name)
            Text(playlist.name)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(playlist.entries.count) song\(playlist.entries.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
