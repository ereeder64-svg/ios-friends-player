//
//  AllAlbumsView.swift
//  Family Player
//

import SwiftUI
import SwiftData

struct AllAlbumsView: View {
    @Query(sort: \Album.title) private var albums: [Album]
    @State private var searchText = ""

    private let columns = [
        GridItem(.flexible(), spacing: 20),
        GridItem(.flexible(), spacing: 20)
    ]

    private var filteredAlbums: [Album] {
        guard !searchText.isEmpty else { return albums }
        let q = searchText.lowercased()
        return albums.filter { album in
            album.title.lowercased().contains(q) ||
            (album.persona?.name.lowercased().contains(q) ?? false)
        }
    }

    private var allSongs: [Song] {
        filteredAlbums.flatMap { album in
            album.songs.sorted { ($0.trackNumber ?? 0, $0.title) < ($1.trackNumber ?? 0, $1.title) }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                PlayShuffleButtons(songs: allSongs)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(filteredAlbums) { album in
                        NavigationLink {
                            AlbumDetailView(album: album)
                        } label: {
                            AlbumTile(album: album)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
        .navigationTitle("Albums")
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search albums or personas"
        )
        .overlay {
            if albums.isEmpty {
                ContentUnavailableView("No Albums", systemImage: "square.stack")
            } else if filteredAlbums.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }
}

struct AlbumDetailView: View {
    @Environment(PlaybackEngine.self) private var engine
    let album: Album

    private var sortedSongs: [Song] {
        album.songs.sorted { ($0.trackNumber ?? 0, $0.title) < ($1.trackNumber ?? 0, $1.title) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                AlbumArtworkView(
                    cachePath: album.artworkCachePath,
                    title: album.title,
                    size: 260,
                    cornerRadius: 12
                )
                .shadow(color: .black.opacity(0.35), radius: 14, x: 0, y: 6)
                .padding(.top, 24)

                VStack(spacing: 4) {
                    Text(album.title)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    if let persona = album.persona {
                        Text(persona.name)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    Text("\(album.songs.count) song\(album.songs.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.horizontal)

                PlayShuffleButtons(songs: sortedSongs)
                    .padding(.horizontal)

                LazyVStack(spacing: 0) {
                    ForEach(Array(sortedSongs.enumerated()), id: \.element.stableID) { idx, song in
                        HStack(spacing: 0) {
                            Button {
                                Task { await engine.play(song: song, in: sortedSongs) }
                            } label: {
                                AlbumTrackRow(
                                    song: song,
                                    displayNumber: song.trackNumber ?? (idx + 1)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            SongActionsMenu(song: song)
                        }
                        if idx < sortedSongs.count - 1 {
                            Divider()
                                .background(.white.opacity(0.15))
                                .padding(.leading, 48)
                        }
                    }
                }
                .padding(.horizontal)

                AlbumFooter(songs: sortedSongs)
                    .padding(.horizontal)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
            }
        }
        .background(albumBackground)
        .navigationTitle(album.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    BulkDownloadMenuItems(songs: sortedSongs, label: "Album")
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    @ViewBuilder
    private var albumBackground: some View {
        if let path = album.artworkCachePath,
           let image = UIImage(contentsOfFile: path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .blur(radius: 80)
                .overlay(Color.black.opacity(0.45))
                .ignoresSafeArea()
        } else {
            let tint = AlbumArtworkView.accentColor(for: album.title)
            LinearGradient(
                colors: [tint.opacity(0.55), .black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }
}

struct AlbumTrackRow: View {
    let song: Song
    let displayNumber: Int

    var body: some View {
        HStack(spacing: 14) {
            Text("\(displayNumber)")
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 22, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if song.hasLyrics {
                    Text("Lyrics")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            Spacer()
            if song.isFavorite {
                Image(systemName: "heart.fill")
                    .font(.caption)
                    .foregroundStyle(.pink)
            }
            if song.downloadCachePath != nil {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            if song.duration > 0 {
                Text(formatDuration(song.duration))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 10)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
struct AlbumFooter: View {
    let songs: [Song]

    private var totalSeconds: Double {
        songs.reduce(0) { $0 + ($1.duration > 0 ? $1.duration : 0) }
    }

    var body: some View {
        Text(footerText)
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.55))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footerText: String {
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
}

