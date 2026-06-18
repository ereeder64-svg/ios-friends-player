//
//  PlayShuffleButtons.swift
//  Family Player
//

import SwiftUI

struct PlayShuffleButtons: View {
    @Environment(PlaybackEngine.self) private var engine
    let songs: [Song]

    private var currentInScope: Bool {
        guard let current = engine.currentSong else { return false }
        return songs.contains { $0.stableID == current.stableID }
    }

    private var showPause: Bool {
        currentInScope && engine.isPlaying
    }

    var body: some View {
        HStack(spacing: 12) {
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
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(songs.isEmpty)

            shuffleButton
        }
    }

    @ViewBuilder
    private var shuffleButton: some View {
        if engine.shuffleEnabled {
            Button {
                engine.shuffleEnabled = false
            } label: {
                Label("Shuffle", systemImage: "shuffle")
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
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(songs.isEmpty)
        }
    }
}
