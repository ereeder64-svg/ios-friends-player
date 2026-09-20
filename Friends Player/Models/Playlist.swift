//
//  Playlist.swift
//  Friends Player
//

import Foundation
import SwiftData

enum PlaylistSortMode: String, Codable, CaseIterable {
    case alpha
    case dateAdded
}

@Model
final class Playlist {
    // Inline defaults added for CloudKit schema readiness (see Song.swift
    // for the full rationale).
    var name: String = ""
    var dateCreated: Date = Date()
    var sortModeRaw: String = PlaylistSortMode.dateAdded.rawValue

    // CloudKit requires ALL relationships be optional, including to-many
    // (array) relationships -- a default empty array is not sufficient.
    @Relationship(deleteRule: .cascade, inverse: \PlaylistEntry.playlist)
    var entries: [PlaylistEntry]? = []

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
