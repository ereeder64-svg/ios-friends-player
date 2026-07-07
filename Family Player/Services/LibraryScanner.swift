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
        // Only shares whose security scope actually started this pass are
        // eligible for pruning below. A share that fails to (re)gain access
        // on a given launch would otherwise enumerate zero items and look
        // "missing", causing pruneMissing to wrongly delete everything in
        // it — including albums that are still very much there.
        var scannedShareNames: Set<String> = []

        for (shareName, shareURL) in coordinator.resolvedURLs {
            progress.currentShare = shareName
            guard shareURL.startAccessingSecurityScopedResource() else {
                continue
            }
            startedScopes.append(shareURL)
            scannedShareNames.insert(shareName)

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
        await cachePersonaArtwork(shareRoots: coordinator.resolvedURLs, context: context)
        await pruneMissing(
            currentStableIDs: Set(allWorkItems.map(stableID)),
            scannedShareNames: scannedShareNames,
            context: context
        )
        mergeDuplicateLibraryEntries(context: context)
    }

    // MARK: - Dedup (self-healing for legacy duplicate records)

    // Earlier bugs (a device's first scan racing ahead of CloudKit's
    // initial import, and a ModelContainer store collision that corrupted
    // saves mid-write) both had windows where the same Persona/Album/Song
    // could get inserted more than once before app-level dedup (fetch by
    // natural key before insert) had a chance to see the earlier row. Those
    // duplicates already made it into CloudKit as genuinely separate
    // records, so a fresh local install just re-downloads all of them --
    // no amount of fetch-before-insert logic at scan time can prevent that,
    // since CloudKit itself has two distinct records for the same song.
    // This merges any duplicates found by natural key back down to one,
    // preserving favorite/play-history/playlist-membership state, and runs
    // after every scan so it keeps self-healing as old duplicates continue
    // trickling in from CloudKit.
    private func mergeDuplicateLibraryEntries(context: ModelContext) {
        mergeDuplicatePersonas(context: context)
        mergeDuplicateAlbums(context: context)
        mergeDuplicateSongs(context: context)
        try? context.save()
    }

    // IMPORTANT: winner selection across all three merge functions below
    // must be a deterministic total order -- given the SAME set of
    // duplicate records (which is what both devices see once CloudKit has
    // fully synced them), every device must compute the SAME winner.
    // `Array.max(by:)` only compares pairwise and silently falls back to
    // whatever order `context.fetch()` happened to return for ties, and
    // that local fetch order is not guaranteed to match across devices.
    // If device A picks copy X as the winner and device B (fetching the
    // exact same two duplicate rows) picks copy Y, each device deletes the
    // OTHER's winner on its next scan -- a tug-of-war that never
    // converges, and any favorite/play-history/playlist state applied to
    // "the losing" copy on one device can vanish when that device's
    // dedup pass later decides its copy lost. Sorting by a synced,
    // content-derived tiebreak (firstSeenAt / dateAddedToLibrary) instead
    // of object identity fixes that: once the tiebreak value itself has
    // synced, every device agrees on the winner.
    private func mergeDuplicatePersonas(context: ModelContext) {
        guard let personas = try? context.fetch(FetchDescriptor<Persona>()) else { return }
        var groups: [String: [Persona]] = [:]
        for persona in personas {
            groups[persona.name.lowercased(), default: []].append(persona)
        }
        for group in groups.values where group.count > 1 {
            let ranked = group.sorted { a, b in
                let countA = a.albums?.count ?? 0
                let countB = b.albums?.count ?? 0
                if countA != countB { return countA > countB }
                return a.firstSeenAt < b.firstSeenAt
            }
            guard let winner = ranked.first else { continue }
            for loser in group where loser.persistentModelID != winner.persistentModelID {
                for album in loser.albums ?? [] {
                    album.persona = winner
                }
                context.delete(loser)
            }
        }
    }

    private func mergeDuplicateAlbums(context: ModelContext) {
        guard let albums = try? context.fetch(FetchDescriptor<Album>()) else { return }
        var groups: [String: [Album]] = [:]
        for album in albums {
            groups[album.stableID, default: []].append(album)
        }
        for group in groups.values where group.count > 1 {
            let ranked = group.sorted { a, b in
                let countA = a.songs?.count ?? 0
                let countB = b.songs?.count ?? 0
                if countA != countB { return countA > countB }
                return a.firstSeenAt < b.firstSeenAt
            }
            guard let winner = ranked.first else { continue }
            for loser in group where loser.persistentModelID != winner.persistentModelID {
                for song in loser.songs ?? [] {
                    song.album = winner
                }
                context.delete(loser)
            }
        }
    }

    private func mergeDuplicateSongs(context: ModelContext) {
        guard let songs = try? context.fetch(FetchDescriptor<Song>()) else { return }
        var groups: [String: [Song]] = [:]
        for song in songs {
            groups[song.stableID, default: []].append(song)
        }
        func score(_ song: Song) -> Int {
            (song.hasBeenPlayed ? 4 : 0) + (song.isFavorite ? 2 : 0) + (song.metadataLoaded ? 1 : 0)
        }
        for group in groups.values where group.count > 1 {
            let ranked = group.sorted { a, b in
                let scoreA = score(a)
                let scoreB = score(b)
                if scoreA != scoreB { return scoreA > scoreB }
                return a.dateAddedToLibrary < b.dateAddedToLibrary
            }
            guard let winner = ranked.first else { continue }
            let winnerPlaylistIDs = Set((winner.playlistEntries ?? []).compactMap { $0.playlist?.persistentModelID })

            for loser in group where loser.persistentModelID != winner.persistentModelID {
                // Preserve favorite/play-history state before discarding the loser.
                winner.isFavorite = winner.isFavorite || loser.isFavorite
                winner.hasBeenPlayed = winner.hasBeenPlayed || loser.hasBeenPlayed
                winner.playCount = max(winner.playCount, loser.playCount)
                if let loserPlayedAt = loser.lastPlayedAt,
                   (winner.lastPlayedAt ?? .distantPast) < loserPlayedAt {
                    winner.lastPlayedAt = loserPlayedAt
                }
                if !winner.metadataLoaded && loser.metadataLoaded {
                    winner.title = loser.title
                    winner.trackNumber = loser.trackNumber
                    winner.duration = loser.duration
                    winner.hasLyrics = loser.hasLyrics
                    winner.metadataLoaded = true
                }

                // Re-point playlist membership instead of losing it, but
                // don't create a second entry in a playlist that already
                // has the winner.
                for entry in loser.playlistEntries ?? [] {
                    if let playlistID = entry.playlist?.persistentModelID,
                       winnerPlaylistIDs.contains(playlistID) {
                        context.delete(entry)
                    } else {
                        entry.song = winner
                    }
                }

                context.delete(loser)
            }
        }
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

            // artworkCachePath is computed from on-disk presence (see
            // Album.swift), so this already means "we have a local copy".
            if album.artworkCachePath != nil {
                continue
            }

            let folderName: String = album.relativePath.isEmpty
                ? album.shareName
                : folderURL.lastPathComponent
            let safeRel = album.relativePath.replacingOccurrences(of: "/", with: "_")
            let sidecar = folderURL.appendingPathComponent("\(folderName).png")
            let destSidecar = cacheDir.appendingPathComponent("\(album.shareName)__\(safeRel).png")

            if await Self.coordinatedCopy(from: sidecar, to: destSidecar) {
                continue
            }

            if let fallback = await findFallbackArtwork(in: folderURL) {
                let destFallback = cacheDir.appendingPathComponent("\(album.shareName)__\(safeRel).\(fallback.pathExtension)")
                _ = await Self.coordinatedCopy(from: fallback, to: destFallback)
            }
        }
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

    /// Deletes every locally cached artwork file on this device. Since
    /// artworkCachePath is now computed from on-disk presence (not a synced
    /// property), "resetting" it just means removing the actual files --
    /// the next scan will re-copy them fresh.
    nonisolated static func clearArtworkCache() {
        let dir = artworkCacheDirectory()
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for f in files { try? FileManager.default.removeItem(at: f) }
    }

    // MARK: - Persona artwork
    //
    // Mac player convention: each share may contain an "Artists" folder with
    // "<PersonaName>.png" files. Look in the share root and one subfolder deep.
    private func cachePersonaArtwork(shareRoots: [String: URL], context: ModelContext) async {
        let descriptor = FetchDescriptor<Persona>()
        guard let personas = try? context.fetch(descriptor), !personas.isEmpty else { return }
        let cacheDir = Self.artworkCacheDirectory()
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let fm = FileManager.default
        for persona in personas {
            // artworkCachePath is computed from on-disk presence.
            if persona.artworkCachePath != nil {
                continue
            }
            let safeName = persona.name.replacingOccurrences(of: "/", with: "_")
            let dest = cacheDir.appendingPathComponent("_persona_\(safeName).png")

            var candidates: [URL] = []
            for (_, shareURL) in shareRoots {
                candidates.append(shareURL.appendingPathComponent("Artists/\(persona.name).png"))
                if let entries = try? fm.contentsOfDirectory(at: shareURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
                    for entry in entries {
                        let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                        if isDir {
                            candidates.append(entry.appendingPathComponent("Artists/\(persona.name).png"))
                        }
                    }
                }
            }

            for candidate in candidates {
                if await Self.coordinatedCopy(from: candidate, to: dest) {
                    break
                }
            }
        }
    }

    // MARK: - Pruning

    private func pruneMissing(currentStableIDs: Set<String>, scannedShareNames: Set<String>, context: ModelContext) async {
        let descriptor = FetchDescriptor<Song>()
        guard let songs = try? context.fetch(descriptor) else { return }
        for song in songs
        where scannedShareNames.contains(song.shareName) && !currentStableIDs.contains(song.stableID) {
            let doomedID = song.stableID
            let entryDescriptor = FetchDescriptor<PlaylistEntry>(
                predicate: #Predicate<PlaylistEntry> { $0.song?.stableID == doomedID }
            )
            if let entries = try? context.fetch(entryDescriptor) {
                for entry in entries {
                    context.delete(entry)
                }
            }
            context.delete(song)
        }
        let albumDescriptor = FetchDescriptor<Album>()
        if let albums = try? context.fetch(albumDescriptor) {
            for album in albums where (album.songs ?? []).isEmpty {
                context.delete(album)
            }
        }
        let personaDescriptor = FetchDescriptor<Persona>()
        if let personas = try? context.fetch(personaDescriptor) {
            for persona in personas where (persona.albums ?? []).isEmpty {
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
