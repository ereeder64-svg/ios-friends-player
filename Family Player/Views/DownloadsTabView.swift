//
//  DownloadsTabView.swift
//  Family Player
//

import SwiftUI
import SwiftData

struct DownloadsTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(DownloadManager.self) private var downloads
    @Query(
        filter: #Predicate<Song> { $0.downloadCachePath != nil },
        sort: \Song.title
    )
    private var downloadedSongs: [Song]
    @State private var searchText = ""
    @State private var showClearAllAlert = false

    private var filteredSongs: [Song] {
        let base: [Song]
        if searchText.isEmpty {
            base = Array(downloadedSongs)
        } else {
            let q = searchText.lowercased()
            base = downloadedSongs.filter { song in
                song.title.lowercased().contains(q) ||
                (song.album?.title.lowercased().contains(q) ?? false) ||
                (song.album?.persona?.name.lowercased().contains(q) ?? false)
            }
        }
        return base.sortedByAlbumThenTitle()
    }

    private var totalBytes: Int64 {
        downloadedSongs.reduce(0) { $0 + $1.downloadSizeBytes }
    }

    private var totalSizeText: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    PlayShuffleButtons(songs: filteredSongs)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    if !downloadedSongs.isEmpty {
                        HStack {
                            Text("\(downloadedSongs.count) song\(downloadedSongs.count == 1 ? "" : "s")")
                                .font(.footnote.weight(.semibold))
                            Spacer()
                            Text(totalSizeText)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 20)
                    }

                    SongListSection(songs: filteredSongs)
                }
                .padding(.bottom, 16)
            }
            .navigationTitle("Downloads")
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search downloads"
            )
            .toolbar {
                if !downloadedSongs.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .destructive) {
                            showClearAllAlert = true
                        } label: {
                            Text("Clear All")
                        }
                    }
                }
            }
            .alert("Clear All Downloads?", isPresented: $showClearAllAlert) {
                Button("Clear All", role: .destructive) {
                    downloads.clearAll(context: modelContext)
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Removes every downloaded song from this device. The songs remain in your iCloud share and can be re-downloaded later.")
            }
            .overlay {
                if downloadedSongs.isEmpty {
                    ContentUnavailableView(
                        "No Downloads",
                        systemImage: "arrow.down.circle",
                        description: Text("Open a song's menu or use the album menu to download.")
                    )
                } else if filteredSongs.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
    }
}
