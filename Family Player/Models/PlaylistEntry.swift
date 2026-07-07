//
//  PlaylistEntry.swift
//  Family Player
//

import Foundation
import SwiftData

@Model
final class PlaylistEntry {
    var playlist: Playlist?
    // Inverse of Song.playlistEntries is declared on the Song side (matches
    // this codebase's existing convention: Persona/Album/Playlist all
    // declare their @Relationship(inverse:) on the "collection" side).
    var song: Song?
    // Inline defaults added for CloudKit schema readiness (see Song.swift
    // for the full rationale).
    var dateAdded: Date = Date()
    var position: Int = 0

    init(playlist: Playlist, song: Song, position: Int) {
        self.playlist = playlist
        self.song = song
        self.position = position
        self.dateAdded = Date()
    }
}
