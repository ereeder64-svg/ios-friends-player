//
//  NowPlayingSheet.swift
//  Friends Player
//

import SwiftUI
import SwiftData

struct NowPlayingSheet: View {
    @Environment(PlaybackEngine.self) private var engine
    @Environment(FavoritesSharingService.self) private var favoritesSharing
    @Environment(\.dismiss) private var dismiss
    @State private var showingLyrics = false

    var body: some View {
        @Bindable var engine = engine

        VStack(spacing: 20) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.title3.weight(.semibold))
                }
                .buttonStyle(.plain)
                Spacer()
                Text("Now Playing")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Button {
                    showingLyrics.toggle()
                } label: {
                    Image(systemName: showingLyrics ? "quote.bubble.fill" : "quote.bubble")
                        .font(.title3)
                        .foregroundStyle(showingLyrics ? Color.accentColor : .primary)
                }
                .buttonStyle(.plain)
                .disabled(engine.currentSong == nil)
                Button {
                    if let song = engine.currentSong {
                        song.isFavorite.toggle()
                        try? song.modelContext?.save()
                        Task { await favoritesSharing.syncFavorite(song) }
                    }
                } label: {
                    Image(systemName: (engine.currentSong?.isFavorite ?? false) ? "heart.fill" : "heart")
                        .font(.title3)
                        .foregroundStyle((engine.currentSong?.isFavorite ?? false) ? .pink : .primary)
                }
                .buttonStyle(.plain)
                .disabled(engine.currentSong == nil)
            }
            .padding(.horizontal)
            .padding(.top, 8)

            Spacer()

            if let song = engine.currentSong {
                if showingLyrics {
                    LyricsView(song: song)
                        .frame(maxHeight: .infinity)
                } else {
                    AlbumArtworkView(
                        cachePath: song.album?.artworkCachePath,
                        title: song.album?.title ?? song.displayTitle,
                        size: 280,
                        cornerRadius: 12
                    )
                    VStack(spacing: 4) {
                        Text(song.displayTitle).font(.title3.bold())
                        Text(song.album?.persona?.name ?? "").foregroundStyle(.secondary)
                        if let albumTitle = song.album?.title {
                            Text(albumTitle).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                }
            } else {
                ContentUnavailableView("Nothing Playing", systemImage: "music.note")
            }

            scrubber

            HStack(spacing: 36) {
                Button {
                    engine.shuffleEnabled.toggle()
                } label: {
                    Image(systemName: "shuffle")
                        .font(.title3)
                        .foregroundStyle(engine.shuffleEnabled ? Color.accentColor : .primary)
                }
                Button {
                    Task { await engine.playPrevious() }
                } label: {
                    Image(systemName: "backward.fill").font(.title)
                }
                Button {
                    engine.togglePlayPause()
                } label: {
                    Image(systemName: engine.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 64))
                }
                Button {
                    Task { await engine.playNext() }
                } label: {
                    Image(systemName: "forward.fill").font(.title)
                }
                Button {
                    engine.loopEnabled.toggle()
                } label: {
                    Image(systemName: "repeat")
                        .font(.title3)
                        .foregroundStyle(engine.loopEnabled ? Color.accentColor : .primary)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .padding(.vertical)

            Spacer()
        }
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var scrubber: some View {
        if engine.duration > 0 {
            VStack(spacing: 4) {
                Slider(
                    value: Binding(
                        get: { min(engine.currentTime, engine.duration) },
                        set: { engine.seek(to: $0) }
                    ),
                    in: 0...engine.duration
                )
                HStack {
                    Text(timeString(engine.currentTime)).monospacedDigit()
                    Spacer()
                    Text("-" + timeString(max(0, engine.duration - engine.currentTime))).monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
        }
    }

    private func timeString(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
