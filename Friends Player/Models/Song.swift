//
//  Song.swift
//  Friends Player
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
    // Read from the MP3's ID3 genre (TCON) tag at scan time -- see
    // LibraryScanner.readMetadata. nil/blank means the file just isn't
    // tagged; GenresListView folds those into an "Unknown Genre" bucket
    // rather than hiding them, so untagged songs stay easy to find.
    var genre: String?

    var isFavorite: Bool = false
    var hasBeenPlayed: Bool = false
    var lastPlayedAt: Date?
    var playCount: Int = 0

    // NOTE: download state is intentionally NOT a stored/synced property.
    // It used to be (downloadCachePath/downloadedAt/downloadSizeBytes as
    // @Model vars), which meant CloudKit synced one device's local file
    // path to every other device -- so a song downloaded on the iPad would
    // show as "already downloaded" on the iPhone (wrong path, file doesn't
    // exist there), and refreshing on one device could stomp the other's
    // state. Download location is fully deterministic from shareName +
    // relativePath (see DownloadManager.destinationURL), so instead we just
    // check the local filesystem on demand -- naturally per-device, nothing
    // to keep in sync.
    var downloadCachePath: String? {
        let path = DownloadManager.destinationURL(for: self).path
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    var downloadedAt: Date? {
        guard let path = downloadCachePath,
              let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        return (attrs[.creationDate] as? Date) ?? (attrs[.modificationDate] as? Date)
    }

    var downloadSizeBytes: Int64 {
        guard let path = downloadCachePath,
              let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int64 else { return 0 }
        return size
    }

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
        duration: Double = 0,
        genre: String? = nil
    ) {
        self.stableID = stableID
        self.title = title
        self.trackNumber = trackNumber
        self.album = album
        self.shareName = shareName
        self.relativePath = relativePath
        self.hasLyrics = hasLyrics
        self.duration = duration
        self.genre = genre
        self.metadataLoaded = false
        self.dateAddedToLibrary = Date()

        self.isFavorite = false
        self.hasBeenPlayed = false
        self.lastPlayedAt = nil
        self.playCount = 0
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

    /// Genre bucket name for grouping (GenresListView, and the "Genres
    /// (N)" count in Library's Browse section). Blank/missing genre folds
    /// into a single "Unknown Genre" bucket instead of being dropped, so
    /// songs that still need a genre tag stay visible rather than
    /// disappearing from the Genres list entirely.
    static func genreName(for song: Song) -> String {
        // normalizedGenre also cleans numeric values ("(17)") already stored
        // by earlier scans, so they display correctly without a rescan.
        normalizedGenre(song.genre) ?? "Unknown Genre"
    }
}
