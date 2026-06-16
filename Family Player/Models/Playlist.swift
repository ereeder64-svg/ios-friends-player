//
//  Playlist.swift
//  Family Player
//

import Foundation
import SwiftData

enum PlaylistSortMode: String, Codable, CaseIterable {
    case alpha
    case dateAdded
}

@Model
final class Playlist {
    var name: String
    var dateCreated: Date
    var sortModeRaw: String

    @Relationship(deleteRule: .cascade, inverse: \PlaylistEntry.playlist)
    var entries: [PlaylistEntry] = []

    var sortMode: PlaylistSortMode {
        get { PlaylistSortMode(rawValue: sortModeRaw) ?? .dateAdded }
        set { sortModeRaw = newValue.rawValue }
    }

    init(name: String, sortMode: PlaylistSortMode = .dateAdded) {
        self.name = name
        self.dateCreated = Date()
        self.sortModeRaw = sortMode.rawValue
    }
}
