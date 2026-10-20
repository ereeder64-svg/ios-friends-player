//
//  ShareRenameMigration.swift
//  Friends Player
//

import Foundation
import SwiftData

/// One-time migration for renaming a share. The share name is a persisted
/// key, not just a label: it's stored on every Song/Album (and in Song's
/// stableID), on the local-only ShareBookmark, and baked into the
/// filenames of downloaded songs and cached artwork. Changing the string
/// alone would orphan all of that -- favorites, play history, downloads
/// and the saved folder bookmark -- so each store is rewritten here.
/// Every step is idempotent and cheap once nothing carries an old name.
enum ShareRenameMigration {

    /// old share name -> current share name
    static let renames: [String: String] = ["Friends": "Friends Share"]

    // MARK: - Local-only bookmarks

    static func migrateBookmarks(in context: ModelContext) {
        for (old, new) in renames {
            let oldDescriptor = FetchDescriptor<ShareBookmark>(
                predicate: #Predicate { $0.shareName == old }
            )
            guard let oldRows = try? context.fetch(oldDescriptor), !oldRows.isEmpty else { continue }

            let newDescriptor = FetchDescriptor<ShareBookmark>(
                predicate: #Predicate { $0.shareName == new }
            )
            let hasNew = ((try? context.fetchCount(newDescriptor)) ?? 0) > 0

            for row in oldRows {
                if hasNew {
                    // The folder was already re-picked under the new name.
                    context.delete(row)
                } else {
                    row.shareName = new
                }
            }
        }
        try? context.save()
    }

    // MARK: - On-disk caches (per device)

    static func migrateFiles() {
        let directories = [
            DownloadManager.downloadDirectory(),
            LibraryScanner.artworkCacheDirectory(),
        ]
        let fm = FileManager.default
        for dir in directories {
            guard let files = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            for (old, new) in renames {
                let oldPrefix = "\(old)__"
                for name in files where name.hasPrefix(oldPrefix) {
                    let renamed = "\(new)__" + name.dropFirst(oldPrefix.count)
                    let source = dir.appendingPathComponent(name)
                    let destination = dir.appendingPathComponent(renamed)
                    if fm.fileExists(atPath: destination.path) {
                        try? fm.removeItem(at: source)
                    } else {
                        try? fm.moveItem(at: source, to: destination)
                    }
                }
            }
        }
    }

    // MARK: - Synced library (Song / Album)

    static func migrateLibrary(in context: ModelContext) {
        for (old, new) in renames {
            let songDescriptor = FetchDescriptor<Song>(
                predicate: #Predicate { $0.shareName == old }
            )
            if let songs = try? context.fetch(songDescriptor) {
                for song in songs {
                    song.shareName = new
                    song.stableID = "\(new)|\(song.relativePath)"
                }
            }

            let albumDescriptor = FetchDescriptor<Album>(
                predicate: #Predicate { $0.shareName == old }
            )
            if let albums = try? context.fetch(albumDescriptor) {
                for album in albums {
                    let relativePath = album.relativePath
                    var existing = FetchDescriptor<Album>(
                        predicate: #Predicate { $0.shareName == new && $0.relativePath == relativePath }
                    )
                    existing.fetchLimit = 1
                    if let target = try? context.fetch(existing).first {
                        // Another device already migrated this album --
                        // fold ours into it instead of leaving a twin.
                        for song in album.songs ?? [] { song.album = target }
                        context.delete(album)
                    } else {
                        album.shareName = new
                    }
                }
            }
        }
        try? context.save()
    }
}
