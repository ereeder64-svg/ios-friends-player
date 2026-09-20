//
//  NewTabView.swift
//  Friends Player
//

import SwiftUI
import SwiftData

// Thin wrapper for iPhone/portrait tab-bar use, where this needs its own
// NavigationStack. The sidebar (iPad landscape) hosts NewTabContent
// directly inside its own single shared NavigationStack instead --
// .toolbar{} content only merges into a NavigationStack's bar when it's
// applied to a view genuinely inside one, not layered on from outside.
struct NewTabView: View {
    var body: some View {
        NavigationStack {
            NewTabContent()
        }
    }
}

struct NewTabContent: View {
    @Environment(ShareAccessCoordinator.self) private var coordinator
    @Query(
        filter: #Predicate<Song> { !$0.hasBeenPlayed },
        sort: \Song.dateAddedToLibrary,
        order: .reverse
    )
    private var newSongs: [Song]

    @State private var displayedSongs: [Song] = []
    @State private var searchText = ""

    // Only songs from shares this device has actually connected -- see
    // ShareAccessCoordinator.connectedShareNames.
    private var reachableNewSongs: [Song] {
        newSongs.filter { coordinator.connectedShareNames.contains($0.shareName) }
    }

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
        ScrollView {
            VStack(spacing: 16) {
                PlayShuffleButtons(songs: filteredSongs)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                SongListSection(songs: filteredSongs)

                if !filteredSongs.isEmpty {
                    SongsCountFooter(songs: filteredSongs)
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                }
            }
            .padding(.bottom, 16)
        }
        .navigationTitle("New")
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search new songs"
        )
        .refreshable {
            // hasBeenPlayed is a normal synced field, but CloudKit's
            // private-database sync is eventually-consistent -- a song
            // played on another device may take a little while to land
            // here. displayedSongs is deliberately only re-snapshotted
            // from the live `newSongs` query on appear (so a song you're
            // actively playing doesn't vanish out from under you), so
            // give people an explicit way to check for anything that's
            // synced in since, instead of needing to leave and re-enter
            // the tab (or replay songs individually per device).
            displayedSongs = reachableNewSongs
        }
        .toolbar {
            if !displayedSongs.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        BulkDownloadMenuItems(songs: displayedSongs, label: "All New")
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
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
        .onAppear {
            displayedSongs = reachableNewSongs
        }
    }
}
