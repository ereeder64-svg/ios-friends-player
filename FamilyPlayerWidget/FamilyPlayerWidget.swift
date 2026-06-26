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
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> NowPlayingEntry {
        NowPlayingEntry(date: Date(), snapshot: .empty, artworkData: nil)
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
        return NowPlayingEntry(date: Date(), snapshot: snapshot, artworkData: data)
    }
}

struct FamilyPlayerWidgetEntryView: View {
    var entry: NowPlayingEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if entry.snapshot.hasSong {
            playingLayout
        } else {
            emptyLayout
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

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 6) {
            artwork
                .frame(maxWidth: .infinity, alignment: .center)
            Text(entry.snapshot.songTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
            Text(entry.snapshot.personaName)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
            HStack(spacing: 14) {
                Spacer()
                Button(intent: PreviousTrackIntent()) {
                    Image(systemName: "backward.fill")
                }
                Button(intent: PlayPauseIntent()) {
                    Image(systemName: entry.snapshot.isPlaying ? "pause.fill" : "play.fill")
                }
                Button(intent: NextTrackIntent()) {
                    Image(systemName: "forward.fill")
                }
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.white)
            .buttonStyle(.plain)
        }
    }

    private var mediumLayout: some View {
        HStack(spacing: 14) {
            artwork
                .frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.snapshot.songTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(entry.snapshot.personaName)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                if !entry.snapshot.albumTitle.isEmpty {
                    Text(entry.snapshot.albumTitle)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                HStack(spacing: 18) {
                    Button(intent: PreviousTrackIntent()) {
                        Image(systemName: "backward.fill")
                    }
                    Button(intent: PlayPauseIntent()) {
                        Image(systemName: entry.snapshot.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                    }
                    Button(intent: NextTrackIntent()) {
                        Image(systemName: "forward.fill")
                    }
                }
                .font(.callout)
                .foregroundStyle(.white)
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if let data = entry.artworkData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(.white.opacity(0.15))
                .aspectRatio(1, contentMode: .fit)
                .overlay(
                    Image(systemName: "music.note")
                        .foregroundStyle(.white.opacity(0.6))
                )
        }
    }

    private var emptyLayout: some View {
        VStack(spacing: 6) {
            Image(systemName: "music.note.house")
                .font(.title)
                .foregroundStyle(.white.opacity(0.7))
            Text("Family Player")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
            Text("Open to play")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
        }
        .multilineTextAlignment(.center)
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
                .blur(radius: 22)
                .overlay(Color.black.opacity(0.45))
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
            songTitle: "01 Battle of the Bell",
            personaName: "Eric Reeder",
            albumTitle: "Rise Up",
            isPlaying: true,
            updatedAt: .now
        ),
        artworkData: nil
    )
}
