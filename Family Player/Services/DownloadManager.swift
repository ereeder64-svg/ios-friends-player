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

    nonisolated static func downloadDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Downloads", isDirectory: true)
    }

    private nonisolated static func destinationURL(for song: Song) -> URL {
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

        song.downloadCachePath = destURL.path
        song.downloadedAt = Date()
        if let attrs = try? FileManager.default.attributesOfItem(atPath: destURL.path),
           let size = attrs[.size] as? Int64 {
            song.downloadSizeBytes = size
        }
        try? song.modelContext?.save()
    }

    func remove(song: Song) {
        scheduledStableIDs.remove(song.stableID)
        if let path = song.downloadCachePath {
            try? FileManager.default.removeItem(atPath: path)
        }
        song.downloadCachePath = nil
        song.downloadedAt = nil
        song.downloadSizeBytes = 0
        try? song.modelContext?.save()
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
        let descriptor = FetchDescriptor<Song>(
            predicate: #Predicate { $0.downloadCachePath != nil }
        )
        if let downloaded = try? context.fetch(descriptor) {
            for song in downloaded {
                remove(song: song)
            }
        }
        let dir = Self.downloadDirectory()
        if let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for f in files { try? FileManager.default.removeItem(at: f) }
        }
    }

    func totalDownloadedBytes(context: ModelContext) -> Int64 {
        let descriptor = FetchDescriptor<Song>(
            predicate: #Predicate { $0.downloadCachePath != nil }
        )
        guard let songs = try? context.fetch(descriptor) else { return 0 }
        return songs.reduce(0) { $0 + $1.downloadSizeBytes }
    }

    func isDownloading(_ song: Song) -> Bool {
        inFlightStableIDs.contains(song.stableID)
    }
}
