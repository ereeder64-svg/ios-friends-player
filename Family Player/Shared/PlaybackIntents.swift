//
//  PlaybackIntents.swift
//  Family Player + FamilyPlayerWidget (shared)
//

import AppIntents
import Foundation

struct PlayPauseIntent: AppIntent {
    static var title: LocalizedStringResource = "Play / Pause"
    static var description = IntentDescription("Toggle play and pause in Family Player.")
    static var openAppWhenRun: Bool = false
    static var isDiscoverable: Bool = true

    init() {}

    func perform() async throws -> some IntentResult {
        AppGroupConstants.sharedDefaults()?.set("playPause", forKey: AppGroupConstants.Keys.lastWidgetRequest)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(AppGroupConstants.Darwin.playPause as CFString),
            nil, nil, true
        )
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
