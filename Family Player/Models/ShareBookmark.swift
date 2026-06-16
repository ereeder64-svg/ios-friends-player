//
//  ShareBookmark.swift
//  Family Player
//

import Foundation
import SwiftData

@Model
final class ShareBookmark {
    @Attribute(.unique) var shareName: String
    var bookmarkData: Data
    var lastResolvedAt: Date

    init(shareName: String, bookmarkData: Data) {
        self.shareName = shareName
        self.bookmarkData = bookmarkData
        self.lastResolvedAt = Date()
    }
}
