//
//  AllSongsView.swift
//  Family Player
//

import SwiftUI
import SwiftData

struct AllSongsView: View {
    @Query(sort: \Song.title) private var songs: [Song]
    @State private var searchText = ""

    private var filteredSongs: [Song] {
        guard !searchText.isEmpty else { return songs }
        let q = searchText.lowercased()
        return songs.filter { song in
            song.title.lowercased().contains(q) ||
            (song.album?.title.lowercased().contains(q) ?? false) ||
            (song.album?.persona?.name.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                PlayShuffleButtons(songs: filteredSongs)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                SongListSection(songs: filteredSongs)
            }
            .padding(.bottom, 16)
        }
        .navigationTitle("Songs")
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search songs, personas, albums"
        )
        .overlay {
            if songs.isEmpty {
                ContentUnavailableView("No Songs", systemImage: "music.note")
            } else if filteredSongs.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }
}

struct SongListSection: View {
    let songs: [Song]

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(songs.enumerated()), id: \.element.stableID) { idx, song in
                SongListRow(song: song, scope: songs)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                if idx < songs.count - 1 {
                    Divider().padding(.leading, 72)
                }
            }
        }
    }
}
