//
//  NowPlayingSnapshot.swift
//  Family Player + FamilyPlayerWidget (shared)
//

import Foundation

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
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let snap = try? JSONDecoder().decode(NowPlayingSnapshot.self, from: data) else {
            return .empty
        }
        return snap
    }

    func save() {
        guard let url = Self.fileURL,
              let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
