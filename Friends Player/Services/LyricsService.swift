//
//  LyricsService.swift
//  Friends Player
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

        // 1. Try SYLT (synchronized lyrics) via AVFoundation — converts to LRC text.
        for item in items where isSYLTItem(item) {
            if let data = try? await item.load(.dataValue),
               let lines = decodeSYLT(data), !lines.isEmpty {
                let lrc = formatAsLRC(lines)
                saveCached(lrc, for: stableID)
                return lrc
            }
        }

        // 2. AVFoundation may not surface SYLT for some files — try reading
        //    raw ID3 frames directly via NSFileCoordinator (handles iCloud
        //    materialization, works for both local and placeholder files).
        if let frames = await readID3FramesCoordinated(at: songURL),
           let sylt = frames.first(where: { $0.id == "SYLT" }),
           let lines = decodeSYLT(sylt.data), !lines.isEmpty {
            let lrc = formatAsLRC(lines)
            saveCached(lrc, for: stableID)
            return lrc
        }

        // 3. Fall back to USLT (plain text, possibly already LRC-formatted).
        for item in items where item.identifier == .id3MetadataUnsynchronizedLyric {
            if let str = try? await item.load(.stringValue), !str.isEmpty {
                saveCached(str, for: stableID)
                return str
            }
            if let data = try? await item.load(.dataValue),
               let decoded = decodeUSLT(data), !decoded.isEmpty {
                saveCached(decoded, for: stableID)
                return decoded
            }
        }
        return nil
    }

    private static func isSYLTItem(_ item: AVMetadataItem) -> Bool {
        let id = item.identifier?.rawValue ?? ""
        let key = (item.key as? String) ?? ""
        return id.hasSuffix("SYLT") ||
               id.contains("synchronized-lyric") ||
               id.contains("SynchronizedLyric") ||
               key == "SYLT"
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

    // MARK: - LRC timestamp parsing

    struct TimedLine: Hashable, Sendable {
        let time: TimeInterval
        let text: String
    }

    /// Parses LRC-style timestamps from a lyrics blob.
    /// Returns nil if no timestamps were found — caller should fall back to plain text rendering.
    /// Format: each line may begin with one or more `[MM:SS.xx]` markers, e.g.
    ///   `[00:11.18][Verse 1] (Amanda)`  → time=11.18, text="[Verse 1] (Amanda)"
    ///   `[00:50.00][01:30.00]Chorus line` → emits two entries pointing at the same text.
    static func parseTimedLyrics(_ text: String) -> [TimedLine]? {
        guard let regex = try? NSRegularExpression(pattern: #"\[(\d{1,2}):(\d{2})\.(\d{1,3})\]"#) else { return nil }

        var result: [TimedLine] = []
        for rawLine in text.components(separatedBy: .newlines) {
            var remaining = rawLine.trimmingCharacters(in: .whitespaces)
            guard !remaining.isEmpty else { continue }

            var timestamps: [TimeInterval] = []
            while let match = regex.firstMatch(
                in: remaining,
                options: [.anchored],
                range: NSRange(remaining.startIndex..., in: remaining)
            ) {
                if let mRange = Range(match.range(at: 1), in: remaining),
                   let sRange = Range(match.range(at: 2), in: remaining),
                   let fRange = Range(match.range(at: 3), in: remaining),
                   let fullRange = Range(match.range, in: remaining) {
                    let minutes = Int(remaining[mRange]) ?? 0
                    let seconds = Int(remaining[sRange]) ?? 0
                    let frac = Double("0.\(remaining[fRange])") ?? 0
                    timestamps.append(Double(minutes * 60 + seconds) + frac)
                    remaining = String(remaining[fullRange.upperBound...])
                } else {
                    break
                }
            }

            guard !timestamps.isEmpty else { continue }
            let lyric = remaining.trimmingCharacters(in: .whitespaces)
            for ts in timestamps {
                result.append(TimedLine(time: ts, text: lyric))
            }
        }

        guard !result.isEmpty else { return nil }
        return result.sorted { $0.time < $1.time }
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

    // MARK: - SYLT decoding
    //
    // SYLT frame layout:
    //   [encoding:1][language:3][timestamp format:1][content type:1]
    //   [descriptor:null-term][text:null-term][timestamp:4 BE]...repeats...
    // timestamp format: 0x02 = milliseconds (the only one we support)
    private static func decodeSYLT(_ data: Data) -> [TimedLine]? {
        guard data.count >= 6 else { return nil }

        let encoding = data[0]
        let timestampFormat = data[4]
        guard timestampFormat == 0x02 else { return nil }

        let isUTF16 = (encoding == 0x01 || encoding == 0x02)
        let isUTF8 = (encoding == 0x03)
        let stringEncoding: String.Encoding = isUTF16 ? .utf16 : (isUTF8 ? .utf8 : .isoLatin1)
        let nullLen = isUTF16 ? 2 : 1

        var idx = 6
        // Skip content descriptor (null-terminated)
        idx = skipNullTerminated(in: data, from: idx, isUTF16: isUTF16)
        guard idx <= data.count else { return nil }

        var lines: [TimedLine] = []
        while idx + nullLen + 4 <= data.count {
            let textStart = idx
            let textEnd = findNullTerminator(in: data, from: textStart, isUTF16: isUTF16)
            guard textEnd >= textStart, textEnd + nullLen + 4 <= data.count else { break }

            let textBytes = data.subdata(in: textStart..<textEnd)
            let text = String(data: textBytes, encoding: stringEncoding) ?? ""

            idx = textEnd + nullLen

            let timestamp = (UInt32(data[idx]) << 24)
                | (UInt32(data[idx + 1]) << 16)
                | (UInt32(data[idx + 2]) << 8)
                | UInt32(data[idx + 3])
            idx += 4

            let timeSeconds = TimeInterval(timestamp) / 1000.0
            lines.append(TimedLine(time: timeSeconds, text: text.trimmingCharacters(in: .newlines)))
        }

        guard !lines.isEmpty else { return nil }
        return lines.sorted { $0.time < $1.time }
    }

    private static func skipNullTerminated(in data: Data, from start: Int, isUTF16: Bool) -> Int {
        let end = findNullTerminator(in: data, from: start, isUTF16: isUTF16)
        return end + (isUTF16 ? 2 : 1)
    }

    private static func findNullTerminator(in data: Data, from start: Int, isUTF16: Bool) -> Int {
        var i = start
        if isUTF16 {
            while i + 1 < data.count {
                if data[i] == 0 && data[i + 1] == 0 { return i }
                i += 2
            }
        } else {
            while i < data.count {
                if data[i] == 0 { return i }
                i += 1
            }
        }
        return data.count
    }

    private static func formatAsLRC(_ lines: [TimedLine]) -> String {
        return lines.map { line in
            let totalCentiseconds = Int((line.time * 100).rounded())
            let minutes = totalCentiseconds / 6000
            let seconds = (totalCentiseconds % 6000) / 100
            let cs = totalCentiseconds % 100
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return String(format: "[%02d:%02d.%02d]%@", minutes, seconds, cs, text)
        }.joined(separator: "\n")
    }

    // MARK: - Raw ID3v2 tag reader
    //
    // Coordinated read materializes iCloud placeholders and yields a URL
    // we can read directly. This is how artwork is fetched too.
    private static func readID3FramesCoordinated(at url: URL) async -> [(id: String, data: Data)]? {
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        return await withCheckedContinuation { (continuation: CheckedContinuation<[(id: String, data: Data)]?, Never>) in
            DispatchQueue.global(qos: .utility).async {
                let coordinator = NSFileCoordinator()
                var coordError: NSError?
                var result: [(id: String, data: Data)]? = nil
                coordinator.coordinate(
                    readingItemAt: url,
                    options: [],
                    error: &coordError
                ) { coordinatedURL in
                    guard FileManager.default.fileExists(atPath: coordinatedURL.path) else { return }
                    result = readID3Frames(from: coordinatedURL)
                }
                continuation.resume(returning: result)
            }
        }
    }

    // Reads the ID3v2 tag at the start of an MP3 file and returns the frames.
    // Returns nil if the file isn't readable.
    private static func readID3Frames(from url: URL) -> [(id: String, data: Data)]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        guard let header = try? handle.read(upToCount: 10), header.count == 10 else { return nil }
        guard header[0] == 0x49, header[1] == 0x44, header[2] == 0x33 else { return nil }

        let isV24 = header[3] >= 4
        let tagSize = (Int(header[6] & 0x7F) << 21)
            | (Int(header[7] & 0x7F) << 14)
            | (Int(header[8] & 0x7F) << 7)
            | Int(header[9] & 0x7F)
        guard tagSize > 0, tagSize < 10_000_000 else { return nil }

        guard let tagData = try? handle.read(upToCount: tagSize), tagData.count >= 10 else { return nil }

        var frames: [(id: String, data: Data)] = []
        var idx = 0
        while idx + 10 <= tagData.count {
            guard let frameID = String(data: tagData.subdata(in: idx..<(idx + 4)), encoding: .ascii),
                  frameID.count == 4,
                  let first = frameID.first,
                  first.isLetter || first.isNumber else { break }

            let s0 = tagData[idx + 4], s1 = tagData[idx + 5]
            let s2 = tagData[idx + 6], s3 = tagData[idx + 7]
            let frameSize: Int
            if isV24 {
                frameSize = (Int(s0 & 0x7F) << 21) | (Int(s1 & 0x7F) << 14)
                          | (Int(s2 & 0x7F) << 7) | Int(s3 & 0x7F)
            } else {
                frameSize = (Int(s0) << 24) | (Int(s1) << 16) | (Int(s2) << 8) | Int(s3)
            }

            let contentStart = idx + 10
            let contentEnd = contentStart + frameSize
            guard frameSize >= 0, contentEnd <= tagData.count else { break }

            frames.append((id: frameID, data: tagData.subdata(in: contentStart..<contentEnd)))
            idx = contentEnd
        }
        return frames
    }
}
