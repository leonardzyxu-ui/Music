import AppKit
import AVFoundation
import Foundation
import MediaPlayer
import SwiftUI

@MainActor
final class PlaybackStore: ObservableObject {
    @Published private(set) var currentSong: Song?
    @Published private(set) var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published var volume: Float = 0.9 {
        didSet { player.volume = volume }
    }
    @Published var shuffle = false {
        didSet { updateNowPlayingInfo() }
    }
    @Published var repeatMode = 0 {
        didSet { updateNowPlayingInfo() }
    }
    @Published private(set) var queueSnapshot = QueueSnapshot(source: "Idle", songIDs: [], createdAt: Date())

    private let player = AVPlayer()
    private weak var library: LibraryStore?
    private var queue: [Song] = []
    private var currentIndex = -1
    private var timeObserver: Any?
    private var session: PlaybackSession?
    private var repeatStreak = 0
    private var lastSongID: String?

    struct PlaybackSession {
        var songID: String
        var startedAt: Date
        var lastPosition: TimeInterval
        var maxPosition: TimeInterval
        var listenedSeconds: TimeInterval
        var duration: TimeInterval
        var manualSelection: Bool
    }

    init() {
        player.volume = volume
        installTimeObserver()
        installEndObserver()
        installRemoteCommands()
    }

    func attach(library: LibraryStore) {
        self.library = library
    }

    @discardableResult
    func setVolume(_ level: Float) -> Float {
        volume = min(1, max(0, level))
        return volume
    }

    @discardableResult
    func setShuffle(_ enabled: Bool) -> Bool {
        shuffle = enabled
        return shuffle
    }

    @discardableResult
    func setRepeatMode(_ mode: Int) -> Int {
        repeatMode = min(2, max(0, mode))
        return repeatMode
    }

    func queueStatePayload() -> [String: Any] {
        [
            "source": queueSnapshot.source,
            "songIds": queueSnapshot.songIDs,
            "createdAt": ISO8601DateFormatter().string(from: queueSnapshot.createdAt),
            "currentIndex": currentIndex,
            "count": queue.count
        ]
    }

    func play(song: Song, queue songs: [Song], source: String, manual: Bool = true) {
        let baseQueue = songs.isEmpty ? [song] : songs
        let nextQueue = shuffle ? shuffledQueue(baseQueue, keeping: song) : baseQueue
        queue = nextQueue
        queueSnapshot = QueueSnapshot(source: source, songIDs: nextQueue.map(\.id), createdAt: Date())
        let index = nextQueue.firstIndex(where: { $0.id == song.id }) ?? 0
        playAtIndex(index, manual: manual, finalizeReason: "manual-switch")
    }

    func playSmartPicker(from library: LibraryStore) {
        let songs = library.smartSongs
        guard let first = songs.first else { return }
        play(song: first, queue: songs, source: "Your Pick snapshot", manual: true)
    }

    func pause() {
        updateSessionPosition()
        player.pause()
        isPlaying = false
        updateNowPlayingInfo()
    }

    func resume() {
        guard currentSong != nil else {
            if let first = library?.visibleSongs().first, let visible = library?.visibleSongs() {
                play(song: first, queue: visible, source: "Visible songs", manual: true)
            }
            return
        }
        if session == nil, let currentSong {
            beginSession(for: currentSong, manual: false)
        }
        player.play()
        isPlaying = true
        updateNowPlayingInfo()
    }

    func stop() {
        finalizeSession(reason: "stop")
        player.pause()
        player.replaceCurrentItem(with: nil)
        currentSong = nil
        queue.removeAll()
        queueSnapshot = QueueSnapshot(source: "Idle", songIDs: [], createdAt: Date())
        currentIndex = -1
        currentTime = 0
        duration = 0
        isPlaying = false
        updateNowPlayingInfo()
    }

    func next() {
        guard !queue.isEmpty else { return }
        let nextIndex: Int
        if currentIndex + 1 < queue.count {
            nextIndex = currentIndex + 1
        } else if repeatMode == 1 {
            nextIndex = 0
        } else {
            stop()
            return
        }
        playAtIndex(nextIndex, manual: false, finalizeReason: "next")
    }

    func previous() {
        guard !queue.isEmpty else { return }
        if currentTime > 4 {
            seek(to: 0)
            return
        }
        let previousIndex: Int
        if currentIndex > 0 {
            previousIndex = currentIndex - 1
        } else if repeatMode == 1 {
            previousIndex = max(0, queue.count - 1)
        } else {
            previousIndex = 0
        }
        playAtIndex(previousIndex, manual: false, finalizeReason: "previous")
    }

    func seek(to seconds: TimeInterval) {
        let safe = max(0, min(seconds, duration))
        player.seek(to: CMTime(seconds: safe, preferredTimescale: 600))
        currentTime = safe
        updateSessionPosition(forcePosition: safe)
        updateNowPlayingInfo()
    }

    func playSongID(_ id: String) -> Bool {
        guard let library, let song = library.song(id: id) else { return false }
        let visible = library.visibleSongs()
        let base = visible.contains(where: { $0.id == id }) ? visible : library.songs
        play(song: song, queue: base, source: "Bridge snapshot", manual: true)
        return true
    }

    private func playAtIndex(_ index: Int, manual: Bool, finalizeReason: String) {
        finalizeSession(reason: finalizeReason)
        guard queue.indices.contains(index) else { return }
        let song = queue[index]
        currentIndex = index
        currentSong = song
        currentTime = 0
        duration = song.duration
        let item = AVPlayerItem(url: song.fileURL)
        player.replaceCurrentItem(with: item)
        beginSession(for: song, manual: manual)
        player.play()
        isPlaying = true
        updateNowPlayingInfo()
    }

    private func shuffledQueue(_ songs: [Song], keeping firstSong: Song) -> [Song] {
        var rest = songs.filter { $0.id != firstSong.id }
        rest.shuffle()
        return [firstSong] + rest
    }

    private func beginSession(for song: Song, manual: Bool) {
        if lastSongID == song.id {
            repeatStreak += 1
        } else {
            repeatStreak = 1
        }
        lastSongID = song.id
        session = PlaybackSession(
            songID: song.id,
            startedAt: Date(),
            lastPosition: 0,
            maxPosition: 0,
            listenedSeconds: 0,
            duration: song.duration,
            manualSelection: manual
        )
    }

    private func updateSessionPosition(forcePosition: TimeInterval? = nil) {
        guard var session else { return }
        let position = forcePosition ?? currentTime
        let delta = position - session.lastPosition
        if delta > 0, delta < 8 {
            session.listenedSeconds += delta
        }
        session.lastPosition = position
        session.maxPosition = max(session.maxPosition, position)
        self.session = session
    }

    private func finalizeSession(reason: String) {
        updateSessionPosition()
        guard let session else { return }
        self.session = nil
        let duration = max(session.duration, self.duration)
        let completionRatio = duration > 0 ? max(0, min(1, session.maxPosition / duration)) : 0
        let skipReason = ["next", "previous", "manual-switch"].contains(reason)
        let skipped = skipReason && completionRatio < 0.35
        let event = ListeningEvent(
            songID: session.songID,
            listenedSeconds: session.listenedSeconds,
            durationSeconds: duration,
            completionRatio: completionRatio,
            endedReason: reason,
            repeatInRowCount: repeatStreak,
            manualSelection: session.manualSelection,
            skipped: skipped,
            earlySkip: skipped && session.listenedSeconds <= 5,
            createdAt: Date()
        )
        if session.listenedSeconds >= 0.75 || event.earlySkip || session.manualSelection {
            library?.record(event)
        }
    }

    private func installTimeObserver() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                guard self.currentSong != nil else {
                    self.currentTime = 0
                    self.duration = 0
                    self.updateNowPlayingInfo()
                    return
                }
                self.currentTime = CMTimeGetSeconds(time)
                self.updateSessionPosition()
                self.updateNowPlayingInfo()
            }
        }
    }

    private func installEndObserver() {
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.handleEnded()
            }
        }
    }

    private func handleEnded() {
        finalizeSession(reason: "complete")
        if repeatMode == 2 {
            player.seek(to: .zero)
            if let currentSong {
                beginSession(for: currentSong, manual: false)
            }
            player.play()
            isPlaying = true
            return
        }
        next()
    }

    private func installRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.stopCommand.isEnabled = true
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.isEnabled = true

        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.isPlaying ? self.pause() : self.resume()
            }
            return .success
        }
        commandCenter.stopCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.stop() }
            return .success
        }
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor in self?.seek(to: event.positionTime) }
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        guard let song = currentSong else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        let info: [String: Any] = [
            MPMediaItemPropertyTitle: song.title,
            MPMediaItemPropertyArtist: song.artist,
            MPMediaItemPropertyAlbumTitle: song.album,
            MPMediaItemPropertyPlaybackDuration: max(duration, song.duration),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyPlaybackQueueIndex: max(0, currentIndex),
            MPNowPlayingInfoPropertyPlaybackQueueCount: queue.count,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyIsLiveStream: false
        ]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
