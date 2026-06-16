//
//  SongListRow.swift
//  Family Player
//

import SwiftUI
import SwiftData

struct SongListRow: View {
    @Environment(PlaybackEngine.self) private var engine
    let song: Song
    let scope: [Song]

    var body: some View {
        HStack(spacing: 0) {
            Button {
                Task { await engine.play(song: song, in: scope) }
            } label: {
                HStack(spacing: 12) {
                    AlbumArtworkView(
                        cachePath: song.album?.artworkCachePath,
                        title: song.album?.title ?? song.title,
                        size: 44,
                        cornerRadius: 4
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(song.title)
                            .font(.footnote.weight(.semibold))
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            if let persona = song.album?.persona?.name {
                                Text(persona)
                            }
                            if let albumTitle = song.album?.title {
                                Text("\u{2022}")
                                Text(albumTitle)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    if song.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    DownloadStatusIcon(song: song)
                    if song.duration > 0 {
                        Text(formatDuration(song.duration))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            SongActionsMenu(song: song)
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct FavoriteMenuButton: View {
    let song: Song

    var body: some View {
        Button {
            song.isFavorite.toggle()
            try? song.modelContext?.save()
        } label: {
            Label(
                song.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                systemImage: song.isFavorite ? "heart.slash" : "heart"
            )
        }
    }
}

struct DownloadMenuButton: View {
    @Environment(DownloadManager.self) private var downloads
    let song: Song

    var body: some View {
        if song.downloadCachePath != nil {
            Button(role: .destructive) {
                downloads.remove(song: song)
            } label: {
                Label("Remove Download", systemImage: "arrow.down.circle.dotted")
            }
        } else {
            Button {
                Task { await downloads.download(song: song) }
            } label: {
                Label("Download", systemImage: "arrow.down.circle")
            }
        }
    }
}

struct DownloadStatusIcon: View {
    @Environment(DownloadManager.self) private var downloads
    let song: Song

    var body: some View {
        if downloads.isDownloading(song) {
            ProgressView().controlSize(.mini)
        } else if song.downloadCachePath != nil {
            Image(systemName: "arrow.down.circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct BulkDownloadMenuItems: View {
    @Environment(DownloadManager.self) private var downloads
    let songs: [Song]
    let label: String

    private var anyNotDownloaded: Bool {
        songs.contains { $0.downloadCachePath == nil }
    }

    private var anyDownloaded: Bool {
        songs.contains { $0.downloadCachePath != nil }
    }

    var body: some View {
        if anyNotDownloaded {
            Button {
                Task { await downloads.download(songs: songs) }
            } label: {
                Label("Download \(label)", systemImage: "arrow.down.circle")
            }
        }
        if anyDownloaded {
            Button(role: .destructive) {
                downloads.remove(songs: songs)
            } label: {
                Label("Remove \(label) Downloads", systemImage: "arrow.down.circle.dotted")
            }
        }
    }
}
