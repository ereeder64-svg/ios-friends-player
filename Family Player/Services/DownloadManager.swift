//
//  DownloadManager.swift
//  Family Player
//

import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class DownloadManager {

    private(set) var inFlightStableIDs: Set<String> = []
    private var scheduledStableIDs: Set<String> = []
    weak var coordinator: ShareAccessCoordinator?
    var modelContext: ModelContext?

    // Song.downloadCachePath is computed from on-disk presence (not a
    // stored/synced SwiftData property -- see Song.swift), which means
    // SwiftUI has no persisted-attribute change to react to when a
    // download/removal completes: the file changes, but nothing about the
    // model itself does. This observable set is the actual reactivity
    // signal views should key off of for "is this song downloaded" UI.
    private(set) var downloadedStableIDs: Set<String> = []

    /// Populates downloadedStableIDs from what's actually on disk right now.
    /// Call once at launch (after modelContext is set) so already-downloaded
    /// songs from a previous session show correctly immediately.
    func refreshDownloadedStableIDs() {
        guard let modelContext,
              let songs = try? modelContext.fetch(FetchDescriptor<Song>()) else { return }
        downloadedStableIDs = Set(songs.filter { $0.downloadCachePath != nil }.map(\.stableID))
    }

    nonisolated static func downloadDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Downloads", isDirectory: true)
    }

    nonisolated static func destinationURL(for song: Song) -> URL {
        let dir = downloadDirectory()
        let safeRel = song.relativePath.replacingOccurrences(of: "/", with: "_")
        return dir.appendingPathComponent("\(song.shareName)__\(safeRel)")
    }

    // MARK: - Single song

    func download(song: Song) async {
        guard !inFlightStableIDs.contains(song.stableID) else { return }
        guard song.downloadCachePath == nil else { return }
        guard let coordinator,
              let shareURL = coordinator.url(for: song.shareName) else { return }

        scheduledStableIDs.insert(song.stableID)
        inFlightStableIDs.insert(song.stableID)
        defer { inFlightStableIDs.remove(song.stableID) }

        let didStart = shareURL.startAccessingSecurityScopedResource()
        defer { if didStart { shareURL.stopAccessingSecurityScopedResource() } }

        let sourceURL = shareURL.appendingPathComponent(song.relativePath)
        let dir = Self.downloadDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let destURL = Self.destinationURL(for: song)

        guard await LibraryScanner.coordinatedCopy(from: sourceURL, to: destURL) else {
            scheduledStableIDs.remove(song.stableID)
            return
        }

        // If the user requested removal while this was downloading, honor it:
        // delete the file we just wrote instead of recording it as downloaded.
        if !scheduledStableIDs.contains(song.stableID) {
            try? FileManager.default.removeItem(at: destURL)
            return
        }
        scheduledStableIDs.remove(song.stableID)
        // downloadCachePath/downloadedAt/downloadSizeBytes are computed from
        // this file's on-disk presence (see Song.swift) -- nothing to set,
        // but bump the observable set so SwiftUI actually notices.
        downloadedStableIDs.insert(song.stableID)
    }

    func remove(song: Song) {
        scheduledStableIDs.remove(song.stableID)
        if let path = song.downloadCachePath {
            try? FileManager.default.removeItem(atPath: path)
        }
        downloadedStableIDs.remove(song.stableID)
    }

    // MARK: - Bulk

    func download(songs: [Song]) async {
        for song in songs where song.downloadCachePath == nil {
            scheduledStableIDs.insert(song.stableID)
        }
        for song in songs {
            // Cancellation: if remove() was called for this song, skip it.
            guard scheduledStableIDs.contains(song.stableID) else { continue }
            guard song.downloadCachePath == nil else {
                scheduledStableIDs.remove(song.stableID)
                continue
            }
            await download(song: song)
        }
    }

    func remove(songs: [Song]) {
        for song in songs {
            scheduledStableIDs.remove(song.stableID)
        }
        for song in songs where song.downloadCachePath != nil {
            remove(song: song)
        }
    }

    func clearAll(context: ModelContext) {
        // downloadCachePath is now computed from on-disk presence, so it
        // can't be used in a #Predicate -- fetch everything and filter in
        // Swift instead. (Simplest, and this is only user-initiated.)
        if let allSongs = try? context.fetch(FetchDescriptor<Song>()) {
            for song in allSongs where song.downloadCachePath != nil {
                remove(song: song)
            }
        }
        let dir = Self.downloadDirectory()
        if let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for f in files { try? FileManager.default.removeItem(at: f) }
        }
    }

    /// Total size of everything actually downloaded to this device.
    func totalDownloadedBytes() -> Int64 {
        let dir = Self.downloadDirectory()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        return files.reduce(Int64(0)) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return total + Int64(size)
        }
    }

    func isDownloading(_ song: Song) -> Bool {
        inFlightStableIDs.contains(song.stableID)
    }
}
