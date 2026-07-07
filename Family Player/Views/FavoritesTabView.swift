//
//  FavoritesTabView.swift
//  Family Player
//

import SwiftUI
import SwiftData

struct FavoritesTabView: View {
    var body: some View {
        NavigationStack {
            FavoritesTabContent()
        }
    }
}

struct FavoritesTabContent: View {
    @Query(
        filter: #Predicate<Song> { $0.isFavorite },
        sort: \Song.title
    )
    private var allFavoriteSongs: [Song]
    @Environment(ShareAccessCoordinator.self) private var coordinator
    @State private var searchText = ""

    private var favoriteSongs: [Song] {
        allFavoriteSongs.filter { coordinator.connectedShareNames.contains($0.shareName) }
    }

    private var filteredSongs: [Song] {
        let base: [Song]
        if searchText.isEmpty {
            base = Array(favoriteSongs)
        } else {
            let q = searchText.lowercased()
            base = favoriteSongs.filter { song in
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
        .navigationTitle("Favorites")
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search favorites"
        )
        .toolbar {
            if !favoriteSongs.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        BulkDownloadMenuItems(songs: Array(favoriteSongs), label: "All Favorites")
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .overlay {
            if favoriteSongs.isEmpty {
                ContentUnavailableView(
                    "No Favorites Yet",
                    systemImage: "heart",
                    description: Text("Tap the heart icon while playing, or open a song's menu to add favorites.")
                )
            } else if filteredSongs.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }
}
