//
//  ShareBookmark.swift
//  Friends Player
//

import Foundation
import SwiftData

@Model
final class ShareBookmark {
    // No @Attribute(.unique): CloudKit forbids it. saveBookmark(...) in
    // ShareAccessCoordinator already fetches by shareName before inserting,
    // so app-level dedup already exists independent of this constraint.
    var shareName: String = ""
    var bookmarkData: Data = Data()
    var lastResolvedAt: Date = Date()

    init(shareName: String, bookmarkData: Data) {
        self.shareName = shareName
        self.bookmarkData = bookmarkData
        self.lastResolvedAt = Date()
    }
}
