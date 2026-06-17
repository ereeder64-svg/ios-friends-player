//
//  LyricsService.swift
//  Family Player
//

import Foundation
import AVFoundation

enum LyricsService {

    static func cachedLyricsPath(for stableID: String) -> URL? {
        guard let dir = cacheDirectory() else { return nil }
        let safe = stableID.replacingOccurrences(of: "/", with: "_")
        return dir.appendingPathComponent("\(safe).txt")
    }

    static func loadCached(for stableID: String) -> String? {
        guard let url = cachedLyricsPath(for: stableID),
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8),
              !text.isEmpty else { return nil }
        return text
    }

    static func extract(from songURL: URL, stableID: String) async -> String? {
        if let cached = loadCached(for: stableID) { return cached }

        let asset = AVURLAsset(url: songURL)
        let items = (try? await asset.loadMetadata(for: .id3Metadata)) ?? []

        var found: String?
        for item in items where item.identifier == .id3MetadataUnsynchronizedLyric {
            if let str = try? await item.load(.stringValue), !str.isEmpty {
                found = str
                break
            }
            if let data = try? await item.load(.dataValue),
               let decoded = decodeUSLT(data), !decoded.isEmpty {
                found = decoded
                break
            }
        }

        if let text = found {
            saveCached(text, for: stableID)
            return text
        }
        return nil
    }

    private static func saveCached(_ text: String, for stableID: String) {
        guard let url = cachedLyricsPath(for: stableID),
              let data = text.data(using: .utf8) else { return }
        if let dir = cacheDirectory() {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try? data.write(to: url, options: .atomic)
    }

    private static func cacheDirectory() -> URL? {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        return docs.appendingPathComponent("LyricsCache", isDirectory: true)
    }

    static func clearCache(for stableID: String) {
        guard let url = cachedLyricsPath(for: stableID) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func clearAllCache() {
        guard let dir = cacheDirectory() else { return }
        try? FileManager.default.removeItem(at: dir)
    }

    /// Returns stableIDs of songs whose cached lyrics contain the query (case-insensitive).
    /// Matches against the LyricsCache directory only — songs without cached lyrics aren't searched.
    static func searchLyrics(query: String) -> Set<String> {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let dir = cacheDirectory(),
              let entries = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }
        let needle = trimmed.lowercased()
        var hits: Set<String> = []
        for url in entries where url.pathExtension == "txt" {
            guard let data = try? Data(contentsOf: url),
                  let text = String(data: data, encoding: .utf8) else { continue }
            if text.lowercased().contains(needle) {
                let stableID = url.deletingPathExtension().lastPathComponent
                    .replacingOccurrences(of: "_", with: "/")
                hits.insert(stableID)
            }
        }
        return hits
    }

    // USLT raw frame layout (when AVFoundation gives us the data blob, not a string):
    // [encoding:1][language:3][descriptor:null-terminated][lyrics:rest]
    private static func decodeUSLT(_ data: Data) -> String? {
        guard data.count > 4 else { return nil }
        let encoding = data[0]
        var idx = 4

        let encodingType: String.Encoding
        let nullTerminator: Data
        switch encoding {
        case 0x00:
            encodingType = .isoLatin1
            nullTerminator = Data([0x00])
        case 0x01, 0x02:
            encodingType = .utf16
            nullTerminator = Data([0x00, 0x00])
        case 0x03:
            encodingType = .utf8
            nullTerminator = Data([0x00])
        default:
            encodingType = .utf8
            nullTerminator = Data([0x00])
        }

        // Skip descriptor (null-terminated)
        if let range = data.range(of: nullTerminator, in: idx..<data.count) {
            idx = range.upperBound
        }
        guard idx < data.count else { return nil }
        let body = data.subdata(in: idx..<data.count)
        return String(data: body, encoding: encodingType)
    }
}
