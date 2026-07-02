//
//  RootView.swift
//  Family Player
//

import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var coordinator = ShareAccessCoordinator()
    @State private var scanner = LibraryScanner()
    @State private var engine = PlaybackEngine()
    @State private var downloads = DownloadManager()
    @State private var hasCompletedSetup = false
    @State private var didResolve = false
    @State private var didKickOffInitialScan = false

    var body: some View {
        Group {
            if hasCompletedSetup {
                MainTabView()
                    .environment(coordinator)
                    .environment(scanner)
                    .environment(engine)
                    .environment(downloads)
                    .task {
                        engine.coordinator = coordinator
                        downloads.coordinator = coordinator
                        guard !didKickOffInitialScan else { return }
                        didKickOffInitialScan = true
                        await scanner.scan(coordinator: coordinator, context: modelContext)
                    }
            } else {
                SetupView(coordinator: coordinator) {
                    hasCompletedSetup = true
                }
            }
        }
        .onAppear {
            guard !didResolve else { return }
            didResolve = true
            _ = coordinator.resolveAll(context: modelContext)
            purgeOrphanedPlaylistEntries()
            hasCompletedSetup = !coordinator.resolvedURLs.isEmpty
        }
    }

    // PlaylistEntry has no inverse relationship on Song, so previous sessions'
    // song deletions may have left entries whose `song` accessor crashes on read.
    // Purge those before any view tries to read them.
    private func purgeOrphanedPlaylistEntries() {
        let descriptor = FetchDescriptor<PlaylistEntry>(
            predicate: #Predicate<PlaylistEntry> { $0.song?.stableID == nil }
        )
        guard let orphans = try? modelContext.fetch(descriptor), !orphans.isEmpty else { return }
        for entry in orphans {
            modelContext.delete(entry)
        }
        try? modelContext.save()
    }
}
