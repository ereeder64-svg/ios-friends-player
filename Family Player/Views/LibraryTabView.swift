//
//  LibraryTabView.swift
//  Family Player
//

import SwiftUI
import SwiftData

struct LibraryTabView: View {
    // Passed down from MainTabView so this stack's own push state can stay
    // in sync with the shared cross-orientation section selection: tapping
    // Search/Personas/Albums/Songs pushes here AND records that choice in
    // sectionState (so rotating to landscape lands on the same section),
    // and rotating in FROM landscape with one of those four selected
    // pushes straight to it here too.
    let sectionState: SidebarDrawerState

    // Only these four are ever pushed onto Library's own stack -- Library
    // itself, and every non-Library-nested item (New/Playlists/Favorites/
    // Downloads), are handled by MainTabView's own tab selection instead.
    private var path: Binding<[SidebarItem]> {
        Binding(
            get: {
                guard let selection = sectionState.selection,
                      SidebarItem.nestedUnderLibraryTab.contains(selection) else {
                    return []
                }
                return [selection]
            },
            set: { newPath in
                sectionState.selection = newPath.last ?? .library
            }
        )
    }

    var body: some View {
        NavigationStack(path: path) {
            LibraryTabContent()
                .navigationDestination(for: SidebarItem.self) { item in
                    switch item {
                    case .search: SearchTabView()
                    case .personas: PersonasListView()
                    case .albums: AllAlbumsView()
                    case .songs: AllSongsView()
                    default: EmptyView()
                    }
                }
        }
    }
}

struct LibraryTabContent: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(LibraryScanner.self) private var scanner
    @Environment(ShareAccessCoordinator.self) private var coordinator
    @Environment(DownloadManager.self) private var downloads

    @Query private var allPersonas: [Persona]
    @Query private var allAlbums: [Album]
    @Query private var allSongs: [Song]

    private var albums: [Album] {
        allAlbums.filter { coordinator.connectedShareNames.contains($0.shareName) }
    }
    private var songs: [Song] {
        allSongs.filter { coordinator.connectedShareNames.contains($0.shareName) }
    }
    private var personas: [Persona] {
        allPersonas.filter { persona in
            (persona.albums ?? []).contains { coordinator.connectedShareNames.contains($0.shareName) }
        }
    }

    var body: some View {
        List {
            if scanner.progress.isScanning {
                Section {
                    ScanProgressRow(progress: scanner.progress)
                }
            } else if let lastError = scanner.progress.lastError {
                Section {
                    Label(lastError, systemImage: "wifi.slash")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

                Section("Browse") {
                    NavigationLink(value: SidebarItem.search) {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    NavigationLink(value: SidebarItem.personas) {
                        Label("Personas (\(personas.count))", systemImage: "person.2")
                    }
                    NavigationLink(value: SidebarItem.albums) {
                        Label("Albums (\(albums.count))", systemImage: "square.stack")
                    }
                    NavigationLink(value: SidebarItem.songs) {
                        Label("Songs (\(songs.count))", systemImage: "music.note")
                    }
                }

                Section("Setup") {
                    NavigationLink {
                        ShareManagementView()
                    } label: {
                        Label("Manage Shares", systemImage: "folder.badge.gearshape")
                    }
                    NavigationLink {
                        FavoritesSharingSettingsView()
                    } label: {
                        Label("Share My Favorites", systemImage: "person.2.circle")
                    }
                }

                Section("App Icon") {
                    AppIconPicker()
                }

                Section("Downloads") {
                    BulkDownloadMenuItems(songs: songs, label: "All Songs")
                    let downloaded = songs.filter { downloads.downloadedStableIDs.contains($0.stableID) }.count
                    Text("\(downloaded) of \(songs.count) songs downloaded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        Task { await scanner.scan(coordinator: coordinator, context: modelContext) }
                    } label: {
                        Label(scanner.progress.isScanning ? "Scanning\u{2026}" : "Refresh Library", systemImage: "arrow.clockwise")
                    }
                    .disabled(scanner.progress.isScanning)
                    Button(role: .destructive) {
                        LibraryScanner.clearArtworkCache()
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
