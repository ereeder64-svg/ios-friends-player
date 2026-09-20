//
//  Song+Sort.swift
//  Friends Player
//

import Foundation

extension Array where Element == Song {
    func sortedByAlbumThenTitle() -> [Song] {
        sorted { lhs, rhs in
            let albumL = lhs.album?.title ?? ""
            let albumR = rhs.album?.title ?? ""
            let albumCmp = albumL.localizedCaseInsensitiveCompare(albumR)
            if albumCmp != .orderedSame {
                return albumCmp == .orderedAscending
            }
            let trackL = lhs.trackNumber ?? Int.max
            let trackR = rhs.trackNumber ?? Int.max
            if trackL != trackR {
                return trackL < trackR
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }
}
