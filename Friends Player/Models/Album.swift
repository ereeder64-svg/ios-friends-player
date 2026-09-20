//
//  Album.swift
//  Friends Player
//

import Foundation
import SwiftData

@Model
final class Album: Identifiable {
    // Inline defaults added for CloudKit schema readiness (see Song.swift
    // for the full rationale). No @Attribute(.unique) here to begin with.
    var title: String = ""
    var persona: Persona?
    var shareName: String = ""
    var relativePath: String = ""

    // Synced creation timestamp, used only as a deterministic tiebreaker in
    // LibraryScanner.mergeDuplicateAlbums() -- see Persona.firstSeenAt for
    // the full rationale (unstable local fetch order previously let two
    // devices converge on two different "winners" for the same duplicate
    // group).
    var firstSeenAt: Date = Date()

    // NOTE: not a stored/synced property -- see Song.downloadCachePath for
    // the full rationale. The cached artwork file only exists on whichever
    // device actually copied it down from the share, so its path can't be
    // synced via CloudKit without breaking on every other device. The
    // destination filename is deterministic from shareName + relativePath
    // (see LibraryScanner.cacheArtwork), so we just check whichever
    // extension actually landed on this device's disk.
    var artworkCachePath: String? {
        let cacheDir = LibraryScanner.artworkCacheDirectory()
        let safeRel = relativePath.replacingOccurrences(of: "/", with: "_")
        let base = "\(shareName)__\(safeRel)"
        for ext in ["png", "jpg", "jpeg", "webp"] {
            let candidate = cacheDir.appendingPathComponent("\(base).\(ext)")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate.path
            }
        }
        return nil
    }

    // CloudKit requires ALL relationships be optional, including to-many
    // (array) relationships -- a default empty array is not sufficient.
    @Relationship(deleteRule: .cascade, inverse: \Song.album)
    var songs: [Song]? = []

    /// Natural unique key, matching how LibraryScanner already dedupes
    /// albums (shareName + relativePath). Not stored — derived so existing
    /// data doesn't need a migration.
    var stableID: String { "\(shareName)|\(relativePath)" }

    /// Explicit Identifiable conformance for use in .sheet(item:) etc.
    /// (SwiftData's own PersistentIdentifier-based conformance isn't always
    /// picked up depending on toolchain, so make it unambiguous here.)
    var id: String { stableID }

    init(
        title: String,
        persona: Persona,
        shareName: String,
        relativePath: String
    ) {
        self.title = title
        self.persona = persona
        self.shareName = shareName
        self.relativePath = relativePath
        self.firstSeenAt = Date()
    }
}
