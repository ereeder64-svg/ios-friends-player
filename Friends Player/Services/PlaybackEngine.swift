//
//  PlaybackEngine.swift
//  Friends Player
//

import Foundation
import AVFoundation
import MediaPlayer
import Observation
import SwiftData
import UIKit
import WidgetKit
import OSLog

private let widgetLog = Logger(subsystem: "com.luxrecta.Friends-Player", category: "PlaybackEngine")

@MainActor
@Observable
final class PlaybackEngine {

    // MARK: - Public state

    private(set) var currentSong: Song?
    private(set) var isPlaying: Bool = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var isLoading: Bool = false
    private(set) var lastError: String?

    private(set) var queueSource: [Song] = []
    private(set) var playbackQueue: [Song] = []
    private(set) var currentIndex: Int = 0

    // Lives here (rather than as MainTabView's own local @State) so that
    // RootView can dismiss the full-player sheet before presenting a
    // widget-tapped album. MainTabView's NowPlayingSheet and RootView's
    // deep-linked AlbumDetailView sheet are two independent .sheet
    // modifiers on the same view hierarchy; if the now-playing sheet is
    // already presented when the app is foregrounded via a widget album
    // tap, RootView's own sheet presentation attempt gets silently blocked
    // (iOS won't stack a second modal on a context that already has one
    // presented), so the user just keeps seeing whatever was already up.
    var isShowingNowPlayingSheet: Bool = false

    var shuffleEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(shuffleEnabled, forKey: Self.shuffleKey)
            if oldValue != shuffleEnabled {
                reshufflePreservingCurrent()
            }
        }
    }

    var loopEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(loopEnabled, forKey: Self.loopKey)
        }
    }

    weak var coordinator: ShareAccessCoordinator?
    var modelContext: ModelContext?

    // MARK: - Private

    private static let shuffleKey = "playback.shuffleEnabled"
    private static let loopKey = "playback.loopEnabled"

    private let player = AVQueuePlayer()
    private var timeObserverToken: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var activeShareScopes: Set<String> = []

    nonisolated(unsafe) static weak var sharedEngine: PlaybackEngine?

    init() {
        Self.sharedEngine = self
        let defaults = UserDefaults.standard
        shuffleEnabled = defaults.bool(forKey: Self.shuffleKey)
        loopEnabled = defaults.bool(forKey: Self.loopKey)

        configureAudioSession()
        installPeriodicTimeObserver()
        installEndObserver()
        installRemoteCommandTargets()
        installWidgetIntentObservers()
    }

    // MARK: - Widget integration

    private func installWidgetIntentObservers() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let callback: CFNotificationCallback = { _, _, name, _, _ in
            guard let nameRaw = name?.rawValue as String? else { return }
            DispatchQueue.main.async {
                guard let engine = PlaybackEngine.sharedEngine else { return }
                switch nameRaw {
                case AppGroupConstants.Darwin.playPause:
                    engine.togglePlayPause()
                case AppGroupConstants.Darwin.next:
                    Task { @MainActor in await engine.playNext() }
                case AppGroupConstants.Darwin.previous:
                    Task { @MainActor in await engine.playPrevious() }
                default: break
                }
            }
        }

        for name in [AppGroupConstants.Darwin.playPause,
                     AppGroupConstants.Darwin.next,
                     AppGroupConstants.Darwin.previous] {
            CFNotificationCenterAddObserver(
                center, nil, callback,
                name as CFString, nil, .deliverImmediately
            )
        }
    }

    func forceRepublishSnapshot() {
        publishWidgetSnapshot()
    }

    private var lastDisplayedSong: Song?

    private func publishWidgetSnapshot() {
        widgetLog.debug("publishWidgetSnapshot() entered, currentSong=\(self.currentSong?.title ?? "nil", privacy: .public)")
        if let song = currentSong {
            lastDisplayedSong = song
        }
        let displaySong = currentSong ?? lastDisplayedSong

        let snap = NowPlayingSnapshot(
            hasSong: displaySong != nil,
            songTitle: displaySong?.displayTitle ?? "",
            personaName: displaySong?.album?.persona?.name ?? "",
            albumTitle: displaySong?.album?.title ?? "",
            isPlaying: isPlaying && currentSong != nil,
            updatedAt: Date()
        )
        snap.save()

        if let artPath = displaySong?.album?.artworkCachePath,
           let sharedURL = AppGroupConstants.sharedArtworkURL(),
           FileManager.default.fileExists(atPath: artPath) {
            // WidgetKit rejects ("archival failed") images whose pixel area
            // exceeds a small fixed budget (roughly 1024x1024). Full-resolution
            // album art blows past that, silently breaking widget rendering.
            // Downscale before handing it to the widget's shared container.
            if let resizedData = Self.resizedArtworkData(atPath: artPath, maxDimension: 300) {
                try? resizedData.write(to: sharedURL, options: .atomic)
                widgetLog.debug("publishWidgetSnapshot(): wrote downscaled artwork (\(resizedData.count) bytes) to \(sharedURL.path, privacy: .public)")
            } else {
                widgetLog.error("publishWidgetSnapshot(): failed to downscale artwork at \(artPath, privacy: .public)")
                try? FileManager.default.removeItem(at: sharedURL)
            }
        } else if displaySong == nil, let sharedURL = AppGroupConstants.sharedArtworkURL() {
            try? FileManager.default.removeItem(at: sharedURL)
        }

        recomputeAndPublishRecentAlbums()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Picks the last N distinct albums played (by each album's most recent
    /// song `lastPlayedAt`), most-recent-first. If fewer than N albums have
    /// ever been played (new install, etc.), fills the remaining slots with
    /// random albums from the library so the medium widget's recent-albums
    /// row is never left sparse.
    private func recomputeAndPublishRecentAlbums() {
        guard let modelContext else {
            widgetLog.error("recomputeAndPublishRecentAlbums(): modelContext is nil — skipping.")
            return
        }
        guard let fetchedAlbums = try? modelContext.fetch(FetchDescriptor<Album>()) else {
            RecentAlbumsSnapshot.empty.save()
            clearRecentAlbumArtwork(from: 0)
            return
        }
        let connectedShareNames = coordinator?.connectedShareNames ?? []
        let allAlbums = fetchedAlbums.filter { connectedShareNames.contains($0.shareName) }
        guard !allAlbums.isEmpty else {
            RecentAlbumsSnapshot.empty.save()
            clearRecentAlbumArtwork(from: 0)
            return
        }

        let slotCount = AppGroupConstants.recentAlbumSlotCount

        let played = allAlbums
            .compactMap { album -> (Album, Date)? in
                guard let last = (album.songs ?? []).compactMap(\.lastPlayedAt).max() else { return nil }
                return (album, last)
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)

        var selected: [Album] = Array(played.prefix(slotCount))
        if selected.count < slotCount {
            var usedIDs = Set(selected.map(\.stableID))
            let candidates = allAlbums.filter { !usedIDs.contains($0.stableID) }.shuffled()
            for album in candidates {
                guard selected.count < slotCount else { break }
                selected.append(album)
                usedIDs.insert(album.stableID)
            }
        }

        let entries = selected.map { album in
            RecentAlbumEntry(id: album.stableID, title: album.title, personaName: album.persona?.name ?? "")
        }
        for (i, e) in entries.enumerated() {
            widgetLog.debug("recomputeAndPublishRecentAlbums(): slot \(i) -> id='\(e.id, privacy: .public)' title='\(e.title, privacy: .public)'")
        }
        RecentAlbumsSnapshot(albums: entries).save()

        for (index, album) in selected.enumerated() {
            guard let sharedURL = AppGroupConstants.sharedRecentAlbumArtworkURL(slot: index) else { continue }
            if let path = album.artworkCachePath,
               FileManager.default.fileExists(atPath: path),
               let resized = Self.resizedArtworkData(atPath: path, maxDimension: 160) {
                try? resized.write(to: sharedURL, options: .atomic)
            } else {
                try? FileManager.default.removeItem(at: sharedURL)
            }
        }
        clearRecentAlbumArtwork(from: selected.count)
    }

    private func clearRecentAlbumArtwork(from slot: Int) {
        for index in slot..<AppGroupConstants.recentAlbumSlotCount {
            if let url = AppGroupConstants.sharedRecentAlbumArtworkURL(slot: index) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private static func resizedArtworkData(atPath path: String, maxDimension: CGFloat) -> Data? {
        guard let image = UIImage(contentsOfFile: path), image.size.width > 0, image.size.height > 0 else {
            return nil
        }
        let scale = min(1, maxDimension / max(image.size.width, image.size.height))
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resized.pngData()
    }

    // MARK: - Public API

    func play(song: Song, in scope: [Song]) async {
        guard let index = scope.firstIndex(where: { $0.stableID == song.stableID }) else {
            await play(songs: [song], startingAt: 0)
            return
        }
        await play(songs: scope, startingAt: index)
    }

    func play(songs: [Song], startingAt index: Int) async {
        guard !songs.isEmpty, index < songs.count else { return }
        queueSource = songs
        if shuffleEnabled {
            var rest = songs
            let starting = rest.remove(at: index)
            rest.shuffle()
            playbackQueue = [starting] + rest
            currentIndex = 0
        } else {
            playbackQueue = songs
            currentIndex = index
        }
        await playCurrentItem()
    }

    func playShuffled(_ songs: [Song]) async {
        guard !songs.isEmpty else { return }
        shuffleEnabled = true
        queueSource = songs
        playbackQueue = songs.shuffled()
        currentIndex = 0
        await playCurrentItem()
    }

    func playNext(_ song: Song) {
        guard currentSong != nil else {
            Task { await play(songs: [song], startingAt: 0) }
            return
        }
        let insertIndex = min(currentIndex + 1, playbackQueue.count)
        playbackQueue.insert(song, at: insertIndex)
        queueSource.append(song)
    }

    func playLast(_ song: Song) {
        guard currentSong != nil else {
            Task { await play(songs: [song], startingAt: 0) }
            return
        }
        playbackQueue.append(song)
        queueSource.append(song)
    }

    func togglePlayPause() {
        widgetLog.debug("togglePlayPause() called, currentSong=\(self.currentSong?.title ?? "nil", privacy: .public), isPlaying=\(self.isPlaying)")
        guard currentSong != nil else {
            widgetLog.error("togglePlayPause() returning early — currentSong is nil.")
            return
        }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            try? AVAudioSession.sharedInstance().setActive(true)
            player.play()
            isPlaying = true
        }
        updateNowPlayingInfoElapsed()
        publishWidgetSnapshot()
    }

    func stop() {
        widgetLog.debug("stop() called — clearing currentSong and publishing empty snapshot")
        player.pause()
        player.removeAllItems()
        currentSong = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        publishWidgetSnapshot()
    }

    func seek(to seconds: Double) {
        let target = CMTimeMakeWithSeconds(seconds, preferredTimescale: 600)
        player.seek(to: target)
        currentTime = seconds
        updateNowPlayingInfoElapsed()
    }

    func playNext() async {
        widgetLog.debug("playNext() called, queueCount=\(self.playbackQueue.count), currentIndex=\(self.currentIndex)")
        guard !playbackQueue.isEmpty else {
            widgetLog.error("playNext() returning early — playbackQueue is empty.")
            return
        }
        let next = currentIndex + 1
        if next < playbackQueue.count {
            currentIndex = next
            await playCurrentItem()
        } else if loopEnabled {
            currentIndex = 0
            await playCurrentItem()
        } else {
            stop()
        }
    }

    func playPrevious() async {
        if currentTime > 3 {
            seek(to: 0)
            return
        }
        guard !playbackQueue.isEmpty else { return }
        let prev = currentIndex - 1
        if prev >= 0 {
            currentIndex = prev
            await playCurrentItem()
        } else if loopEnabled {
            currentIndex = playbackQueue.count - 1
            await playCurrentItem()
        } else {
            seek(to: 0)
        }
    }

    // MARK: - Queue helpers

    private func reshufflePreservingCurrent() {
        guard let current = currentSong, !queueSource.isEmpty else { return }
        if shuffleEnabled {
            var rest = queueSource.filter { $0.stableID != current.stableID }
            rest.shuffle()
            playbackQueue = [current] + rest
            currentIndex = 0
        } else {
            playbackQueue = queueSource
            if let idx = queueSource.firstIndex(where: { $0.stableID == current.stableID }) {
                currentIndex = idx
            }
        }
    }

    private func playCurrentItem() async {
        guard currentIndex < playbackQueue.count else { return }
        let song = playbackQueue[currentIndex]
        await load(song: song)
    }

    private func load(song: Song) async {
        widgetLog.debug("load(song:) called for \(song.title, privacy: .public), coordinator is \(self.coordinator == nil ? "nil" : "set", privacy: .public)")
        guard let coordinator,
              let shareURL = coordinator.url(for: song.shareName) else {
            widgetLog.error("load(song:) returning early — share not available for \(song.title, privacy: .public).")
            lastError = "Share not available for \"\(song.displayTitle)\""
            return
        }
        ensureSecurityScope(for: song.shareName, shareURL: shareURL)

        let songURL: URL
        if let path = song.downloadCachePath,
           FileManager.default.fileExists(atPath: path) {
            songURL = URL(fileURLWithPath: path)
        } else {
            songURL = shareURL.appendingPathComponent(song.relativePath)
        }

        lastError = nil
        isLoading = true
        currentSong = song

        // Stop the previous track immediately. Otherwise the old audio keeps
        // playing while we wait for the new file to materialize from iCloud,
        // which can take up to 60s on cellular and makes the UI/audio diverge.
        player.pause()
        player.removeAllItems()
        isPlaying = false

        if song.downloadCachePath == nil {
            let available = await ensureLocallyAvailable(url: songURL)
            if !available {
                if lastError == nil {
                    lastError = "Couldn't download \"\(song.displayTitle)\" from iCloud. Connect to Wi-Fi, or download the song first for offline cellular playback."
                }
                isLoading = false
                currentSong = nil
                return
            }
        }

        try? AVAudioSession.sharedInstance().setActive(true)
        let item = AVPlayerItem(url: songURL)
        player.insert(item, after: nil)
        observeStatus(of: item)
        player.play()
        isPlaying = true

        song.hasBeenPlayed = true
        song.lastPlayedAt = Date()
        song.playCount += 1
        try? song.modelContext?.save()

        updateNowPlayingInfo()
        cacheLyricsInBackground(for: song, url: songURL)
    }

    private func cacheLyricsInBackground(for song: Song, url: URL) {
        guard LyricsService.loadCached(for: song.stableID) == nil else { return }
        let stableID = song.stableID
        Task.detached(priority: .utility) {
            _ = await LyricsService.extract(from: url, stableID: stableID)
        }
    }

    // MARK: - Audio session

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            lastError = "Audio session: \(error.localizedDescription)"
        }

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.handleAudioInterruption(notification)
            }
        }
    }

    private func handleAudioInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            isPlaying = false
            updateNowPlayingInfoElapsed()
        case .ended:
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume), currentSong != nil {
                try? AVAudioSession.sharedInstance().setActive(true)
                player.play()
                isPlaying = true
                updateNowPlayingInfoElapsed()
            }
        @unknown default:
            break
        }
    }

    // MARK: - Security scope

    private func ensureSecurityScope(for shareName: String, shareURL: URL) {
        guard !activeShareScopes.contains(shareName) else { return }
        if shareURL.startAccessingSecurityScopedResource() {
            activeShareScopes.insert(shareName)
        }
    }

    // MARK: - iCloud materialization (user-initiated play OK)

    private func ensureLocallyAvailable(url: URL) async -> Bool {
        let keys: Set<URLResourceKey> = [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
        guard let values = try? url.resourceValues(forKeys: keys),
              values.isUbiquitousItem == true else { return true }
        if values.ubiquitousItemDownloadingStatus == .current ||
           values.ubiquitousItemDownloadingStatus == .downloaded { return true }

        do {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
        } catch {
            lastError = "iCloud download failed: \(error.localizedDescription)"
            return false
        }

        // Poll up to 60 seconds — Wi-Fi typically finishes in 1-3s but cellular
        // can take 15-45s. Accept either .current or .downloaded so cellular
        // playback can start as soon as enough bytes are local.
        for _ in 0..<60 {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if let v = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]),
               v.ubiquitousItemDownloadingStatus == .current ||
               v.ubiquitousItemDownloadingStatus == .downloaded {
                return true
            }
        }
        return false
    }

    func clearLastError() {
        lastError = nil
    }

    // MARK: - Observers

    private func installPeriodicTimeObserver() {
        let interval = CMTimeMakeWithSeconds(0.5, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.currentTime = CMTimeGetSeconds(time)
                if let item = self.player.currentItem {
                    let dur = CMTimeGetSeconds(item.duration)
                    if dur.isFinite && dur > 0 {
                        self.duration = dur
                    }
                }
                self.updateNowPlayingInfoElapsed()
            }
        }
    }

    private func installEndObserver() {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { @MainActor in
                    await self.playNext()
                }
            }
        }
    }

    private func observeStatus(of item: AVPlayerItem) {
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            let status = item.status
            let durSec = CMTimeGetSeconds(item.duration)
            let errMsg = item.error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch status {
                case .readyToPlay:
                    self.isLoading = false
                    if durSec.isFinite && durSec > 0 {
                        self.duration = durSec
                        self.updateNowPlayingInfo()
                        if let song = self.currentSong, abs(song.duration - durSec) > 0.5 {
                            song.duration = durSec
                            song.metadataLoaded = true
                            try? song.modelContext?.save()
                        }
                    }
                case .failed:
                    self.isLoading = false
                    self.lastError = errMsg ?? "Playback failed"
                default: break
                }
            }
        }
    }

    // MARK: - Now Playing Info / Remote commands

    private func installRemoteCommandTargets() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            guard let self, self.currentSong != nil else { return .noSuchContent }
            if !self.isPlaying { self.togglePlayPause() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            guard let self, self.currentSong != nil else { return .noSuchContent }
            if self.isPlaying { self.togglePlayPause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self, self.currentSong != nil else { return .noSuchContent }
            self.togglePlayPause()
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in await self?.playNext() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in await self?.playPrevious() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self,
                  let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self.seek(to: e.positionTime)
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        guard let song = currentSong else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = song.displayTitle
        info[MPMediaItemPropertyArtist] = song.album?.persona?.name ?? "Eric Reeder"
        info[MPMediaItemPropertyAlbumTitle] = song.album?.title ?? ""
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0

        if let path = song.album?.artworkCachePath,
           let img = UIImage(contentsOfFile: path) {
            let artwork = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
            info[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        publishWidgetSnapshot()
    }

    private func updateNowPlayingInfoElapsed() {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
