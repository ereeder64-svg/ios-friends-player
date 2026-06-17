//
//  LyricsView.swift
//  Family Player
//

import SwiftUI
import SwiftData

struct LyricsView: View {
    let song: Song
    @Environment(ShareAccessCoordinator.self) private var coordinator

    @State private var lyrics: String?
    @State private var isLoading = true
    @State private var lastLoadedSongID: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 60)
                } else if let text = lyrics, !text.isEmpty {
                    Text(text)
                        .font(.title3)
                        .lineSpacing(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ContentUnavailableView(
                        "No Lyrics",
                        systemImage: "text.alignleft",
                        description: Text("This song has no embedded lyrics.")
                    )
                    .padding(.top, 40)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .task(id: song.stableID) {
            await loadIfNeeded()
        }
    }

    private func loadIfNeeded() async {
        if lastLoadedSongID == song.stableID { return }
        lastLoadedSongID = song.stableID
        isLoading = true
        lyrics = nil

        if let cached = LyricsService.loadCached(for: song.stableID) {
            lyrics = cached
            isLoading = false
            return
        }

        let songURL: URL?
        if let path = song.downloadCachePath,
           FileManager.default.fileExists(atPath: path) {
            songURL = URL(fileURLWithPath: path)
        } else if let shareURL = coordinator.url(for: song.shareName) {
            songURL = shareURL.appendingPathComponent(song.relativePath)
        } else {
            songURL = nil
        }

        guard let url = songURL else {
            isLoading = false
            return
        }

        let id = song.stableID
        let extracted = await LyricsService.extract(from: url, stableID: id)
        guard lastLoadedSongID == id else { return }
        lyrics = extracted
        if extracted != nil {
            song.hasLyrics = true
            try? song.modelContext?.save()
        }
        isLoading = false
    }
}

struct LyricsSheet: View {
    let song: Song
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            LyricsView(song: song)
                .navigationTitle(song.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}
