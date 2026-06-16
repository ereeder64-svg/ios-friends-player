//
//  MiniPlayerBar.swift
//  Family Player
//

import SwiftUI

struct MiniPlayerBar: View {
    @Environment(PlaybackEngine.self) private var engine
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    let onTap: () -> Void

    var body: some View {
        if let song = engine.currentSong {
            switch placement {
            case .inline:
                inlineContent(song: song)
            default:
                expandedContent(song: song)
            }
        }
    }

    @ViewBuilder
    private func expandedContent(song: Song) -> some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                AlbumArtworkView(
                    cachePath: song.album?.artworkCachePath,
                    title: song.album?.title ?? song.title,
                    size: 36,
                    cornerRadius: 4
                )
                VStack(alignment: .leading, spacing: 1) {
                    Text(song.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text(song.album?.persona?.name ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                trailingControl
                Button {
                    Task { await engine.playNext() }
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    @ViewBuilder
    private func inlineContent(song: Song) -> some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                AlbumArtworkView(
                    cachePath: song.album?.artworkCachePath,
                    title: song.album?.title ?? song.title,
                    size: 28,
                    cornerRadius: 3
                )
                Text(song.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 8)
                trailingControl
            }
            .padding(.horizontal, 10)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    @ViewBuilder
    private var trailingControl: some View {
        if engine.isLoading {
            ProgressView().controlSize(.small)
        } else {
            Button {
                engine.togglePlayPause()
            } label: {
                Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
        }
    }
}
