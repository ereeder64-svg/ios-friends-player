//
//  LibraryTabView.swift
//  Family Player
//

import SwiftUI
import SwiftData

struct LibraryTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(LibraryScanner.self) private var scanner
    @Environment(ShareAccessCoordinator.self) private var coordinator

    @Query private var personas: [Persona]
    @Query private var albums: [Album]
    @Query private var songs: [Song]

    var body: some View {
        NavigationStack {
            List {
                if scanner.progress.isScanning {
                    Section {
                        ScanProgressRow(progress: scanner.progress)
                    }
                }

                Section("Browse") {
                    NavigationLink {
                        SearchTabView()
                    } label: {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    NavigationLink {
                        PersonasListView()
                    } label: {
                        Label("Personas (\(personas.count))", systemImage: "person.2")
                    }
                    NavigationLink {
                        AllAlbumsView()
                    } label: {
                        Label("Albums (\(albums.count))", systemImage: "square.stack")
                    }
                    NavigationLink {
                        AllSongsView()
                    } label: {
                        Label("Songs (\(songs.count))", systemImage: "music.note")
                    }
                }

                Section("Setup") {
                    NavigationLink {
                        ShareManagementView()
                    } label: {
                        Label("Manage Shares", systemImage: "folder.badge.gearshape")
                    }
                }

                Section {
                    Button {
                        Task { await scanner.scan(coordinator: coordinator, context: modelContext) }
                    } label: {
                        Label(scanner.progress.isScanning ? "Scanning\u{2026}" : "Refresh Library", systemImage: "arrow.clockwise")
                    }
                    .disabled(scanner.progress.isScanning)
                    Button(role: .destructive) {
                        for album in albums { album.artworkCachePath = nil }
                        try? modelContext.save()
                        Task { await scanner.scan(coordinator: coordinator, context: modelContext) }
                    } label: {
                        Label("Reset Artwork Cache & Rescan", systemImage: "photo.badge.arrow.down")
                    }
                    .disabled(scanner.progress.isScanning)
                    Button(role: .destructive) {
                        LyricsService.clearAllCache()
                        for song in songs { song.hasLyrics = false }
                        try? modelContext.save()
                    } label: {
                        Label("Clear Lyrics Cache", systemImage: "text.badge.xmark")
                    }
                }

            }
            .navigationTitle("Library")
        }
    }
}

private struct ScanProgressRow: View {
    let progress: ScanProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                ProgressView()
                Text("Scanning library\u{2026}")
                    .font(.subheadline.weight(.medium))
            }
            if let share = progress.currentShare {
                Text(share)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if progress.totalCount > 0 {
                ProgressView(value: Double(progress.scannedCount), total: Double(max(progress.totalCount, 1)))
                Text("\(progress.scannedCount) of \(progress.totalCount)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
