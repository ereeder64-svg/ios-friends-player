//
//  Album.swift
//  Family Player
//

import Foundation
import SwiftData

@Model
final class Album {
    var title: String
    var persona: Persona?
    var shareName: String
    var relativePath: String
    var artworkCachePath: String?

    @Relationship(deleteRule: .cascade, inverse: \Song.album)
    var songs: [Song] = []

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
