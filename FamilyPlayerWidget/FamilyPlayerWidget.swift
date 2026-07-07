//
//  FamilyPlayerWidget.swift
//  FamilyPlayerWidget
//

import WidgetKit
import SwiftUI
import AppIntents

struct NowPlayingEntry: TimelineEntry {
    let date: Date
    let snapshot: NowPlayingSnapshot
    let artworkData: Data?
    let recentAlbums: RecentAlbumsSnapshot
    let recentAlbumArtworkData: [Data?]
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> NowPlayingEntry {
        NowPlayingEntry(date: Date(), snapshot: .empty, artworkData: nil, recentAlbums: .empty, recentAlbumArtworkData: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (NowPlayingEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingEntry>) -> Void) {
        let entry = currentEntry()
        // Refresh every 30 min as a safety net; the app calls
        // WidgetCenter.shared.reloadAllTimelines() on actual state changes.
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func currentEntry() -> NowPlayingEntry {
        let snapshot = NowPlayingSnapshot.load()
        var data: Data? = nil
        if let url = AppGroupConstants.sharedArtworkURL(),
           FileManager.default.fileExists(atPath: url.path) {
            data = try? Data(contentsOf: url)
        }

        let recentAlbums = RecentAlbumsSnapshot.load()
        let recentArtwork: [Data?] = (0..<AppGroupConstants.recentAlbumSlotCount).map { slot in
            guard let url = AppGroupConstants.sharedRecentAlbumArtworkURL(slot: slot),
                  FileManager.default.fileExists(atPath: url.path) else { return nil }
            return try? Data(contentsOf: url)
        }

        return NowPlayingEntry(date: Date(), snapshot: snapshot, artworkData: data, recentAlbums: recentAlbums, recentAlbumArtworkData: recentArtwork)
    }
}

struct FamilyPlayerWidgetEntryView: View {
    var entry: NowPlayingEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if entry.snapshot.hasSong {
                playingLayout
            } else {
                emptyLayout
                    .overlay(alignment: .topTrailing) { appIconBadge }
            }
        }
    }

    @ViewBuilder
    private var playingLayout: some View {
        if family == .systemSmall {
            smallLayout
        } else {
            mediumLayout
        }
    }

    // Dark color scheme -> the transparent WHITE icon (reads clearly
    // against a dark system appearance); light color scheme -> transparent
    // RED, matching the dark/light alternate app icons already offered in
    // AppIconPicker. This intentionally reuses those same source images
    // (copied into the widget's own asset catalog, since a widget
    // extension can't reference the main app target's asset catalog).
    private var appIconImage: some View {
        Image(colorScheme == .dark ? "WidgetBadgeWhite" : "WidgetBadgeRed")
            .resizable()
            .scaledToFit()
            .frame(width: 22, height: 22)
            .clipShape(Circle())
    }

    private var appIconBadge: some View {
        appIconImage
            .padding(family == .systemSmall ? 10 : 12)
    }

    // MARK: - Small (2x2)

    // Title: up to 2 lines, shrinks between these bounds before truncating.
    // Floors raised now that displayed titles no longer carry the "NN "
    // track-number prefix — there's more room before text needs to shrink.
    // 2x2 gets the smaller of the two size ranges — the 2x4 is roughly
    // twice as wide, so it gets the larger range (see mediumTitle* below).
    private static let titleMaxSize: CGFloat = 14
    private static let titleMinSize: CGFloat = 13.5
    // Artist: always exactly 1 line, shrinks between these bounds.
    private static let artistMaxSize: CGFloat = 11
    private static let artistMinSize: CGFloat = 10.5

    private var smallLayout: some View {
        HStack(alignment: .top, spacing: 8) {
            // Left column: artwork, then a fixed bottom-anchored artist line
            // with the title centered in whatever space is left above it.
            // Both columns span the full widget height, so the artist's
            // floor always lines up with the play button's floor.
            VStack(alignment: .leading, spacing: 0) {
                artwork
                    .frame(width: 72, height: 72)
                Spacer(minLength: 4)
                Text(entry.snapshot.songTitle)
                    .font(.system(size: Self.titleMaxSize, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(Self.titleMinSize / Self.titleMaxSize)
                    .frame(maxWidth: 92, alignment: .leading)
                Spacer(minLength: 2)
                Text(entry.snapshot.personaName)
                    .font(.system(size: Self.artistMaxSize))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                    .minimumScaleFactor(Self.artistMinSize / Self.artistMaxSize)
                    .frame(maxWidth: 92, alignment: .leading)
            }
            .frame(maxHeight: .infinity)

            Spacer(minLength: 4)

            // Right column: icon pinned near the top, play button pinned
            // near the bottom — both spanning the same full height as the
            // left column, so the button's floor always lines up with it.
            // Trailing-aligned so the (narrower) icon lines up with the
            // right edge of the (wider) play button below it, instead of
            // sitting centered above it.
            VStack(alignment: .trailing, spacing: 0) {
                appIconImage
                Spacer(minLength: 0)
                Button(intent: PlayPauseIntent()) {
                    Image(systemName: entry.snapshot.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 40, height: 40)
                        .background(.white, in: Circle())
                }
                .buttonStyle(.plain)
            }
            .frame(maxHeight: .infinity)
        }
    }

    // MARK: - Medium (4x2)

    // Same rationale as the small layout: floors raised now that the
    // trailing track-number prefix is gone from displayed titles.
    // 2x4 is roughly twice as wide as the 2x2, so it gets the larger
    // title size range (the 2x2's old range, before this swap).
    private static let mediumTitleMaxSize: CGFloat = 16
    private static let mediumTitleMinSize: CGFloat = 14.5
    // Artist floor raised 1pt from before; max bumped along with it to
    // preserve shrink headroom (min would otherwise meet the ceiling).
    private static let mediumArtistMaxSize: CGFloat = 13
    private static let mediumArtistMinSize: CGFloat = 12

    private var mediumLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Now-playing bar: artwork, title/artist, single play/pause
            // control, and the app icon — mirrors the small widget's
            // conventions (icon sits beside the control, not the corner).
            HStack(spacing: 10) {
                artwork
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.snapshot.songTitle)
                        .font(.system(size: Self.mediumTitleMaxSize, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(Self.mediumTitleMinSize / Self.mediumTitleMaxSize)
                    Text(entry.snapshot.personaName)
                        .font(.system(size: Self.mediumArtistMaxSize))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                        .minimumScaleFactor(Self.mediumArtistMinSize / Self.mediumArtistMaxSize)
                }
                Spacer(minLength: 4)
                Button(intent: PlayPauseIntent()) {
                    Image(systemName: entry.snapshot.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 34, height: 34)
                        .background(.white, in: Circle())
                }
                .buttonStyle(.plain)
                appIconImage
            }

            // Recent albums: last 4 distinct albums played, most-recent
            // first (random fill-ins if history is thin). Tapping opens
            // the album directly.
            if !entry.recentAlbums.albums.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(entry.recentAlbums.albums.enumerated()), id: \.element.id) { index, item in
                        Button(intent: OpenAlbumIntent(albumID: item.id)) {
                            recentAlbumThumbnail(
                                data: index < entry.recentAlbumArtworkData.count ? entry.recentAlbumArtworkData[index] : nil
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func recentAlbumThumbnail(data: Data?) -> some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.white.opacity(0.15))
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    )
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
        )
    }

    // MARK: - Artwork

    @ViewBuilder
    private var artwork: some View {
        Group {
            if let data = entry.artworkData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.white.opacity(0.15))
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.6))
                    )
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 2)
    }

    // MARK: - Empty state

    private var emptyLayout: some View {
        VStack(alignment: family == .systemSmall ? .center : .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 10)
                .fill(.white.opacity(0.12))
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.6))
                )
            VStack(alignment: family == .systemSmall ? .center : .leading, spacing: 2) {
                Text("Family Player")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                Text("Nothing playing")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
            Label("Open", systemImage: "play.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.white.opacity(0.18), in: Capsule())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity,
               alignment: family == .systemSmall ? .center : .leading)
        .multilineTextAlignment(family == .systemSmall ? .center : .leading)
    }
}

struct FamilyPlayerWidget: Widget {
    let kind: String = "FamilyPlayerWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            FamilyPlayerWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    background(for: entry)
                }
        }
        .configurationDisplayName("Now Playing")
        .description("Show what's playing and control playback.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }

    @ViewBuilder
    private func background(for entry: NowPlayingEntry) -> some View {
        if let data = entry.artworkData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .blur(radius: 24)
                .overlay(Color.black.opacity(0.5))
        } else {
            LinearGradient(
                colors: [.indigo.opacity(0.7), .black],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

#Preview(as: .systemSmall) {
    FamilyPlayerWidget()
} timeline: {
    NowPlayingEntry(
        date: .now,
        snapshot: NowPlayingSnapshot(
            hasSong: true,
            songTitle: "Battle of the Bell",
            personaName: "Eric Reeder",
            albumTitle: "Rise Up",
            isPlaying: true,
            updatedAt: .now
        ),
        artworkData: nil,
        recentAlbums: .empty,
        recentAlbumArtworkData: []
    )
}

#Preview(as: .systemMedium) {
    FamilyPlayerWidget()
} timeline: {
    NowPlayingEntry(
        date: .now,
        snapshot: NowPlayingSnapshot(
            hasSong: true,
            songTitle: "Battle of the Bell",
            personaName: "Eric Reeder",
            albumTitle: "Rise Up",
            isPlaying: true,
            updatedAt: .now
        ),
        artworkData: nil,
        recentAlbums: RecentAlbumsSnapshot(albums: [
            RecentAlbumEntry(id: "share|rise-up", title: "Rise Up", personaName: "Eric Reeder"),
            RecentAlbumEntry(id: "share|josie", title: "Josie", personaName: "Steely Dan"),
            RecentAlbumEntry(id: "share|classic", title: "Classic Rewind", personaName: "Various"),
            RecentAlbumEntry(id: "share|hallways", title: "Hallways", personaName: "Various")
        ]),
        recentAlbumArtworkData: [nil, nil, nil, nil]
    )
}
