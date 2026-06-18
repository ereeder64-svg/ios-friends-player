//
//  PlaybackEngine.swift
//  Family Player
//

import Foundation
import AVFoundation
import MediaPlayer
import Observation
import SwiftData
import UIKit

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

    // MARK: - Private

    private static let shuffleKey = "playback.shuffleEnabled"
    private static let loopKey = "playback.loopEnabled"

    private let player = AVQueuePlayer()
    private var timeObserverToken: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var activeShareScopes: Set<String> = []

    init() {
        let defaults = UserDefaults.standard
        shuffleEnabled = defaults.bool(forKey: Self.shuffleKey)
        loopEnabled = defaults.bool(forKey: Self.loopKey)

        configureAudioSession()
        installPeriodicTimeObserver()
        installEndObserver()
        installRemoteCommandTargets()
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
        guard currentSong != nil else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            try? AVAudioSession.sharedInstance().setActive(true)
            player.play()
            isPlaying = true
        }
        updateNowPlayingInfoElapsed()
    }

    func stop() {
        player.pause()
        player.removeAllItems()
        currentSong = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func seek(to seconds: Double) {
        let target = CMTimeMakeWithSeconds(seconds, preferredTimescale: 600)
        player.seek(to: target)
        currentTime = seconds
        updateNowPlayingInfoElapsed()
    }

    func playNext() async {
        guard !playbackQueue.isEmpty else { return }
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
        guard let coordinator,
              let shareURL = coordinator.url(for: song.shareName) else {
            lastError = "Share not available for \"\(song.title)\""
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

        if song.downloadCachePath == nil {
            await ensureLocallyAvailable(url: songURL)
        }

        try? AVAudioSession.sharedInstance().setActive(true)
        let item = AVPlayerItem(url: songURL)
        player.removeAllItems()
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

    private func ensureLocallyAvailable(url: URL) async {
        let keys: Set<URLResourceKey> = [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
        guard let values = try? url.resourceValues(forKeys: keys),
              values.isUbiquitousItem == true else { return }
        if values.ubiquitousItemDownloadingStatus == .current { return }

        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        // Poll up to 60 seconds — Wi-Fi typically finishes in 1-3s but cellular
        // can take 15-45s depending on signal strength.
        for _ in 0..<60 {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if let v = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]),
               v.ubiquitousItemDownloadingStatus == .current {
                return
            }
        }
        lastError = "Couldn't download from iCloud. Check your connection and try again."
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
        info[MPMediaItemPropertyTitle] = song.title
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
    }

    private func updateNowPlayingInfoElapsed() {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
