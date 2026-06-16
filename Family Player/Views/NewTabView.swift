//
//  NewTabView.swift
//  Family Player
//

import SwiftUI
import SwiftData

struct NewTabView: View {
    @Query(
        filter: #Predicate<Song> { !$0.hasBeenPlayed },
        sort: \Song.dateAddedToLibrary,
        order: .reverse
    )
    private var newSongs: [Song]

    @State private var displayedSongs: [Song] = []
    @State private var searchText = ""

    private var filteredSongs: [Song] {
        let base: [Song]
        if searchText.isEmpty {
            base = displayedSongs
        } else {
            let q = searchText.lowercased()
            base = displayedSongs.filter { song in
                song.title.lowercased().contains(q) ||
                (song.album?.title.lowercased().contains(q) ?? false) ||
                (song.album?.persona?.name.lowercased().contains(q) ?? false)
            }
        }
        return base.sortedByAlbumThenTitle()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    PlayShuffleButtons(songs: filteredSongs)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    SongListSection(songs: filteredSongs)
                }
                .padding(.bottom, 16)
            }
            .navigationTitle("New")
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search new songs"
            )
            .overlay {
                if displayedSongs.isEmpty {
                    ContentUnavailableView(
                        "Caught Up",
                        systemImage: "checkmark.circle",
                        description: Text("You've played everything in your library.")
                    )
                } else if filteredSongs.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
        .onAppear {
            displayedSongs = newSongs
        }
    }
}
