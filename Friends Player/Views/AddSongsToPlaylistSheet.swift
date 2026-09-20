//
//  AddSongsToPlaylistSheet.swift
//  Friends Player
//

import SwiftUI
import SwiftData

/// Full-library song picker presented from a playlist's Add pill. Lets the
/// user browse or search every song and tap + to add it to the playlist,
/// without leaving the sheet (mirrors the Spotify "Add songs" overlay).
struct AddSongsToPlaylistSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(PlaybackEngine.self) private var engine
    @Environment(ShareAccessCoordinator.self) private var coordinator
    @Query(sort: \Song.title) private var allSongsRaw: [Song]
    let playlist: Playlist

    @State private var searchText = ""

    private var allSongs: [Song] {
        allSongsRaw.filter { coordinator.connectedShareNames.contains($0.shareName) }
    }

    private var filteredSongs: [Song] {
        guard !searchText.isEmpty else { return allSongs }
        let q = searchText.lowercased()
        return allSongs.filter { song in
            song.displayTitle.lowercased().contains(q) ||
            (song.album?.persona?.name.lowercased().contains(q) ?? false) ||
            (song.album?.title.lowercased().contains(q) ?? false)
        }
    }

    private var existingSongIDs: Set<String> {
        Set((playlist.entries ?? []).compactMap { $0.song?.stableID })
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color.black.ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredSongs, id: \.stableID) { song in
                            AddSongRow(
                                song: song,
                                scope: filteredSongs,
                                isAdded: existingSongIDs.contains(song.stableID)
                            ) {
                                addSong(song)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 90)
                }

                searchBar
            }
            .navigationTitle("Add Songs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
            .overlay {
                if allSongs.isEmpty {
                    ContentUnavailableView("No Songs", systemImage: "music.note")
                } else if filteredSongs.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.6))
            TextField("", text: $searchText, prompt: Text("What would you like to add?").foregroundStyle(.white.opacity(0.5)))
                .foregroundStyle(.white)
                .tint(.white)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.15), in: Capsule())
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .background(
            LinearGradient(colors: [.clear, Color.black.opacity(0.95)], startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
        )
    }

    private func addSong(_ song: Song) {
        guard !existingSongIDs.contains(song.stableID) else { return }
        let position = (playlist.entries ?? []).count
        let entry = PlaylistEntry(playlist: playlist, song: song, position: position)
        modelContext.insert(entry)
        try? modelContext.save()
    }
}

private struct AddSongRow: View {
    @Environment(PlaybackEngine.self) private var engine
    let song: Song
    let scope: [Song]
    let isAdded: Bool
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                Task { await engine.play(song: song, in: scope) }
            } label: {
                ZStack {
                    AlbumArtworkView(
                        cachePath: song.album?.artworkCachePath,
                        title: song.displayTitle,
                        size: 46,
                        cornerRadius: 4
                    )
                    Image(systemName: "play.fill")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(Color.black.opacity(0.4), in: Circle())
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(song.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if let persona = song.album?.persona?.name {
                    Text(persona)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Button(action: onAdd) {
                Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle")
                    .font(.title3)
                    .foregroundStyle(isAdded ? Color.green : Color.white.opacity(0.85))
            }
            .buttonStyle(.plain)
            .disabled(isAdded)
        }
    }
}
