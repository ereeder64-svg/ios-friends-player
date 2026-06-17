//
//  SongActionsMenu.swift
//  Family Player
//

import SwiftUI
import SwiftData

struct SongActionsMenu: View {
    @Environment(PlaybackEngine.self) private var engine
    @Environment(\.modelContext) private var modelContext
    let song: Song
    var fromPlaylist: Playlist? = nil

    @State private var showAddToPlaylist = false
    @State private var showLyrics = false

    var body: some View {
        Menu {
            DownloadMenuButton(song: song)

            Button {
                showAddToPlaylist = true
            } label: {
                Label("Add to Playlist", systemImage: "text.badge.plus")
            }

            Button {
                engine.playNext(song)
            } label: {
                Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
            }

            Button {
                engine.playLast(song)
            } label: {
                Label("Play After", systemImage: "text.line.last.and.arrowtriangle.forward")
            }

            FavoriteMenuButton(song: song)

            Button {
                showLyrics = true
            } label: {
                Label("View Lyrics", systemImage: "text.alignleft")
            }

            if let playlist = fromPlaylist {
                Divider()
                Button(role: .destructive) {
                    removeFromPlaylist(playlist)
                } label: {
                    Label("Remove from Playlist", systemImage: "minus.circle")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .sheet(isPresented: $showAddToPlaylist) {
            AddToPlaylistSheet(song: song)
        }
        .sheet(isPresented: $showLyrics) {
            LyricsSheet(song: song)
        }
    }

    private func removeFromPlaylist(_ playlist: Playlist) {
        if let entry = playlist.entries.first(where: { $0.song?.stableID == song.stableID }) {
            modelContext.delete(entry)
            try? modelContext.save()
        }
    }
}
