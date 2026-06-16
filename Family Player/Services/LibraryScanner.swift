//
//  LibraryScanner.swift
//  Family Player
//

import Foundation
import SwiftData
import Observation
import AVFoundation
import UIKit

struct ScanProgress: Equatable {
    var isScanning: Bool = false
    var currentShare: String?
    var scannedCount: Int = 0
    var totalCount: Int = 0
    var lastError: String?
}

private struct SongWorkItem: Sendable, Hashable {
    let shareName: String
    let shareRoot: URL
    let songURL: URL
    let relativePath: String
    let albumFolderURL: URL
    let albumRelativePath: String
    let albumDisplayName: String
    let personaName: String
}

private struct SongMetadata: Sendable {
    var title: String
    var album: String?
    var trackNumber: Int?
    var duration: Double
    var hasLyrics: Bool
}

@MainActor
@Observable
final class LibraryScanner {

    var progress = ScanProgress()

    private let publicShareName = "Public Share"
    private let defaultPersona = "Eric Reeder"

    func scan(coordinator: ShareAccessCoordinator, context: ModelContext) async {
        guard !progress.isScanning else { return }
        progress.isScanning = true
        progress.scannedCount = 0
        progress.totalCount = 0
        progress.currentShare = nil
        progress.lastError = nil

        var startedScopes: [URL] = []
        defer {
            for url in startedScopes {
                url.stopAccessingSecurityScopedResource()
            }
            progress.isScanning = false
        }

        var allWorkItems: [SongWorkItem] = []
        var albumFoldersSeen: [String: URL] = [:]

        for (shareName, shareURL) in coordinator.resolvedURLs {
            progress.currentShare = shareName
            if shareURL.startAccessingSecurityScopedResource() {
                startedScopes.append(shareURL)
            }

            let rawItems = await Task.detached(priority: .userInitiated) { [shareName, shareURL, publicShareName = self.publicShareName, defaultPersona = self.defaultPersona] in
                Self.enumerateShare(
                    shareName: shareName,
                    shareURL: shareURL,
                    publicShareName: publicShareName,
                    defaultPersona: defaultPersona
                )
            }.value

            let items = Self.dedupe(rawItems)
            allWorkItems.append(contentsOf: items)

            for item in items {
                let key = "\(item.shareName)|\(item.albumRelativePath)"
                if albumFoldersSeen[key] == nil {
                    albumFoldersSeen[key] = item.albumFolderURL
                }
            }
        }

        progress.totalCount = allWorkItems.count

        for (idx, item) in allWorkItems.enumerated() {
            progress.scannedCount = idx
            progress.currentShare = item.shareName
            await processSong(item, context: context)
        }
        progress.scannedCount = allWorkItems.count

        await cacheArtwork(for: albumFoldersSeen, context: context)
        await pruneMissing(currentStableIDs: Set(allWorkItems.map(stableID)), context: context)
    }

    // MARK: - Enumeration (background)

    // Same (persona, album, filename) appearing at multiple folder depths in the
    // same share is treated as one song. Keep the shallowest path so the album
    // folder is more likely to contain the sidecar artwork.
    nonisolated private static func dedupe(_ items: [SongWorkItem]) -> [SongWorkItem] {
        var seen: [String: SongWorkItem] = [:]
        for item in items {
            let key = "\(item.personaName.lowercased())|\(item.albumDisplayName.lowercased())|\(item.songURL.lastPathComponent.lowercased())"
            if let existing = seen[key] {
                if item.relativePath.count < existing.relativePath.count {
                    seen[key] = item
                }
            } else {
                seen[key] = item
            }
        }
        return Array(seen.values)
    }

    nonisolated private static func enumerateShare(
        shareName: String,
        shareURL: URL,
        publicShareName: String,
        defaultPersona: String
    ) -> [SongWorkItem] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: shareURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var items: [SongWorkItem] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            guard url.pathExtension.lowercased() == "mp3" else { continue }

            let albumFolder = url.deletingLastPathComponent()
            let albumRelativePath = relativePath(of: albumFolder, base: shareURL)
            let songRelativePath = relativePath(of: url, base: shareURL)

            let (persona, album) = deriveMeta(
                shareName: shareName,
                albumFolderURL: albumFolder,
                shareURL: shareURL,
                publicShareName: publicShareName,
                defaultPersona: defaultPersona
            )

            items.append(SongWorkItem(
                shareName: shareName,
                shareRoot: shareURL,
                songURL: url,
                relativePath: songRelativePath,
                albumFolderURL: albumFolder,
                albumRelativePath: albumRelativePath,
                albumDisplayName: album,
                personaName: persona
            ))
        }
        return items
    }

    nonisolated private static func relativePath(of url: URL, base: URL) -> String {
        let basePath = base.standardizedFileURL.path
        let urlPath = url.standardizedFileURL.path
        if urlPath.hasPrefix(basePath) {
            var trimmed = String(urlPath.dropFirst(basePath.count))
            if trimmed.hasPrefix("/") { trimmed.removeFirst() }
            return trimmed
        }
        return url.lastPathComponent
    }

    nonisolated private static func deriveMeta(
        shareName: String,
        albumFolderURL: URL,
        shareURL: URL,
        publicShareName: String,
        defaultPersona: String
    ) -> (persona: String, album: String) {
        let albumFolderPath = albumFolderURL.standardizedFileURL.path
        let sharePath = shareURL.standardizedFileURL.path

        if albumFolderPath == sharePath {
            return (defaultPersona, shareName)
        }

        let folderName = albumFolderURL.lastPathComponent

        if shareName == publicShareName {
            if let range = folderName.range(of: " - ") {
                let persona = String(folderName[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                let album = String(folderName[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                return (persona.isEmpty ? folderName : persona,
                        album.isEmpty ? folderName : album)
            }
            return (folderName, folderName)
        }

        return (defaultPersona, folderName)
    }

    // MARK: - Per-song processing

    private func processSong(_ item: SongWorkItem, context: ModelContext) async {
        let url = item.songURL
        let id = stableID(item)

        let existing = fetchSong(stableID: id, context: context)
        let album = fetchOrCreateAlbum(item: item, context: context)

        let filenameTitle = Self.titleFromFilename(item.songURL.lastPathComponent)
        let filenameTrack = Self.trackNumberFromFilename(item.songURL.lastPathComponent)

        let shouldReadMetadata = Self.isLocallyAvailable(url: url)
            && !(existing?.metadataLoaded ?? false)

        let metadata = shouldReadMetadata ? await readMetadata(at: url) : nil
        let estimatedDuration = metadata == nil ? Self.estimatedDuration(at: url) : 0

        if let song = existing {
            song.album = album
            song.shareName = item.shareName
            song.relativePath = item.relativePath
            if let metadata {
                song.title = metadata.title
                song.trackNumber = metadata.trackNumber ?? filenameTrack
                song.duration = metadata.duration
                song.hasLyrics = metadata.hasLyrics
                song.metadataLoaded = true
            } else if !song.metadataLoaded {
                song.title = filenameTitle
                song.trackNumber = filenameTrack
                if song.duration <= 0, estimatedDuration > 0 {
                    song.duration = estimatedDuration
                }
            }
        } else {
            let song = Song(
                stableID: id,
                title: metadata?.title ?? filenameTitle,
                trackNumber: metadata?.trackNumber ?? filenameTrack,
                album: album,
                shareName: item.shareName,
                relativePath: item.relativePath,
                hasLyrics: metadata?.hasLyrics ?? false,
                duration: metadata?.duration ?? estimatedDuration
            )
            song.metadataLoaded = (metadata != nil)
            context.insert(song)
        }

        try? context.save()
    }

    nonisolated static func estimatedDuration(at url: URL) -> Double {
        let keys: Set<URLResourceKey> = [.totalFileSizeKey, .fileSizeKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        let size = values.totalFileSize ?? values.fileSize ?? 0
        guard size > 0 else { return 0 }
        // Assume 256 kbps average bitrate → 32,000 bytes/sec
        return Double(size) / 32000.0
    }

    nonisolated static func isLocallyAvailable(url: URL) -> Bool {
        let keys: Set<URLResourceKey> = [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return false }
        if values.isUbiquitousItem == true {
            return values.ubiquitousItemDownloadingStatus == .current
        }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private func stableID(_ item: SongWorkItem) -> String {
        "\(item.shareName)|\(item.relativePath)"
    }

    private func fetchSong(stableID: String, context: ModelContext) -> Song? {
        var descriptor = FetchDescriptor<Song>(
            predicate: #Predicate { $0.stableID == stableID }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func fetchOrCreateAlbum(item: SongWorkItem, context: ModelContext) -> Album {
        let shareName = item.shareName
        let albumRelPath = item.albumRelativePath
        let albumTitle = item.albumDisplayName
        let personaName = item.personaName

        var albumDescriptor = FetchDescriptor<Album>(
            predicate: #Predicate { $0.shareName == shareName && $0.relativePath == albumRelPath }
        )
        albumDescriptor.fetchLimit = 1
        if let existing = try? context.fetch(albumDescriptor).first {
            if existing.title != albumTitle {
                existing.title = albumTitle
            }
            return existing
        }

        let persona = fetchOrCreatePersona(name: personaName, context: context)
        let album = Album(
            title: albumTitle,
            persona: persona,
            shareName: shareName,
            relativePath: albumRelPath
        )
        context.insert(album)
        return album
    }

    private func fetchOrCreatePersona(name: String, context: ModelContext) -> Persona {
        var descriptor = FetchDescriptor<Persona>(
            predicate: #Predicate { $0.name == name }
        )
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let persona = Persona(name: name)
        context.insert(persona)
        return persona
    }

    // MARK: - Filename helpers

    nonisolated static func titleFromFilename(_ filename: String) -> String {
        var base = (filename as NSString).deletingPathExtension
        // Mac convention: "01, Song name" or "01 - Song name" — strip leading track digits
        if let match = base.range(of: #"^\s*\d+\s*[,.\-]\s*"#, options: .regularExpression) {
            base.removeSubrange(match)
        }
        return base.trimmingCharacters(in: .whitespaces)
    }

    nonisolated static func trackNumberFromFilename(_ filename: String) -> Int? {
        let base = (filename as NSString).deletingPathExtension
        if let match = base.range(of: #"^\s*(\d+)"#, options: .regularExpression),
           let digits = Int(base[match].trimmingCharacters(in: .whitespaces)) {
            return digits
        }
        return nil
    }

    // MARK: - AVAsset metadata (background)

    private func readMetadata(at url: URL) async -> SongMetadata? {
        await Task.detached(priority: .utility) { () -> SongMetadata? in
            let asset = AVURLAsset(url: url)
            do {
                let duration = try await asset.load(.duration)
                let commonItems = try await asset.load(.commonMetadata)
                let id3Items = (try? await asset.loadMetadata(for: .id3Metadata)) ?? []

                let title = await stringValue(commonItems, key: .commonKeyTitle)
                    ?? Self.titleFromFilename(url.lastPathComponent)
                let album = await stringValue(commonItems, key: .commonKeyAlbumName)
                let trackString = await stringValue(id3Items, identifier: .id3MetadataTrackNumber)
                let trackNumber = trackString.flatMap { Int($0.split(separator: "/").first.map(String.init) ?? $0) }

                let hasLyrics = id3Items.contains { item in
                    item.identifier == .id3MetadataUnsynchronizedLyric
                }

                return SongMetadata(
                    title: title,
                    album: album,
                    trackNumber: trackNumber,
                    duration: CMTimeGetSeconds(duration),
                    hasLyrics: hasLyrics
                )
            } catch {
                return nil
            }
        }.value
    }

    // MARK: - iCloud materialization

    private func materializeIfNeeded(url: URL) async {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
        guard let values = try? url.resourceValues(forKeys: keys),
              values.isUbiquitousItem == true else { return }

        if values.ubiquitousItemDownloadingStatus == .current { return }

        try? fm.startDownloadingUbiquitousItem(at: url)
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if let v = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]),
               v.ubiquitousItemDownloadingStatus == .current {
                return
            }
        }
    }

    // MARK: - Artwork caching

    private func cacheArtwork(for albumFolders: [String: URL], context: ModelContext) async {
        let cacheDir = Self.artworkCacheDirectory()
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        for (albumKey, folderURL) in albumFolders {
            let parts = albumKey.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 2 else { continue }
            let shareName = parts[0]
            let relPath = parts[1]

            var descriptor = FetchDescriptor<Album>(
                predicate: #Predicate { $0.shareName == shareName && $0.relativePath == relPath }
            )
            descriptor.fetchLimit = 1
            guard let album = try? context.fetch(descriptor).first else { continue }

            if let cached = album.artworkCachePath,
               FileManager.default.fileExists(atPath: cached) {
                continue
            }

            let folderName: String = album.relativePath.isEmpty
                ? album.shareName
                : folderURL.lastPathComponent
            let safeRel = album.relativePath.replacingOccurrences(of: "/", with: "_")
            let sidecar = folderURL.appendingPathComponent("\(folderName).png")
            let destSidecar = cacheDir.appendingPathComponent("\(album.shareName)__\(safeRel).png")

            if await Self.coordinatedCopy(from: sidecar, to: destSidecar) {
                album.artworkCachePath = destSidecar.path
                continue
            }

            if let fallback = await findFallbackArtwork(in: folderURL) {
                let destFallback = cacheDir.appendingPathComponent("\(album.shareName)__\(safeRel).\(fallback.pathExtension)")
                if await Self.coordinatedCopy(from: fallback, to: destFallback) {
                    album.artworkCachePath = destFallback.path
                }
            }
        }
        try? context.save()
    }

    nonisolated static func coordinatedCopy(from source: URL, to dest: URL) async -> Bool {
        try? FileManager.default.startDownloadingUbiquitousItem(at: source)

        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            DispatchQueue.global(qos: .utility).async {
                let coordinator = NSFileCoordinator()
                var coordError: NSError?
                var success = false

                coordinator.coordinate(
                    readingItemAt: source,
                    options: [],
                    error: &coordError
                ) { coordinatedURL in
                    guard FileManager.default.fileExists(atPath: coordinatedURL.path) else { return }
                    _ = try? FileManager.default.removeItem(at: dest)
                    do {
                        try FileManager.default.copyItem(at: coordinatedURL, to: dest)
                        success = true
                    } catch {
                        success = false
                    }
                }
                continuation.resume(returning: success)
            }
        }
    }

    private func findFallbackArtwork(in folder: URL) async -> URL? {
        let exts: Set<String> = ["png", "jpg", "jpeg", "webp"]
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return nil }
        return contents.first { exts.contains($0.pathExtension.lowercased()) }
    }

    nonisolated static func artworkCacheDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("ArtworkCache", isDirectory: true)
    }

    // MARK: - Pruning

    private func pruneMissing(currentStableIDs: Set<String>, context: ModelContext) async {
        let descriptor = FetchDescriptor<Song>()
        guard let songs = try? context.fetch(descriptor) else { return }
        for song in songs where !currentStableIDs.contains(song.stableID) {
            context.delete(song)
        }
        let albumDescriptor = FetchDescriptor<Album>()
        if let albums = try? context.fetch(albumDescriptor) {
            for album in albums where album.songs.isEmpty {
                context.delete(album)
            }
        }
        let personaDescriptor = FetchDescriptor<Persona>()
        if let personas = try? context.fetch(personaDescriptor) {
            for persona in personas where persona.albums.isEmpty {
                context.delete(persona)
            }
        }
        try? context.save()
    }
}

private func stringValue(_ items: [AVMetadataItem], key: AVMetadataKey) async -> String? {
    let filtered = AVMetadataItem.metadataItems(from: items, withKey: key, keySpace: .common)
    guard let first = filtered.first else { return nil }
    return try? await first.load(.stringValue)
}

private func stringValue(_ items: [AVMetadataItem], identifier: AVMetadataIdentifier) async -> String? {
    let filtered = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier)
    guard let first = filtered.first else { return nil }
    return try? await first.load(.stringValue)
}
