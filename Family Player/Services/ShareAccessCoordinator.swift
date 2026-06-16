//
//  ShareAccessCoordinator.swift
//  Family Player
//

import Foundation
import SwiftData
import Observation

@Observable
final class ShareAccessCoordinator {

    static let expectedShares: [String] = [
        "Public Share",
        "Family Share",
        "Legacy Share",
        "Amanda",
        "Chris",
        "Emily",
        "Michele"
    ]

    private(set) var resolvedURLs: [String: URL] = [:]
    private(set) var staleShares: Set<String> = []

    func hasAnyShares(context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<ShareBookmark>()
        let count = (try? context.fetchCount(descriptor)) ?? 0
        return count > 0
    }

    @discardableResult
    func resolveAll(context: ModelContext) -> [String: URL] {
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

    func saveBookmark(for shareName: String, pickedURL: URL, context: ModelContext) throws {
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

    func removeBookmark(for shareName: String, context: ModelContext) throws {
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
}
