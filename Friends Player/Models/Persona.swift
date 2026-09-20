//
//  Persona.swift
//  Friends Player
//

import Foundation
import SwiftData

@Model
final class Persona {
    // No @Attribute(.unique): CloudKit forbids it. fetchOrCreatePersona(...)
    // in LibraryScanner already fetches by name before inserting, so
    // app-level dedup already exists independent of this constraint.
    var name: String = ""

    // Synced creation timestamp, used only as a deterministic tiebreaker
    // when LibraryScanner.mergeDuplicatePersonas() finds two Persona rows
    // with the same name (leftover duplicates from earlier sync bugs) and
    // needs to decide which one to keep. Without a synced, content-derived
    // value like this, each device's tiebreak fell back to local fetch
    // order, which isn't guaranteed to match across devices -- so two
    // devices could each keep a *different* copy and repeatedly try to
    // delete the other's, which also meant favorite/play state applied to
    // "the wrong" copy could keep disappearing.
    var firstSeenAt: Date = Date()

    // NOTE: not stored/synced -- see Song.downloadCachePath for why. The
    // cached artwork file only exists on whichever device copied it down,
    // so its path can't be synced via CloudKit. Destination filename is
    // deterministic (see LibraryScanner.cachePersonaArtwork), always .png.
    var artworkCachePath: String? {
        let cacheDir = LibraryScanner.artworkCacheDirectory()
        let safeName = name.replacingOccurrences(of: "/", with: "_")
        let candidate = cacheDir.appendingPathComponent("_persona_\(safeName).png")
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate.path : nil
    }

    // CloudKit requires ALL relationships be optional, including to-many
    // (array) relationships -- a default empty array is not sufficient.
    @Relationship(deleteRule: .cascade, inverse: \Album.persona)
    var albums: [Album]? = []

    init(name: String) {
        self.name = name
        self.firstSeenAt = Date()
    }
}
