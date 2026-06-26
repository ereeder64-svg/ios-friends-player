//
//  AppGroupConstants.swift
//  Family Player + FamilyPlayerWidget (shared)
//

import Foundation

enum AppGroupConstants {
    static let identifier = "group.com.luxrecta.Family-Player"

    enum Keys {
        static let snapshot = "nowPlaying.snapshot"
        static let lastWidgetRequest = "widget.lastRequest"
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
}
