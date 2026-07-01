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
    var style: RowStyle = .light
    var fromPlaylist: Playlist? = nil

    enum RowStyle {
        case light   // dark text on light background
        case dark    // light text on dark ambient background
    }

    private var titleColor: Color {
        style == .dark ? .white : .primary
    }

    private var subtitleColor: Color {
        style == .dark ? .white.opacity(0.65) : .secondary
    }

    var body: some View {
        HStack(spacing: 0) {
            Button {
                Task { await engine.play(song: song, in: scope) }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(song.isFavorite ? Color.red : Color.clear)
                        .frame(width: 6)
                    AlbumArtworkView(
                        cachePath: song.album?.artworkCachePath,
                        title: song.album?.title ?? song.title,
                        size: 44,
                        cornerRadius: 4
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(song.title)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(titleColor)
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
                        .foregroundStyle(subtitleColor)
                        .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    DownloadStatusIcon(song: song, style: style)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            SongActionsMenu(song: song, fromPlaylist: fromPlaylist, style: style)
        }
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
    var style: SongListRow.RowStyle = .light

    var body: some View {
        if downloads.isDownloading(song) {
            ProgressView().controlSize(.mini)
        } else if song.downloadCachePath != nil {
            Image(systemName: "arrow.down.circle.fill")
                .font(.caption2)
                .foregroundStyle(style == .dark ? Color.white.opacity(0.7) : Color.secondary)
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
