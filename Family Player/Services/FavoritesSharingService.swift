//
//  FavoritesSharingService.swift
//  Family Player
//

import Foundation
import CloudKit
import SwiftData
import Observation
import OSLog

private let favoritesSharingLog = Logger(subsystem: "com.luxrecta.Friends-Player", category: "FavoritesSharing")

extension Notification.Name {
    static let familyFavoritesShareAccepted = Notification.Name("familyFavoritesShareAccepted")
}

/// One song's favorite status merged across every favorites list this
/// device can currently see (this user's own + anyone who has shared
/// theirs with this user).
struct FamilyFavorite: Identifiable {
    let stableID: String
    let title: String
    let albumTitle: String
    let personaName: String
    var owners: [String]

    var id: String { stableID }
}

// Deliberately separate from ShareAccessCoordinator/ShareBookmark, which are
// about read access to iCloud Drive folders (a completely different
// mechanism -- security-scoped bookmarks to files). This is real CKShare:
// each user zone-wide-shares a small CloudKit zone containing just
// "I favorited song X" records, read-only, to the rest of the family --
// their music folders are never touched.
@MainActor
@Observable
final class FavoritesSharingService {

    private(set) var isSharingEnabled: Bool {
        didSet { UserDefaults.standard.set(isSharingEnabled, forKey: Self.enabledKey) }
    }
    var ownerDisplayName: String {
        didSet { UserDefaults.standard.set(ownerDisplayName, forKey: Self.nameKey) }
    }

    private(set) var familyFavorites: [FamilyFavorite] = []
    private(set) var isRefreshing = false
    private(set) var lastError: String?

    private static let enabledKey = "favoritesSharing.isEnabled"
    private static let nameKey = "favoritesSharing.ownerDisplayName"
    private static let recordType = "FavoriteSong"
    private static let zoneName = "FamilyFavoritesZone"

    private let container = CKContainer(identifier: "iCloud.com.luxrecta.Friends-Player")
    private var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName)
    }

    init() {
        let defaults = UserDefaults.standard
        isSharingEnabled = defaults.bool(forKey: Self.enabledKey)
        ownerDisplayName = defaults.string(forKey: Self.nameKey) ?? ""
    }

    func clearLastError() {
        lastError = nil
    }

    // MARK: - Enable / disable

    /// Creates (or reuses) this user's favorites zone, zone-wide shares it
    /// read-only, pushes every currently-favorited song into it, and
    /// returns the share URL to hand off via `ShareLink`.
    func enableSharing(displayName: String, context: ModelContext) async -> URL? {
        ownerDisplayName = displayName
        do {
            let zone = CKRecordZone(zoneID: zoneID)
            _ = try await container.privateCloudDatabase.save(zone)

            let share = try await existingShare() ?? CKShare(recordZoneID: zoneID)
            share.publicPermission = .readOnly
            share[CKShare.SystemFieldKey.title] = "Family Player Favorites" as CKRecordValue
            _ = try await container.privateCloudDatabase.modifyRecords(saving: [share], deleting: [])

            isSharingEnabled = true
            await pushAllFavorites(context: context)
            return share.url
        } catch {
            lastError = "Couldn't enable favorites sharing: \(error.localizedDescription)"
            favoritesSharingLog.error("enableSharing failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Deletes the zone outright rather than trying to partially revoke
    /// participants -- one step, no in-between state, and it takes the
    /// share down with it.
    func disableSharing() async {
        do {
            try await container.privateCloudDatabase.deleteRecordZone(withID: zoneID)
        } catch {
            lastError = "Couldn't fully remove the shared favorites zone: \(error.localizedDescription)"
            favoritesSharingLog.error("disableSharing failed: \(error.localizedDescription, privacy: .public)")
        }
        isSharingEnabled = false
    }

    private func existingShare() async throws -> CKShare? {
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        do {
            return try await container.privateCloudDatabase.record(for: shareID) as? CKShare
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    /// Re-fetches the invite URL for an already-enabled share -- needed
    /// because the URL only comes back from `enableSharing`'s return value,
    /// which a settings screen re-opened later has no memory of.
    func currentShareURL() async -> URL? {
        guard isSharingEnabled else { return nil }
        return (try? await existingShare())?.url
    }

    /// Changes the name attached to your shared favorites without touching
    /// whether sharing is on. Re-pushes every favorite so already-synced
    /// records pick up the new name too, not just future ones.
    func updateOwnerName(_ name: String, context: ModelContext) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        ownerDisplayName = trimmed.isEmpty ? "Family" : trimmed
        guard isSharingEnabled else { return }
        await pushAllFavorites(context: context)
    }

    // MARK: - Per-song sync

    /// Upserts or deletes this song's record in this user's own zone.
    /// No-ops entirely when sharing is off.
    func syncFavorite(_ song: Song) async {
        guard isSharingEnabled else { return }
        let recordID = CKRecord.ID(recordName: song.stableID, zoneID: zoneID)
        do {
            if song.isFavorite {
                let record = CKRecord(recordType: Self.recordType, recordID: recordID)
                populate(record, from: song)
                _ = try await container.privateCloudDatabase.modifyRecords(saving: [record], deleting: [])
            } else {
                _ = try await container.privateCloudDatabase.modifyRecords(saving: [], deleting: [recordID])
            }
        } catch let error as CKError where error.code == .unknownItem {
            // Already absent -- nothing to delete.
        } catch {
            favoritesSharingLog.error("syncFavorite failed for \(song.stableID, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func pushAllFavorites(context: ModelContext) async {
        guard let songs = try? context.fetch(FetchDescriptor<Song>(predicate: #Predicate { $0.isFavorite == true })) else { return }
        let records = songs.map { song -> CKRecord in
            let record = CKRecord(recordType: Self.recordType, recordID: CKRecord.ID(recordName: song.stableID, zoneID: zoneID))
            populate(record, from: song)
            return record
        }
        // CloudKit caps a single modify operation around a few hundred
        // records -- chunk defensively so a large favorites list can't
        // silently fail the whole batch.
        for chunk in records.chunked(into: 200) {
            do {
                _ = try await container.privateCloudDatabase.modifyRecords(saving: chunk, deleting: [])
            } catch {
                favoritesSharingLog.error("pushAllFavorites chunk failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func populate(_ record: CKRecord, from song: Song) {
        record["songTitle"] = song.title as CKRecordValue
        record["albumTitle"] = (song.album?.title ?? "") as CKRecordValue
        record["personaName"] = (song.album?.persona?.name ?? "") as CKRecordValue
        record["ownerName"] = (ownerDisplayName.isEmpty ? "Family" : ownerDisplayName) as CKRecordValue
        record["favoritedAt"] = Date() as CKRecordValue
    }

    // MARK: - Merged read model

    /// Rebuilds `familyFavorites` from this device's own favorited songs
    /// plus every accepted shared zone. Call on view-appear / pull-to-
    /// refresh / after accepting a new share -- there's no push-driven
    /// live update for this in v1.
    func refresh(context: ModelContext) async {
        isRefreshing = true
        defer { isRefreshing = false }

        var merged: [String: FamilyFavorite] = [:]
        let myName = ownerDisplayName.isEmpty ? "Me" : ownerDisplayName

        if let mySongs = try? context.fetch(FetchDescriptor<Song>(predicate: #Predicate { $0.isFavorite == true })) {
            for song in mySongs {
                merged[song.stableID] = FamilyFavorite(
                    stableID: song.stableID,
                    title: song.title,
                    albumTitle: song.album?.title ?? "",
                    personaName: song.album?.persona?.name ?? "",
                    owners: [myName]
                )
            }
        }

        do {
            let zones = try await container.sharedCloudDatabase.allRecordZones()
            for zone in zones {
                let records = try await fetchFavoriteRecords(in: zone.zoneID, database: container.sharedCloudDatabase)
                for record in records {
                    let stableID = record.recordID.recordName
                    let ownerName = record["ownerName"] as? String ?? "Family"
                    if var existing = merged[stableID] {
                        if !existing.owners.contains(ownerName) {
                            existing.owners.append(ownerName)
                        }
                        merged[stableID] = existing
                    } else {
                        merged[stableID] = FamilyFavorite(
                            stableID: stableID,
                            title: record["songTitle"] as? String ?? "",
                            albumTitle: record["albumTitle"] as? String ?? "",
                            personaName: record["personaName"] as? String ?? "",
                            owners: [ownerName]
                        )
                    }
                }
            }
            lastError = nil
        } catch {
            lastError = "Couldn't refresh family favorites: \(error.localizedDescription)"
            favoritesSharingLog.error("refresh failed: \(error.localizedDescription, privacy: .public)")
        }

        familyFavorites = merged.values.sorted {
            $0.owners.count != $1.owners.count ? $0.owners.count > $1.owners.count : $0.title < $1.title
        }
    }

    private func fetchFavoriteRecords(in zoneID: CKRecordZone.ID, database: CKDatabase) async throws -> [CKRecord] {
        let query = CKQuery(recordType: Self.recordType, predicate: NSPredicate(value: true))
        var records: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?
        repeat {
            let result: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?)
            if let cursor {
                result = try await database.records(continuingMatchFrom: cursor)
            } else {
                result = try await database.records(matching: query, inZoneWith: zoneID)
            }
            records.append(contentsOf: result.matchResults.compactMap { try? $0.1.get() })
            cursor = result.queryCursor
        } while cursor != nil
        return records
    }

    // MARK: - Accepting an incoming share (called from AppDelegate)

    static func acceptShare(_ metadata: CKShare.Metadata) async {
        do {
            let container = CKContainer(identifier: "iCloud.com.luxrecta.Friends-Player")
            _ = try await container.accept(metadata)
            NotificationCenter.default.post(name: .familyFavoritesShareAccepted, object: nil)
        } catch {
            favoritesSharingLog.error("acceptShare failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
