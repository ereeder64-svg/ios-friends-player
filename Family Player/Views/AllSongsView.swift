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

                if !filteredSongs.isEmpty {
                    SongsCountFooter(songs: filteredSongs)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                }
            }
            .padding(.bottom, 16)
        }
        .navigationTitle("Songs")
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search songs, personas, albums"
        )
        .toolbar {
            if !songs.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        BulkDownloadMenuItems(songs: songs, label: "All Songs")
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .overlay {
            if songs.isEmpty {
                ContentUnavailableView("No Songs", systemImage: "music.note")
            } else if filteredSongs.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }
}

struct SongsCountFooter: View {
    let songs: [Song]
    var style: FooterStyle = .light

    enum FooterStyle {
        case light   // dark text on light background (list tabs)
        case dark    // light text on dark ambient background (album/playlist detail)
    }

    private var totalSeconds: Double {
        songs.reduce(0) { $0 + ($1.duration > 0 ? $1.duration : 0) }
    }

    private var text: String {
        let count = songs.count
        let songsStr = "\(count) song\(count == 1 ? "" : "s")"
        guard totalSeconds > 0 else { return songsStr }
        let total = Int(totalSeconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let durStr: String
        if hours > 0 {
            durStr = "\(hours) hour\(hours == 1 ? "" : "s") \(minutes) minute\(minutes == 1 ? "" : "s")"
        } else {
            durStr = "\(minutes) minute\(minutes == 1 ? "" : "s")"
        }
        return "\(songsStr), \(durStr)"
    }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(style == .dark ? Color.white.opacity(0.55) : Color.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
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
