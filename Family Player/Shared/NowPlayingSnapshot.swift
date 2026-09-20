//
//  NowPlayingSnapshot.swift
//  Family Player + FamilyPlayerWidget (shared)
//

import Foundation
import OSLog

private let widgetLog = Logger(subsystem: "com.luxrecta.Friends-Player", category: "NowPlayingSnapshot")

struct NowPlayingSnapshot: Codable, Sendable, Equatable {
    var hasSong: Bool
    var songTitle: String
    var personaName: String
    var albumTitle: String
    var isPlaying: Bool
    var updatedAt: Date

    static let empty = NowPlayingSnapshot(
        hasSong: false,
        songTitle: "",
        personaName: "",
        albumTitle: "",
        isPlaying: false,
        updatedAt: .distantPast
    )

    private static var fileURL: URL? {
        AppGroupConstants.containerURL()?.appendingPathComponent("nowPlayingSnapshot.json")
    }

    static func load() -> NowPlayingSnapshot {
        guard let url = fileURL else {
            widgetLog.error("load(): AppGroupConstants.containerURL() returned nil — app group entitlement is not resolving.")
            return .empty
        }
        do {
            let data = try Data(contentsOf: url)
            do {
                return try JSONDecoder().decode(NowPlayingSnapshot.self, from: data)
            } catch {
                widgetLog.error("load(): decode failed at \(url.path, privacy: .public): \(String(describing: error), privacy: .public)")
                return .empty
            }
        } catch {
            widgetLog.error("load(): no readable file at \(url.path, privacy: .public): \(String(describing: error), privacy: .public)")
            return .empty
        }
    }

    func save() {
        guard let url = Self.fileURL else {
            widgetLog.error("save(): AppGroupConstants.containerURL() returned nil — app group entitlement is not resolving.")
            return
        }
        do {
            let data = try JSONEncoder().encode(self)
            try data.write(to: url, options: .atomic)
            widgetLog.debug("save(): wrote snapshot (hasSong=\(self.hasSong), title=\(self.songTitle, privacy: .public), isPlaying=\(self.isPlaying)) to \(url.path, privacy: .public)")
        } catch {
            widgetLog.error("save(): write failed at \(url.path, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }
}
