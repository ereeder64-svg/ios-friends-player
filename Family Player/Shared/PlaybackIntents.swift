//
//  PlaybackIntents.swift
//  Family Player + FamilyPlayerWidget (shared)
//

import AppIntents
import Foundation
import WidgetKit

struct PlayPauseIntent: AppIntent {
    static var title: LocalizedStringResource = "Play / Pause"
    static var description = IntentDescription("Toggle play and pause in Family Player.")
    static var openAppWhenRun: Bool = false
    static var isDiscoverable: Bool = true

    init() {}

    func perform() async throws -> some IntentResult {
        // Optimistically flip + persist the shared snapshot so the widget's
        // icon updates immediately. Without this, the icon depends on a
        // round trip through the host app (Darwin notification -> main
        // actor -> re-publish snapshot), which frequently loses the race
        // against WidgetKit's automatic post-intent reload and leaves the
        // button showing the stale (pre-toggle) state.
        var snapshot = NowPlayingSnapshot.load()
        if snapshot.hasSong {
            snapshot.isPlaying.toggle()
            snapshot.save()
        }

        AppGroupConstants.sharedDefaults()?.set("playPause", forKey: AppGroupConstants.Keys.lastWidgetRequest)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(AppGroupConstants.Darwin.playPause as CFString),
            nil, nil, true
        )
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct NextTrackIntent: AppIntent {
    static var title: LocalizedStringResource = "Next Track"
    static var description = IntentDescription("Play the next song in the current queue.")
    static var openAppWhenRun: Bool = false
    static var isDiscoverable: Bool = true

    init() {}

    func perform() async throws -> some IntentResult {
        AppGroupConstants.sharedDefaults()?.set("next", forKey: AppGroupConstants.Keys.lastWidgetRequest)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(AppGroupConstants.Darwin.next as CFString),
            nil, nil, true
        )
        return .result()
    }
}

struct OpenAlbumIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Album"
    static var description = IntentDescription("Open a specific album in Family Player.")
    // Unlike the playback intents above, this one needs the host app in the
    // foreground so it can actually navigate — the widget can't push a
    // detail screen itself.
    static var openAppWhenRun: Bool = true
    static var isDiscoverable: Bool = false

    @Parameter(title: "Album ID")
    var albumID: String

    init() {
        self.albumID = ""
    }

    init(albumID: String) {
        self.albumID = albumID
    }

    func perform() async throws -> some IntentResult {
        AppGroupConstants.sharedDefaults()?.set(albumID, forKey: AppGroupConstants.Keys.pendingAlbumDeepLinkID)
        return .result()
    }
}

struct PreviousTrackIntent: AppIntent {
    static var title: LocalizedStringResource = "Previous Track"
    static var description = IntentDescription("Play the previous song or restart the current one.")
    static var openAppWhenRun: Bool = false
    static var isDiscoverable: Bool = true

    init() {}

    func perform() async throws -> some IntentResult {
        AppGroupConstants.sharedDefaults()?.set("previous", forKey: AppGroupConstants.Keys.lastWidgetRequest)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(AppGroupConstants.Darwin.previous as CFString),
            nil, nil, true
        )
        return .result()
    }
}
