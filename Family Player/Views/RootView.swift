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
            hasCompletedSetup = !coordinator.resolvedURLs.isEmpty
        }
    }
}
