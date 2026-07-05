//
//  RootView.swift
//  Family Player
//

import SwiftUI
import SwiftData
import OSLog

private let deepLinkLog = Logger(subsystem: "com.luxrecta.Family-Player", category: "DeepLink")

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var coordinator = ShareAccessCoordinator()
    @State private var scanner = LibraryScanner()
    @State private var engine = PlaybackEngine()
    @State private var downloads = DownloadManager()
    @State private var hasCompletedSetup = false
    @State private var didResolve = false
    @State private var didKickOffInitialScan = false
    @State private var deepLinkAlbum: Album?

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
                        engine.modelContext = modelContext
                        downloads.coordinator = coordinator
                        if !didKickOffInitialScan {
                            didKickOffInitialScan = true
                            await scanner.scan(coordinator: coordinator, context: modelContext)
                        }
                        checkPendingAlbumDeepLink()
                    }
                    .sheet(item: $deepLinkAlbum) { album in
                        NavigationStack {
                            AlbumDetailView(album: album)
                        }
                        .environment(engine)
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
        .onOpenURL { url in
            deepLinkLog.debug("onOpenURL received: \(url.absoluteString, privacy: .public)")
            handleDeepLink(url)
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Widget album taps now go through OpenAlbumIntent (openAppWhenRun),
            // not a URL — the intent just foregrounds the app and stashes the
            // requested album id in shared UserDefaults. Pick it up whenever
            // we come back to the foreground, since Link-based onOpenURL
            // turned out not to be reliably firing from widget taps at all.
            if newPhase == .active {
                checkPendingAlbumDeepLink()
            }
        }
    }

    private func checkPendingAlbumDeepLink() {
        guard let defaults = AppGroupConstants.sharedDefaults(),
              let id = defaults.string(forKey: AppGroupConstants.Keys.pendingAlbumDeepLinkID),
              !id.isEmpty else { return }
        defaults.removeObject(forKey: AppGroupConstants.Keys.pendingAlbumDeepLinkID)
        deepLinkLog.debug("checkPendingAlbumDeepLink: found pending id='\(id, privacy: .public)'.")
        presentAlbum(withID: id)
    }

    // Widget recent-album thumbnails link back via
    // familyplayer://album?id=<shareName>|<relativePath> (Album.stableID).
    //
    // Deliberately not checking url.host here: Foundation's URL parser
    // doesn't reliably populate .host for custom (non-http/https) schemes,
    // so gating on it silently dropped every deep link.
    private func handleDeepLink(_ url: URL) {
        guard url.scheme?.caseInsensitiveCompare(AppGroupConstants.urlScheme) == .orderedSame else {
            deepLinkLog.error("handleDeepLink: scheme mismatch — got \(url.scheme ?? "nil", privacy: .public).")
            return
        }
        guard let idString = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "id" })?.value else {
            deepLinkLog.error("handleDeepLink: no 'id' query item in \(url.absoluteString, privacy: .public).")
            return
        }
        presentAlbum(withID: idString)
    }

    private func presentAlbum(withID idString: String) {
        let parts = idString.components(separatedBy: "|")
        guard parts.count == 2 else {
            deepLinkLog.error("presentAlbum: unexpected id format '\(idString, privacy: .public)'.")
            return
        }
        let shareName = parts[0]
        let relativePath = parts[1]
        var descriptor = FetchDescriptor<Album>(
            predicate: #Predicate { $0.shareName == shareName && $0.relativePath == relativePath }
        )
        descriptor.fetchLimit = 1
        let found = try? modelContext.fetch(descriptor).first
        if let found {
            deepLinkLog.debug("presentAlbum: requested id='\(idString, privacy: .public)' -> matched Album title='\(found.title, privacy: .public)'.")
        } else {
            deepLinkLog.error("presentAlbum: no Album matched shareName='\(shareName, privacy: .public)' relativePath='\(relativePath, privacy: .public)'.")
        }
        deepLinkAlbum = found
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
