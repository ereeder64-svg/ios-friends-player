//
//  SearchTabView.swift
//  Family Player
//

import SwiftUI
import SwiftData

struct SearchTabView: View {
    @Query(sort: \Song.title) private var allSongs: [Song]
    @State private var searchText = ""
    @State private var searchLyrics = false
    @State private var lyricHits: Set<String> = []
    @State private var isSearchingLyrics = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Toggle(isOn: $searchLyrics) {
                    Label("Search lyrics", systemImage: "text.alignleft")
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)

                if searchText.isEmpty {
                    ContentUnavailableView(
                        "Search Your Library",
                        systemImage: "magnifyingglass",
                        description: Text(searchLyrics
                            ? "Find songs by lyric phrases you remember. Lyric search only covers songs you've played or viewed lyrics for."
                            : "Find songs by title, persona, or album.")
                    )
                    .padding(.top, 60)
                } else if isSearchingLyrics {
                    ProgressView()
                        .padding(.top, 60)
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .padding(.top, 40)
                } else {
                    PlayShuffleButtons(songs: results)
                        .padding(.horizontal, 20)
                    SongListSection(songs: results)
                    SongsCountFooter(songs: results)
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                }
            }
            .padding(.bottom, 16)
        }
        .navigationTitle("Search")
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: searchLyrics ? "Search lyrics" : "Songs, personas, albums"
        )
        .task(id: searchKey) {
            await runLyricSearchIfNeeded()
        }
    }

    private var searchKey: String { "\(searchLyrics):\(searchText)" }

    private var results: [Song] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        if searchLyrics {
            return allSongs.filter { lyricHits.contains($0.stableID) }
        } else {
            return allSongs.filter { song in
                song.title.lowercased().contains(q) ||
                (song.album?.title.lowercased().contains(q) ?? false) ||
                (song.album?.persona?.name.lowercased().contains(q) ?? false)
            }
        }
    }

    private func runLyricSearchIfNeeded() async {
        guard searchLyrics else {
            lyricHits = []
            isSearchingLyrics = false
            return
        }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            lyricHits = []
            isSearchingLyrics = false
            return
        }
        isSearchingLyrics = true
        let hits = await Task.detached(priority: .userInitiated) {
            LyricsService.searchLyrics(query: q)
        }.value
        if searchKey == "\(searchLyrics):\(searchText)" {
            lyricHits = hits
            isSearchingLyrics = false
        }
    }
}
