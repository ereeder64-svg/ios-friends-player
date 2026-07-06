//
//  Song.swift
//  Family Player
//

import Foundation
import SwiftData

@Model
final class Song {
    @Attribute(.unique) var stableID: String
    var title: String
    var trackNumber: Int?
    var album: Album?
    var shareName: String
    var relativePath: String
    var hasLyrics: Bool
    var duration: Double
    var metadataLoaded: Bool
    var dateAddedToLibrary: Date

    var isFavorite: Bool
    var hasBeenPlayed: Bool
    var lastPlayedAt: Date?
    var playCount: Int

    var downloadCachePath: String?
    var downloadedAt: Date?
    var downloadSizeBytes: Int64

    init(
        stableID: String,
        title: String,
        trackNumber: Int? = nil,
        album: Album,
        shareName: String,
        relativePath: String,
        hasLyrics: Bool = false,
        duration: Double = 0
    ) {
        self.stableID = stableID
        self.title = title
        self.trackNumber = trackNumber
        self.album = album
        self.shareName = shareName
        self.relativePath = relativePath
        self.hasLyrics = hasLyrics
        self.duration = duration
        self.metadataLoaded = false
        self.dateAddedToLibrary = Date()

        self.isFavorite = false
        self.hasBeenPlayed = false
        self.lastPlayedAt = nil
        self.playCount = 0

        self.downloadCachePath = nil
        self.downloadedAt = nil
        self.downloadSizeBytes = 0
    }

    /// `title` with a manually-embedded two-digit track-number prefix
    /// stripped for display (e.g. "03 Bohemian Rhapsody" -> "Bohemian
    /// Rhapsody"). Only strips when the first two characters are both
    /// digits; otherwise the full title is returned untouched — a
    /// catch-all for songs that don't follow that naming convention.
    /// Sorting, search, and stableID all continue to use the raw `title`,
    /// which is unaffected by this.
    var displayTitle: String {
        let chars = Array(title)
        guard chars.count >= 2, chars[0].isNumber, chars[1].isNumber else {
            return title
        }
        let trimmed = String(chars.dropFirst(3))
        return trimmed.isEmpty ? title : trimmed
    }
}
