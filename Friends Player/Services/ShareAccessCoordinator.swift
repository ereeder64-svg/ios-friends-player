//
//  ShareAccessCoordinator.swift
//  Friends Player
//

import Foundation
import SwiftData
import Observation

@Observable
final class ShareAccessCoordinator {

    static let expectedShares: [String] = [
        "Friends"
    ]

    private(set) var resolvedURLs: [String: URL] = [:]
    private(set) var staleShares: Set<String> = []

    // ShareBookmark lives in its own local-only ModelContainer (see
    // Friends_PlayerApp.localOnlyModelContainer) -- security-scoped bookmark
    // data only means something on the device/sandbox that created it, so
    // it must never be in the CloudKit-synced container. This coordinator
    // owns its own ModelContext against that separate container rather than
    // taking the app's shared (synced) context from callers.
    private let context: ModelContext

    init(localContainer: ModelContainer = Friends_PlayerApp.localOnlyModelContainer) {
        self.context = ModelContext(localContainer)
    }

    func hasAnyShares() -> Bool {
        let descriptor = FetchDescriptor<ShareBookmark>()
        let count = (try? context.fetchCount(descriptor)) ?? 0
        return count > 0
    }

    @discardableResult
    func resolveAll() -> [String: URL] {
        resolvedURLs.removeAll()
        staleShares.removeAll()

        let descriptor = FetchDescriptor<ShareBookmark>()
        guard let bookmarks = try? context.fetch(descriptor) else { return [:] }

        for bookmark in bookmarks {
            do {
                var isStale = false
                let url = try URL(
                    resolvingBookmarkData: bookmark.bookmarkData,
                    options: [],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                if isStale {
                    staleShares.insert(bookmark.shareName)
                }
                resolvedURLs[bookmark.shareName] = url
            } catch {
                staleShares.insert(bookmark.shareName)
            }
        }
        return resolvedURLs
    }

    func saveBookmark(for shareName: String, pickedURL: URL) throws {
        let didStart = pickedURL.startAccessingSecurityScopedResource()
        defer { if didStart { pickedURL.stopAccessingSecurityScopedResource() } }

        let data = try pickedURL.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        let descriptor = FetchDescriptor<ShareBookmark>(
            predicate: #Predicate { $0.shareName == shareName }
        )
        if let existing = try context.fetch(descriptor).first {
            existing.bookmarkData = data
            existing.lastResolvedAt = Date()
        } else {
            let bookmark = ShareBookmark(shareName: shareName, bookmarkData: data)
            context.insert(bookmark)
        }
        try context.save()

        resolvedURLs[shareName] = pickedURL
        staleShares.remove(shareName)
    }

    func removeBookmark(for shareName: String) throws {
        let descriptor = FetchDescriptor<ShareBookmark>(
            predicate: #Predicate { $0.shareName == shareName }
        )
        for bookmark in try context.fetch(descriptor) {
            context.delete(bookmark)
        }
        try context.save()
        resolvedURLs.removeValue(forKey: shareName)
        staleShares.remove(shareName)
    }

    func url(for shareName: String) -> URL? {
        resolvedURLs[shareName]
    }

    func configuredShareNames() -> [String] {
        Array(resolvedURLs.keys).sorted()
    }

    /// Song/Album/Persona sync globally via CloudKit, but each device only
    /// has actual file access to the shares IT has connected (ShareBookmark
    /// is local-only, per device). Any Song/Album whose shareName isn't in
    /// this set exists in the synced library only because some other
    /// device connected that share -- this device can't reach the file, so
    /// it should be filtered out of every user-facing list rather than
    /// shown with placeholder artwork / failing to play.
    var connectedShareNames: Set<String> {
        Set(resolvedURLs.keys)
    }
}
