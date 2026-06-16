//
//  PlaylistsTabView.swift
//  Family Player
//

import SwiftUI
import SwiftData

struct PlaylistsTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Playlist.dateCreated, order: .reverse) private var playlists: [Playlist]
    @State private var searchText = ""
    @State private var showCreateSheet = false

    private let columns = [
        GridItem(.flexible(), spacing: 20),
        GridItem(.flexible(), spacing: 20)
    ]

    private var filteredPlaylists: [Playlist] {
        guard !searchText.isEmpty else { return playlists }
        let q = searchText.lowercased()
        return playlists.filter { $0.name.lowercased().contains(q) }
    }

    private var allSongs: [Song] {
        var seen = Set<String>()
        var result: [Song] = []
        for playlist in filteredPlaylists {
            let sorted = playlist.entries.sorted { $0.position < $1.position }
            for entry in sorted {
                if let song = entry.song, seen.insert(song.stableID).inserted {
                    result.append(song)
                }
            }
        }
        return result
    }

    var body: some View {
        NavigationStack {
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
}
