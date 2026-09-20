//
//  PlaylistsTabView.swift
//  Friends Player
//

import SwiftUI
import SwiftData

struct PlaylistsTabView: View {
    var body: some View {
        NavigationStack {
            PlaylistsTabContent()
        }
    }
}

struct PlaylistsTabContent: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ShareAccessCoordinator.self) private var coordinator
    @Query(sort: \Playlist.dateCreated, order: .reverse) private var playlists: [Playlist]
    @State private var searchText = ""
    @State private var showCreateSheet = false

    private let columns = AdaptiveTileGrid.columns

    private var filteredPlaylists: [Playlist] {
        guard !searchText.isEmpty else { return playlists }
        let q = searchText.lowercased()
        return playlists.filter { $0.name.lowercased().contains(q) }
    }

    private var allSongs: [Song] {
        // PlaylistEntry.song has no inverse relationship on Song, so orphans can
        // slip in when a song file goes missing during a scan. Build a set of
        // known-good song IDs and use it as a safety net so we never touch a
        // faulted Song's real properties.
        guard let allSongObjects = try? modelContext.fetch(FetchDescriptor<Song>()) else { return [] }
        let validIDs = Set(
            allSongObjects
                .filter { coordinator.connectedShareNames.contains($0.shareName) }
                .map { $0.persistentModelID }
        )

        let entryDescriptor = FetchDescriptor<PlaylistEntry>(
            predicate: #Predicate<PlaylistEntry> { $0.song?.stableID != nil }
        )
        guard let entries = try? modelContext.fetch(entryDescriptor) else { return [] }
        let visiblePlaylistIDs = Set(filteredPlaylists.map { $0.persistentModelID })

        var seen = Set<PersistentIdentifier>()
        var result: [Song] = []
        for entry in entries {
            guard let playlistID = entry.playlist?.persistentModelID,
                  visiblePlaylistIDs.contains(playlistID),
                  let song = entry.song,
                  validIDs.contains(song.persistentModelID),
                  seen.insert(song.persistentModelID).inserted
            else { continue }
            result.append(song)
        }
        return result
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                PlayShuffleButtons(songs: allSongs)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(filteredPlaylists) { playlist in
                        NavigationLink {
                            PlaylistDetailView(playlist: playlist)
                        } label: {
                            PlaylistTile(playlist: playlist)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                modelContext.delete(playlist)
                                try? modelContext.save()
                            } label: {
                                Label("Delete Playlist", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 16)
        }
        .navigationTitle("Playlists")
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search playlists"
        )
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            if !allSongs.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        BulkDownloadMenuItems(songs: allSongs, label: "All Playlists")
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            CreatePlaylistSheet()
        }
        .overlay {
            if playlists.isEmpty {
                ContentUnavailableView(
                    "No Playlists",
                    systemImage: "music.note.list",
                    description: Text("Tap + to create a playlist, or use the menu on a song to add it to a new playlist.")
                )
            } else if filteredPlaylists.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }
}
