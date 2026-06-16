//
//  PlayShuffleButtons.swift
//  Family Player
//

import SwiftUI

struct PlayShuffleButtons: View {
    @Environment(PlaybackEngine.self) private var engine
    let songs: [Song]

    var body: some View {
        HStack(spacing: 12) {
            Button {
                Task { await engine.play(songs: songs, startingAt: 0) }
            } label: {
                Label("Play", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(songs.isEmpty)

            Button {
                Task { await engine.playShuffled(songs) }
            } label: {
                Label("Shuffle", systemImage: "shuffle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(songs.isEmpty)
        }
    }
}
