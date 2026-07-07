//
//  PlayShuffleButtons.swift
//  Family Player
//

import SwiftUI

struct PlayShuffleButtons: View {
    @Environment(PlaybackEngine.self) private var engine
    let songs: [Song]
    /// When non-nil, an "Add" pill is shown to the right of Shuffle and the
    /// Play/Shuffle buttons shrink slightly to make room for it. Used by
    /// PlaylistDetailView to let the user pick songs from the whole library.
    var onAdd: (() -> Void)? = nil

    private var currentInScope: Bool {
        guard let current = engine.currentSong else { return false }
        return songs.contains { $0.stableID == current.stableID }
    }

    private var showPause: Bool {
        currentInScope && engine.isPlaying
    }

    private var buttonFont: Font {
        onAdd != nil ? .subheadline : .body
    }

    var body: some View {
        HStack(spacing: onAdd != nil ? 8 : 12) {
            Button {
                if currentInScope {
                    engine.togglePlayPause()
                } else {
                    Task { await engine.play(songs: songs, startingAt: 0) }
                }
            } label: {
                Label(
                    showPause ? "Pause" : "Play",
                    systemImage: showPause ? "pause.fill" : "play.fill"
                )
                .font(buttonFont)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(songs.isEmpty)

            shuffleButton

            if let onAdd {
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            }
        }
    }

    @ViewBuilder
    private var shuffleButton: some View {
        if engine.shuffleEnabled {
            Button {
                engine.shuffleEnabled = false
            } label: {
                Label("Shuffle", systemImage: "shuffle")
                    .font(buttonFont)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button {
                if currentInScope {
                    engine.shuffleEnabled = true
                } else {
                    Task { await engine.playShuffled(songs) }
                }
            } label: {
                Label("Shuffle", systemImage: "shuffle")
                    .font(buttonFont)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(songs.isEmpty)
        }
    }
}
