//
//  SongListRow.swift
//  Family Player
//

import SwiftUI
import SwiftData

struct SongListRow: View {
    @Environment(PlaybackEngine.self) private var engine
    @Environment(\.songRowLayout) private var rowLayout
    let song: Song
    let scope: [Song]
    var style: RowStyle = .light
    var subtitleMode: SubtitleMode = .artistAndAlbum
    var fromPlaylist: Playlist? = nil

    enum RowStyle {
        case light   // dark text on light background
        case dark    // light text on dark ambient background
    }

    enum SubtitleMode {
        case artistAndAlbum  // "Artist • Album" — default
        case artistOnly       // just the persona/artist
        case none            // no subtitle; title may wrap to two lines
    }

    private var titleColor: Color {
        style == .dark ? .white : .primary
    }

    private var subtitleColor: Color {
        style == .dark ? .white.opacity(0.65) : .secondary
    }

    private var titleLineLimit: Int {
        subtitleMode == .none ? 2 : 1
    }

    // Columns (artist / album / duration) only make sense once there's a
    // stacked subtitle to replace -- on iPhone (.compact) there's no room
    // for them regardless of subtitleMode, and callers that pass .none
    // (nothing worth showing at all, e.g. Album detail on iPhone) don't
    // get columns either.
    private var showsColumns: Bool {
        rowLayout != .compact && subtitleMode != .none
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
                        title: song.album?.title ?? song.displayTitle,
                        size: 44,
                        cornerRadius: 4
                    )
                    if showsColumns {
                        // Its own, more generously-spaced group -- these
                        // text columns need real breathing room between
                        // them or they read as one crowded, run-together
                        // block right on top of the title. The tight
                        // spacing: 10 above is fine for icon-sized artwork,
                        // not for column text.
                        HStack(spacing: 40) {
                            titleAndSubtitle
                            artistColumn
                            // Album detail's rows pass .artistOnly since
                            // every row's album is the one already titling
                            // the screen -- a repeated album column there
                            // would be pure redundancy, so it's gated on
                            // .artistAndAlbum specifically, not just .wide.
                            if rowLayout == .wide && subtitleMode == .artistAndAlbum {
                                albumColumn
                            }
                        }
                        // A small, fixed gap rather than a big empty one --
                        // titleAndSubtitle's own bounded maxWidth (below) is
                        // what actually absorbs most of the freed space on
                        // wide rows, so duration/download don't end up
                        // stranded far from the rest of the row.
                        Spacer(minLength: 12)
                            .frame(maxWidth: 32)
                        durationColumn
                    } else {
                        titleAndSubtitle
                        Spacer(minLength: 6)
                    }
                    DownloadStatusIcon(song: song, style: style)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            SongActionsMenu(song: song, fromPlaylist: fromPlaylist, style: style)
        }
    }

    // iPhone (and any compact-width context) keeps the original stacked
    // title-over-subtitle layout -- there's no room for separate columns.
    // On iPad, once columns take over for artist/album/duration, the title
    // stands alone and just needs to flex to fill whatever space is left.
    // A bounded (not unbounded .infinity) max width: SwiftUI grows a view
    // like this to fill available space up to the cap before handing any
    // remainder to the Spacer, so the title actually uses the freed-up
    // room instead of truncating while empty space sits unused further
    // right. Capped, rather than truly unbounded, so it still can't shove
    // artist/album/duration all the way to the trailing edge the way an
    // .infinity maxWidth did before.
    private var titleMaxWidth: CGFloat {
        rowLayout == .wide ? 360 : 480
    }

    @ViewBuilder
    private var titleAndSubtitle: some View {
        if showsColumns {
            Text(song.displayTitle)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(titleColor)
                .lineLimit(1)
                .frame(maxWidth: titleMaxWidth, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text(song.displayTitle)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(titleColor)
                    .lineLimit(titleLineLimit)
                subtitle
            }
        }
    }

    @ViewBuilder
    private var artistColumn: some View {
        Text(song.album?.persona?.name ?? "")
            .font(.subheadline)
            .foregroundStyle(subtitleColor)
            .lineLimit(1)
            .frame(maxWidth: 200, alignment: .leading)
    }

    @ViewBuilder
    private var albumColumn: some View {
        Text(song.album?.title ?? "")
            .font(.subheadline)
            .foregroundStyle(subtitleColor)
            .lineLimit(1)
            .frame(maxWidth: 220, alignment: .leading)
    }

    private var durationText: String {
        guard song.duration > 0 else { return "" }
        let totalSeconds = Int(song.duration.rounded())
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    @ViewBuilder
    private var durationColumn: some View {
        Text(durationText)
            .font(.caption)
            .foregroundStyle(subtitleColor)
            .monospacedDigit()
            .frame(width: 40, alignment: .trailing)
    }

    @ViewBuilder
    private var subtitle: some View {
        switch subtitleMode {
        case .artistAndAlbum:
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
        case .artistOnly:
            if let persona = song.album?.persona?.name {
                Text(persona)
                    .font(.caption)
                    .foregroundStyle(subtitleColor)
                    .lineLimit(1)
            }
        case .none:
            EmptyView()
        }
    }
}

struct FavoriteMenuButton: View {
    @Environment(FavoritesSharingService.self) private var favoritesSharing
    let song: Song

    var body: some View {
        Button {
            song.isFavorite.toggle()
            try? song.modelContext?.save()
            Task { await favoritesSharing.syncFavorite(song) }
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
        if downloads.downloadedStableIDs.contains(song.stableID) {
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
        } else if downloads.downloadedStableIDs.contains(song.stableID) {
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
        songs.contains { !downloads.downloadedStableIDs.contains($0.stableID) }
    }

    private var anyDownloaded: Bool {
        songs.contains { downloads.downloadedStableIDs.contains($0.stableID) }
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
