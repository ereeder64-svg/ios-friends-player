//
//  Song.swift
//  Family Player
//

import Foundation
import SwiftData

@Model
final class Song {
    // NOTE on CloudKit readiness (no CloudKit sync enabled yet, this is
    // schema prep for a possible future iPad app):
    // - No @Attribute(.unique): CloudKit forbids it. Every creation path
    //   (LibraryScanner.processSong) already fetches by stableID before
    //   inserting, so app-level dedup already exists independent of this
    //   constraint -- removing it doesn't change current behavior.
    // - Every non-optional property below has an inline default value,
    //   which CloudKit requires (optional-or-default at declaration).
    var stableID: String = ""
    var title: String = ""
    var trackNumber: Int?
    var album: Album?
    var shareName: String = ""
    var relativePath: String = ""
    var hasLyrics: Bool = false
    var duration: Double = 0
    var metadataLoaded: Bool = false
    var dateAddedToLibrary: Date = Date()

    var isFavorite: Bool = false
    var hasBeenPlayed: Bool = false
    var lastPlayedAt: Date?
    var playCount: Int = 0

    var downloadCachePath: String?
    var downloadedAt: Date?
    var downloadSizeBytes: Int64 = 0

    // Inverse side of PlaylistEntry.song. Previously PlaylistEntry.song had
    // no @Relationship/inverse at all, which is why deleting a Song left
    // orphaned PlaylistEntry rows (worked around by RootView's
    // purgeOrphanedPlaylistEntries() scan on launch -- left in place as a
    // safety net for any pre-existing orphans, but this fixes the root
    // cause going forward: deleting a Song now cascades to its entries).
    // CloudKit requires ALL relationships be optional, including to-many
    // (array) relationships -- a default empty array is not sufficient.
    @Relationship(deleteRule: .cascade, inverse: \PlaylistEntry.song)
    var playlistEntries: [PlaylistEntry]? = []

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
