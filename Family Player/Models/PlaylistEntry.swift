//
//  PlaylistEntry.swift
//  Family Player
//

import Foundation
import SwiftData

@Model
final class PlaylistEntry {
    var playlist: Playlist?
    var song: Song?
    var dateAdded: Date
    var position: Int

    init(playlist: Playlist, song: Song, position: Int) {
        self.playlist = playlist
        self.song = song
        self.position = position
        self.dateAdded = Date()
    }
}
