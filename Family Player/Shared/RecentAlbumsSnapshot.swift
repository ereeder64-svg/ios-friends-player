//
//  RecentAlbumsSnapshot.swift
//  Family Player + FamilyPlayerWidget (shared)
//

import Foundation
import OSLog

private let widgetLog = Logger(subsystem: "com.luxrecta.Family-Player", category: "RecentAlbumsSnapshot")

struct RecentAlbumEntry: Codable, Sendable, Equatable, Identifiable {
    var id: String        // Album.stableID
    var title: String
    var personaName: String
}

struct RecentAlbumsSnapshot: Codable, Sendable, Equatable {
    var albums: [RecentAlbumEntry]

    static let empty = RecentAlbumsSnapshot(albums: [])

    private static var fileURL: URL? {
        AppGroupConstants.containerURL()?.appendingPathComponent("recentAlbums.json")
    }

    static func load() -> RecentAlbumsSnapshot {
        guard let url = fileURL else {
            widgetLog.error("load(): AppGroupConstants.containerURL() returned nil — app group entitlement is not resolving.")
            return .empty
        }
        do {
            let data = try Data(contentsOf: url)
            do {
                return try JSONDecoder().decode(RecentAlbumsSnapshot.self, from: data)
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
            widgetLog.debug("save(): wrote \(self.albums.count) recent album(s) to \(url.path, privacy: .public)")
        } catch {
            widgetLog.error("save(): write failed at \(url.path, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }
}
