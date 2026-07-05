//
//  Album.swift
//  Family Player
//

import Foundation
import SwiftData

@Model
final class Album: Identifiable {
    var title: String
    var persona: Persona?
    var shareName: String
    var relativePath: String
    var artworkCachePath: String?

    @Relationship(deleteRule: .cascade, inverse: \Song.album)
    var songs: [Song] = []

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
        relativePath: String,
        artworkCachePath: String? = nil
    ) {
        self.title = title
        self.persona = persona
        self.shareName = shareName
        self.relativePath = relativePath
        self.artworkCachePath = artworkCachePath
    }
}
