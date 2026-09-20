//
//  GenresListView.swift
//  Friends Player
//

import SwiftUI
import SwiftData

struct GenresListView: View {
    @Query(sort: \Song.title) private var allSongsRaw: [Song]
    @Environment(ShareAccessCoordinator.self) private var coordinator
    @State private var searchText = ""

    // Only songs from shares this device has actually connected -- see
    // ShareAccessCoordinator.connectedShareNames.
    private var songs: [Song] {
        allSongsRaw.filter { coordinator.connectedShareNames.contains($0.shareName) }
    }

    private struct GenreGroup: Identifiable {
        let name: String
        let songs: [Song]
        var id: String { name }
    }

    private var groups: [GenreGroup] {
        var buckets: [String: [Song]] = [:]
        for song in songs {
            buckets[Song.genreName(for: song), default: []].append(song)
        }
        return buckets.map { GenreGroup(name: $0.key, songs: $0.value) }
            .sorted { a, b in
                // "Unknown Genre" always sorts last -- it's a catch-all,
                // not a real genre, so it shouldn't compete alphabetically
                // with tagged ones.
                if a.name == "Unknown Genre" { return false }
                if b.name == "Unknown Genre" { return true }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
    }

    private var filteredGroups: [GenreGroup] {
        guard !searchText.isEmpty else { return groups }
        let q = searchText.lowercased()
        return groups.filter { $0.name.lowercased().contains(q) }
    }

    var body: some View {
        List {
            ForEach(filteredGroups) { group in
                NavigationLink {
                    GenreDetailView(genreName: group.name, songs: group.songs)
                } label: {
                    HStack {
                        Text(group.name)
                            .foregroundStyle(group.name == "Unknown Genre" ? .secondary : .primary)
                        Spacer()
                        Text("\(group.songs.count)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Genres")
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search genres"
        )
        .overlay {
            if songs.isEmpty {
                ContentUnavailableView(
                    "No Songs",
                    systemImage: "guitars",
                    description: Text("Scan the library to populate.")
                )
            } else if filteredGroups.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }
}

struct GenreDetailView: View {
    let genreName: String
    let songs: [Song]

    private var sortedSongs: [Song] {
        songs.sorted { $0.title < $1.title }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                PlayShuffleButtons(songs: sortedSongs)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                SongListSection(songs: sortedSongs)

                if !sortedSongs.isEmpty {
                    SongsCountFooter(songs: sortedSongs)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                }
            }
            .padding(.bottom, 16)
        }
        .navigationTitle(genreName)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    BulkDownloadMenuItems(songs: sortedSongs, label: "Genre")
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        // Pushed from GenresListView -- without this, drilling into a
        // genre with the iPad sidebar collapsed would leave no way back to
        // the drawer (a pushed screen's own .toolbar replaces, rather than
        // adds to, whatever the parent screen had -- see
        // SidebarDrawerToolbar.swift).
        .sidebarDrawerToolbar()
    }
}
