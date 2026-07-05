//
//  AppGroupConstants.swift
//  Family Player + FamilyPlayerWidget (shared)
//

import Foundation

enum AppGroupConstants {
    static let identifier = "group.com.luxrecta.Family-Player"

    /// Custom URL scheme used for widget tap-throughs (e.g. recent-album
    /// thumbnails). Requires a matching URL Type added to the main app
    /// target's Info settings in Xcode (Target > Info > URL Types).
    static let urlScheme = "familyplayer"

    /// Number of recent-album thumbnails shown on the medium widget.
    static let recentAlbumSlotCount = 4

    enum Keys {
        static let snapshot = "nowPlaying.snapshot"
        static let lastWidgetRequest = "widget.lastRequest"
        static let pendingAlbumDeepLinkID = "widget.pendingAlbumDeepLinkID"
    }

    enum Darwin {
        static let playPause = "com.luxrecta.familyplayer.widget.playPause"
        static let next = "com.luxrecta.familyplayer.widget.next"
        static let previous = "com.luxrecta.familyplayer.widget.previous"
    }

    static func sharedDefaults() -> UserDefaults? {
        UserDefaults(suiteName: identifier)
    }

    static func containerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    static func sharedArtworkURL() -> URL? {
        containerURL()?.appendingPathComponent("nowPlayingArtwork.png")
    }

    static func sharedRecentAlbumArtworkURL(slot: Int) -> URL? {
        containerURL()?.appendingPathComponent("recentAlbumArtwork\(slot).png")
    }

    /// Deep link opened when a widget's recent-album thumbnail is tapped.
    static func albumDeepLink(stableID: String) -> URL? {
        var components = URLComponents()
        components.scheme = urlScheme
        components.host = "album"
        components.queryItems = [URLQueryItem(name: "id", value: stableID)]
        return components.url
    }
}
