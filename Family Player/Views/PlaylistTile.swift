//
//  PlaylistTile.swift
//  Family Player
//

import SwiftUI
import SwiftData

struct PlaylistTile: View {
    @Environment(\.modelContext) private var modelContext
    let playlist: Playlist

    private var collageArts: [String] {
        // Fetch entries via the store, filtering out any orphaned song refs so we
        // never touch a faulted Song's properties.
        guard let allSongObjects = try? modelContext.fetch(FetchDescriptor<Song>()) else { return [] }
        let validIDs = Set(allSongObjects.map { $0.persistentModelID })

        let playlistID = playlist.persistentModelID
        let descriptor = FetchDescriptor<PlaylistEntry>(
            predicate: #Predicate<PlaylistEntry> { entry in
                entry.playlist?.persistentModelID == playlistID && entry.song?.stableID != nil
            },
            sortBy: [SortDescriptor(\.position)]
        )
        guard let entries = try? modelContext.fetch(descriptor) else { return [] }

        var seen = Set<String>()
        var result: [String] = []
        for entry in entries {
            guard let song = entry.song, validIDs.contains(song.persistentModelID) else { continue }
            if let path = song.album?.artworkCachePath, seen.insert(path).inserted {
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
            Text("\((playlist.entries ?? []).count) song\((playlist.entries ?? []).count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
