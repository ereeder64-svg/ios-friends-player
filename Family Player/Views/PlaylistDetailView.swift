//
//  PlaylistDetailView.swift
//  Family Player
//

import SwiftUI
import SwiftData

struct PlaylistDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(PlaybackEngine.self) private var engine
    let playlist: Playlist

    @State private var showRenameSheet = false
    @State private var showDeleteConfirm = false

    private var sortedEntries: [PlaylistEntry] {
        switch playlist.sortMode {
        case .alpha:
            return playlist.entries.sorted { ($0.song?.title ?? "") < ($1.song?.title ?? "") }
        case .dateAdded:
            return playlist.entries.sorted { $0.dateAdded < $1.dateAdded }
        }
    }

    private var sortedSongs: [Song] {
        sortedEntries.compactMap { $0.song }
    }

    private var collageArts: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for entry in playlist.entries.sorted(by: { $0.position < $1.position }) {
            if let path = entry.song?.album?.artworkCachePath, seen.insert(path).inserted {
                result.append(path)
                if result.count == 4 { break }
            }
        }
        return result
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                PlaylistCollageView(cachePaths: collageArts, title: playlist.name, cornerRadius: 12)
                    .frame(width: 260, height: 260)
                    .shadow(color: .black.opacity(0.35), radius: 14, x: 0, y: 6)
                    .padding(.top, 24)

                VStack(spacing: 4) {
                    Text(playlist.name)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Text("\(sortedSongs.count) song\(sortedSongs.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.horizontal)

                PlayShuffleButtons(songs: sortedSongs)
                    .padding(.horizontal)

                sortPicker

                LazyVStack(spacing: 0) {
                    ForEach(Array(sortedSongs.enumerated()), id: \.element.stableID) { idx, song in
                        SongListRow(song: song, scope: sortedSongs, style: .dark, fromPlaylist: playlist)
                        if idx < sortedSongs.count - 1 {
                            Divider()
                                .background(.white.opacity(0.15))
                                .padding(.leading, 48)
                        }
                    }
                }
                .padding(.horizontal)

                SongsCountFooter(songs: sortedSongs, style: .dark)
                    .padding(.horizontal)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
            }
        }
        .background(background)
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showRenameSheet = true
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    BulkDownloadMenuItems(songs: sortedSongs, label: "Playlist")
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete Playlist", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showRenameSheet) {
            RenamePlaylistSheet(playlist: playlist)
        }
        .alert("Delete Playlist?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                modelContext.delete(playlist)
                try? modelContext.save()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This deletes the playlist but does not delete the songs.")
        }
    }

    @ViewBuilder
    private var sortPicker: some View {
        Picker("Sort", selection: Binding(
            get: { playlist.sortMode },
            set: {
                playlist.sortMode = $0
                try? playlist.modelContext?.save()
            }
        )) {
            Text("Alphabetical").tag(PlaylistSortMode.alpha)
            Text("Date Added").tag(PlaylistSortMode.dateAdded)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }

    @ViewBuilder
    private var background: some View {
        if let firstPath = collageArts.first,
           let image = UIImage(contentsOfFile: firstPath) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .blur(radius: 80)
                .overlay(Color.black.opacity(0.45))
                .ignoresSafeArea()
        } else {
            let tint = AlbumArtworkView.accentColor(for: playlist.name)
            LinearGradient(colors: [tint.opacity(0.55), .black], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
    }
}
