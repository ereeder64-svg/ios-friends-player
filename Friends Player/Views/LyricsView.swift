//
//  LyricsView.swift
//  Friends Player
//

import SwiftUI
import SwiftData

struct LyricsView: View {
    let song: Song
    @Environment(ShareAccessCoordinator.self) private var coordinator
    @Environment(PlaybackEngine.self) private var engine

    @State private var lyrics: String?
    @State private var timedLines: [LyricsService.TimedLine]?
    @State private var isLoading = true
    @State private var lastLoadedSongID: String?

    private var isCurrentlyPlaying: Bool {
        engine.currentSong?.stableID == song.stableID
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 60)
            } else if let lines = timedLines {
                timedView(lines: lines)
            } else if let text = lyrics, !text.isEmpty {
                plainView(text: text)
            } else {
                ContentUnavailableView(
                    "No Lyrics",
                    systemImage: "text.alignleft",
                    description: Text("This song has no embedded lyrics.")
                )
                .padding(.top, 40)
            }
        }
        .task(id: song.stableID) {
            await loadIfNeeded()
        }
    }

    @ViewBuilder
    private func plainView(text: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(text)
                    .font(.title3)
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
    }

    @ViewBuilder
    private func timedView(lines: [LyricsService.TimedLine]) -> some View {
        let activeIdx = isCurrentlyPlaying ? indexAtTime(engine.currentTime, in: lines) : nil
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                        let isActive = (activeIdx == idx)
                        Text(line.text.isEmpty ? " " : line.text)
                            .font(.title3.weight(isActive ? .bold : .regular))
                            .foregroundStyle(isActive ? Color.primary : Color.secondary)
                            .opacity(isActive ? 1.0 : 0.55)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(idx)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if isCurrentlyPlaying {
                                    engine.seek(to: line.time)
                                }
                            }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
            .onChange(of: activeIdx) { _, newIdx in
                guard let newIdx else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(newIdx, anchor: .center)
                }
            }
        }
    }

    private func indexAtTime(_ time: TimeInterval, in lines: [LyricsService.TimedLine]) -> Int? {
        var idx: Int? = nil
        for (i, line) in lines.enumerated() {
            if line.time <= time {
                idx = i
            } else {
                break
            }
        }
        return idx
    }

    private func loadIfNeeded() async {
        if lastLoadedSongID == song.stableID { return }
        lastLoadedSongID = song.stableID
        isLoading = true
        lyrics = nil
        timedLines = nil

        if let cached = LyricsService.loadCached(for: song.stableID) {
            applyText(cached)
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
        if let extracted {
            applyText(extracted)
            song.hasLyrics = true
            try? song.modelContext?.save()
        }
        isLoading = false
    }

    private func applyText(_ text: String) {
        lyrics = text
        timedLines = LyricsService.parseTimedLyrics(text)
    }
}

struct LyricsSheet: View {
    let song: Song
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            LyricsView(song: song)
                .navigationTitle(song.displayTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}
