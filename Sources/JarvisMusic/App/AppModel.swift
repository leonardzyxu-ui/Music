import AppKit
import Foundation

@MainActor
final class AppModel: ObservableObject {
    let library = LibraryStore()
    let playback = PlaybackStore()
    let youtube = YouTubeImportService()

    @Published var bridgeStatus = "Bridge stopped"
    @Published var bridgeToken = ""
    @Published var youtubeAddress = "https://www.youtube.com"
    @Published var youtubeCurrentURL = "https://www.youtube.com"
    @Published var youtubePageTitle = "YouTube"
    @Published var importPreview: ImportPreview?
    @Published var importTitle = ""
    @Published var importStatus = "Search YouTube or paste a video URL, then rename before saving."
    @Published var importActivityLog: [ImportActivityEntry] = []
    @Published var isImporting = false
    @Published private var youtubeImportProgressOverride: Double?

    private var started = false
    private var server: LocalControlServer?
    private var lastImportFailureCode: String?
    private var lastImportFailureRetryable: Bool?
    private var lastImportRecoverySuggestion: String?

    var bridgeBaseURL: String {
        "http://\(AppConfiguration.bridgeHost):\(AppConfiguration.bridgePort)"
    }

    var youtubeImportProgressFraction: Double {
        if let youtubeImportProgressOverride {
            return min(max(youtubeImportProgressOverride, 0), 1)
        }
        guard let entry = importActivityLog.first(where: { $0.stage != nil }) else {
            return isImporting ? 0.04 : 0
        }
        if entry.state == .success, entry.stage == .finished {
            return 1
        }
        if entry.state == .failure {
            return entry.stage?.progressFraction ?? 0
        }
        return max(isImporting ? 0.04 : 0, entry.stage?.progressFraction ?? 0)
    }

    func start() async {
        guard !started else { return }
        started = true
        playback.attach(library: library)
        bridgeToken = loadOrCreateToken()
        library.searchQuery = ""
        await library.load()
        startBridge()
    }

    func startBridge() {
        guard server == nil else { return }
        let server = LocalControlServer(port: AppConfiguration.bridgePort) { [weak self] request in
            guard let self else {
                return BridgeReply.error("The app model is not available.", status: 500)
            }
            return await self.handleBridge(request)
        }
        do {
            try server.start()
            self.server = server
            bridgeStatus = "Bridge listening on \(bridgeBaseURL)"
        } catch {
            bridgeStatus = "Bridge failed: \(error.localizedDescription)"
        }
    }

    func openYouTube(url: URL? = nil, search: String? = nil) {
        library.selection = .youtube
        if let search, !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let encoded = search.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? search
            youtubeAddress = "https://www.youtube.com/results?search_query=\(encoded)"
            importPreview = nil
            importTitle = ""
            importStatus = "Choose a video, rename it, then import."
        } else if let url {
            youtubeAddress = url.absoluteString
        } else {
            youtubeAddress = "https://www.youtube.com"
            importPreview = nil
            importTitle = ""
            importStatus = "Search YouTube or paste a video URL, then rename before saving."
        }
        youtubeCurrentURL = youtubeAddress
        noteImportActivity(.info, stage: nil, title: "YouTube browser opened", detail: youtubeAddress)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openOriginalVideo(for song: Song) {
        guard let url = song.sourceURL else { return }
        openYouTube(url: url)
    }

    func previewCurrentYouTubeURL() async {
        guard let url = URL(string: youtubeCurrentURL) else {
            importStatus = "That is not a valid URL."
            noteImportActivity(.failure, stage: .failed, title: "Metadata preview failed", detail: importStatus)
            return
        }
        noteImportActivity(.active, stage: .metadata, title: YouTubeImportStage.metadata.title, detail: "Reading the current YouTube page.")
        do {
            let preview = try await youtube.fetchMetadata(url: url)
            importPreview = preview
            importTitle = preview.title
            importStatus = "Ready to import: \(preview.title)"
            noteImportActivity(.success, stage: .metadata, title: "Metadata ready", detail: preview.title)
        } catch {
            importStatus = friendly(error)
            noteImportActivity(.failure, stage: .failed, title: "Metadata preview failed", detail: failureDetail(for: error))
        }
    }

    func importCurrentYouTubeURL() async {
        guard let url = URL(string: youtubeCurrentURL) else {
            importStatus = "That is not a valid URL."
            lastImportFailureCode = "invalid_youtube_url"
            lastImportFailureRetryable = false
            lastImportRecoverySuggestion = "Paste a normal YouTube URL."
            noteImportActivity(.failure, stage: .failed, title: "Import failed", detail: importStatus)
            return
        }
        await importYouTube(url: url, title: importTitle)
    }

    @discardableResult
    func importYouTube(url: URL, title: String?) async -> Song? {
        isImporting = true
        youtubeImportProgressOverride = 0
        importStatus = "Importing audio with yt-dlp and ffmpeg..."
        lastImportFailureCode = nil
        lastImportFailureRetryable = nil
        lastImportRecoverySuggestion = nil
        defer { isImporting = false }
        do {
            let fileURL = try await youtube.importAudio(url: url, titleOverride: title) { [weak self] stage, detail, fraction in
                if let fraction {
                    self?.youtubeImportProgressOverride = fraction
                }
                self?.noteImportActivity(.active, stage: stage, title: stage.title, detail: detail)
            }
            youtubeImportProgressOverride = 0.96
            noteImportActivity(.active, stage: .refreshing, title: YouTubeImportStage.refreshing.title, detail: "Scanning the shared MP3 folder.")
            let song = await library.upsertImportedSong(from: fileURL, title: title, sourceURL: url)
            await library.scanLibrary(silent: true)
            youtubeImportProgressOverride = 1
            importStatus = "Imported \(song.title)."
            noteImportActivity(.success, stage: .finished, title: YouTubeImportStage.finished.title, detail: song.title)
            lastImportFailureCode = nil
            lastImportFailureRetryable = nil
            lastImportRecoverySuggestion = nil
            return song
        } catch {
            youtubeImportProgressOverride = nil
            importStatus = friendly(error)
            lastImportFailureCode = bridgeErrorCode(for: error, fallback: "youtube_import_failed")
            lastImportFailureRetryable = retryable(for: error)
            lastImportRecoverySuggestion = recoverySuggestion(for: error)
            noteImportActivity(.failure, stage: .failed, title: YouTubeImportStage.failed.title, detail: failureDetail(for: error))
            return nil
        }
    }

    func noteImportActivity(_ state: ImportActivityState, stage: YouTubeImportStage?, title: String, detail: String) {
        let cleanTitle = MusicFormatters.clean(title, maxLength: 120)
        let cleanDetail = MusicFormatters.clean(detail, maxLength: 240)
        if state != .active {
            removeCompletedActiveImportRows(stage: stage, title: cleanTitle)
        }
        if state == .active, let stage, let index = importActivityLog.firstIndex(where: { $0.state == .active && $0.stage == stage }) {
            importActivityLog[index].createdAt = Date()
            importActivityLog[index].title = cleanTitle.isEmpty ? "YouTube Import" : cleanTitle
            importActivityLog[index].detail = cleanDetail
            return
        }
        importActivityLog.insert(
            ImportActivityEntry(
                state: state,
                stage: stage,
                title: cleanTitle.isEmpty ? "YouTube Import" : cleanTitle,
                detail: cleanDetail
            ),
            at: 0
        )
        if importActivityLog.count > 12 {
            importActivityLog.removeLast(importActivityLog.count - 12)
        }
    }

    func clearImportActivity() {
        importActivityLog.removeAll()
    }

    func moveSelectedSongsToTrash() async {
        let songs = library.selectedSongs
        guard !songs.isEmpty else { return }

        let title = songs.count == 1 ? "Move Song to Recycle Bin" : "Move Songs to Recycle Bin"
        let detail: String
        if songs.count == 1, let song = songs.first {
            detail = "Move '\(song.title)' to the Recycle Bin?"
        } else {
            detail = "Move \(songs.count) selected songs to the Recycle Bin?"
        }

        guard Prompt.confirm(title: title, message: detail) else { return }

        if let currentSong = playback.currentSong, songs.contains(where: { $0.id == currentSong.id }) {
            playback.stop()
        }

        do {
            try await library.moveSongsToTrash(songs)
        } catch {
            Prompt.error(
                title: "Couldn’t Move to Recycle Bin",
                message: error.localizedDescription
            )
        }
    }

    private func removeCompletedActiveImportRows(stage: YouTubeImportStage?, title: String) {
        let lowerTitle = title.lowercased()
        importActivityLog.removeAll { entry in
            guard entry.state == .active else { return false }
            if stage == .finished || stage == .failed {
                return entry.stage != nil
            }
            if let stage {
                return entry.stage == stage
            }
            if lowerTitle.contains("search") {
                return entry.title.lowercased().contains("searching youtube")
            }
            return false
        }
    }

    func handleBridge(_ request: BridgeRequest) async -> BridgeReply {
        if request.path != "/health" {
            guard authorized(request) else {
                return .error("Missing or invalid local control token.", status: 401, code: "unauthorized")
            }
        }

        switch (request.method, request.path) {
        case ("GET", "/health"):
            return .ok([
                "app": AppConfiguration.appName,
                "status": "running",
                "bridge": bridgeBaseURL,
                "requiresToken": true
            ])
        case ("GET", "/capabilities"):
            return .ok(capabilitiesPayload())
        case ("GET", "/status"):
            return .ok(statusPayload())
        case ("GET", "/songs"):
            let q = request.string("q") ?? ""
            if q.isEmpty {
                return .ok(["songs": library.songs.map(songPayload)])
            }
            let matches = library.searchMatches(q, limit: 50)
            return .ok([
                "query": q,
                "songs": matches.map { songPayload($0.song) },
                "candidates": matches.map(searchMatchPayload)
            ])
        case ("GET", "/search"):
            let q = request.string("q") ?? ""
            let matches = library.searchMatches(q, limit: 20)
            return .ok([
                "query": q,
                "songs": matches.map { songPayload($0.song) },
                "candidates": matches.map(searchMatchPayload)
            ])
        case ("GET", "/groups"):
            return .ok([
                "groups": ["All Songs", "Your Pick"] + library.groups,
                "playlists": groupPayloads()
            ])
        case ("GET", "/playlist/songs"), ("GET", "/group/songs"):
            guard let target = playlistTarget(from: request) else {
                return .error("Playlist not found. Use 'All Songs', 'Your Pick', or one of the names from /groups.", status: 404, code: "playlist_not_found")
            }
            return .ok([
                "playlist": playlistPayload(target),
                "songs": target.songs.map(songPayload)
            ])
        case ("GET", "/now-playing"):
            return .ok(["nowPlaying": playback.currentSong.map(songPayload) ?? NSNull(), "playing": playback.isPlaying])
        case ("GET", "/playback-state"):
            return .ok(playbackStatePayload())
        case ("GET", "/volume"):
            return .ok(["volume": playback.volume])
        case ("GET", "/diagnostics/library-sync"):
            return .ok(library.syncDiagnosticsPayload())
        case ("GET", "/diagnostics/source-metadata"):
            guard let id = request.string("id"), let song = library.song(id: id) else {
                return .error("Song not found.", status: 404, code: "song_not_found")
            }
            let recovered = await MetadataReader.readSong(at: song.fileURL, existing: nil)
            return .ok([
                "song": songPayload(song),
                "recoveredSourceURL": recovered.sourceURLString ?? NSNull(),
                "dbSourceURL": song.sourceURLString ?? NSNull(),
                "metadataHasSourceURL": recovered.sourceURLString != nil
            ])
        case ("GET", "/diagnostics/window-controls"):
            return .ok(MusicWindowControls.diagnosticsPayload())
        case ("POST", "/diagnostics/process-timeout"):
            do {
                return .ok(try await processTimeoutDiagnosticPayload())
            } catch {
                return .error(friendly(error), status: 500, code: "process_timeout_diagnostic_failed")
            }
        case ("GET", "/diagnostics/youtube-helper-error"), ("POST", "/diagnostics/youtube-helper-error"):
            return .ok(youtubeHelperErrorDiagnosticPayload(request))
        case ("POST", "/play"):
            return playBridge(request)
        case ("POST", "/play-by-query"):
            return playBridge(request)
        case ("POST", "/play-by-id"):
            return playBridge(request)
        case ("POST", "/playlist/select"), ("POST", "/group/select"):
            guard let target = playlistTarget(from: request) else {
                return .error("Playlist not found. Use 'All Songs', 'Your Pick', or one of the names from /groups.", status: 404, code: "playlist_not_found")
            }
            library.selection = target.selection
            return .ok(["message": "Selected \(target.name)", "playlist": playlistPayload(target)])
        case ("POST", "/playlist/play"), ("POST", "/group/play"):
            guard let target = playlistTarget(from: request) else {
                return .error("Playlist not found. Use 'All Songs', 'Your Pick', or one of the names from /groups.", status: 404, code: "playlist_not_found")
            }
            guard let first = target.songs.first else {
                return .error("\(target.name) does not have any songs to play.", code: "playlist_empty")
            }
            if target.selection == .smartPicker {
                playback.playSmartPicker(from: library)
            } else {
                playback.play(song: first, queue: target.songs, source: "\(target.name) playlist snapshot", manual: true)
            }
            library.selection = target.selection
            return .ok([
                "message": "Playing \(target.name)",
                "playlist": playlistPayload(target),
                "song": playback.currentSong.map(songPayload) ?? songPayload(first)
            ])
        case ("POST", "/playlist/create"), ("POST", "/group/create"):
            guard let name = request.string("name") ?? request.string("group") ?? request.string("playlist") else {
                return .error("Provide a playlist name in 'name', 'group', or 'playlist'.", code: "missing_playlist_name")
            }
            let cleanName = MusicFormatters.clean(name, maxLength: 60)
            guard !cleanName.isEmpty, cleanName != "All Songs", cleanName != "Your Pick" else {
                return .error("Choose a custom playlist name other than All Songs or Your Pick.", code: "reserved_playlist_name")
            }
            library.addGroup(cleanName)
            guard let target = playlistTarget(name: cleanName) else {
                return .error("The playlist was not created.", code: "playlist_create_failed")
            }
            return .ok(["message": "Created playlist \(cleanName)", "playlist": playlistPayload(target)])
        case ("POST", "/playlist/rename"), ("POST", "/group/rename"):
            guard let oldTarget = playlistTarget(from: request, oldNameKeys: true) else {
                return .error("Playlist to rename was not found.", status: 404, code: "playlist_not_found")
            }
            guard oldTarget.type == "playlist" else {
                return .error("Only custom playlists can be renamed.", code: "reserved_playlist_name")
            }
            guard let newName = request.string("newName") ?? request.string("to") ?? request.string("name") else {
                return .error("Provide the new playlist name in 'newName', 'to', or 'name'.", code: "missing_playlist_name")
            }
            let cleanName = MusicFormatters.clean(newName, maxLength: 60)
            guard !cleanName.isEmpty, cleanName != "All Songs", cleanName != "Your Pick" else {
                return .error("Choose a custom playlist name other than All Songs or Your Pick.", code: "reserved_playlist_name")
            }
            library.renameGroup(oldTarget.name, to: cleanName)
            guard let renamed = playlistTarget(name: cleanName) else {
                return .error("The playlist was not renamed.", code: "playlist_rename_failed")
            }
            return .ok(["message": "Renamed playlist \(oldTarget.name) to \(cleanName)", "playlist": playlistPayload(renamed)])
        case ("POST", "/playlist/delete"), ("POST", "/group/delete"):
            guard let target = playlistTarget(from: request) else {
                return .error("Playlist to delete was not found.", status: 404, code: "playlist_not_found")
            }
            guard target.type == "playlist" else {
                return .error("Only custom playlists can be deleted.", code: "reserved_playlist_name")
            }
            library.deleteGroup(target.name)
            return .ok(["message": "Deleted playlist \(target.name)", "deleted": target.name])
        case ("POST", "/song/move"):
            guard let id = request.string("id"), let song = library.song(id: id) else {
                return .error("Song not found.", status: 404, code: "song_not_found")
            }
            guard let group = request.string("group") ?? request.string("playlist") ?? request.string("name") else {
                return .error("Provide a destination playlist in 'group', 'playlist', or 'name'.", code: "missing_playlist_name")
            }
            let cleanGroup = MusicFormatters.clean(group, maxLength: 60)
            guard !cleanGroup.isEmpty, cleanGroup != "Your Pick" else {
                return .error("Choose All Songs or a custom playlist. Your Pick is smart and cannot accept manual moves.", code: "reserved_playlist_name")
            }
            library.move(song: song, to: cleanGroup)
            guard let updated = library.song(id: id) else {
                return .error("Song moved but could not be reloaded.", code: "song_move_failed")
            }
            return .ok(["message": "Moved \(updated.title) to \(updated.group)", "song": songPayload(updated)])
        case ("POST", "/pause"):
            playback.pause()
            return .ok(["message": "Paused"])
        case ("POST", "/resume"):
            playback.resume()
            return .ok(["message": "Resumed"])
        case ("POST", "/stop"):
            playback.stop()
            return .ok(["message": "Stopped"])
        case ("POST", "/volume"):
            guard let rawLevel = request.string("level") ?? request.string("value") ?? request.string("volume"),
                  let level = Float(rawLevel) else {
                return .error("Provide a volume level from 0.0 to 1.0 in 'level', 'value', or 'volume'.", code: "missing_volume")
            }
            let volume = playback.setVolume(level)
            return .ok(["message": "Volume set", "volume": volume])
        case ("POST", "/seek"):
            guard let rawSeconds = request.string("seconds") ?? request.string("time") ?? request.string("position"),
                  let seconds = TimeInterval(rawSeconds) else {
                return .error("Provide a seek position in seconds using 'seconds', 'time', or 'position'.", code: "missing_seek_position")
            }
            playback.seek(to: seconds)
            return .ok(["message": "Seeked", "playback": playbackStatePayload()])
        case ("POST", "/shuffle"):
            guard let rawEnabled = request.string("enabled") ?? request.string("value") ?? request.string("shuffle") else {
                return .error("Provide shuffle as true or false in 'enabled', 'value', or 'shuffle'.", code: "missing_shuffle")
            }
            guard let enabled = boolValue(rawEnabled) else {
                return .error("Shuffle must be true or false.", code: "invalid_shuffle")
            }
            return .ok(["message": "Shuffle updated", "shuffle": playback.setShuffle(enabled), "playback": playbackStatePayload()])
        case ("POST", "/repeat"):
            guard let rawMode = request.string("mode") ?? request.string("value") ?? request.string("repeat") else {
                return .error("Provide repeat mode as off, all, one, 0, 1, or 2.", code: "missing_repeat")
            }
            guard let mode = repeatModeValue(rawMode) else {
                return .error("Repeat mode must be off, all, one, 0, 1, or 2.", code: "invalid_repeat")
            }
            return .ok(["message": "Repeat updated", "repeatMode": playback.setRepeatMode(mode), "repeatModeName": repeatModeName(mode), "playback": playbackStatePayload()])
        case ("POST", "/diagnostics/window-control-action"):
            guard let action = request.string("action"), ["close", "minimize", "zoom"].contains(action) else {
                return .error("Provide action as close, minimize, or zoom.", code: "missing_window_control_action")
            }
            let performed = MusicWindowControls.perform(action)
            return .ok(["message": "Window control action dispatched", "action": action, "performed": performed])
        case ("POST", "/next"):
            playback.next()
            return .ok(["message": "Skipped to next"])
        case ("POST", "/previous"):
            playback.previous()
            return .ok(["message": "Returned to previous"])
        case ("POST", "/refresh-library"):
            await library.scanLibrary()
            return .ok(["message": "Library refreshed", "songCount": library.songs.count])
        case ("POST", "/refresh-smart-picker"):
            library.refreshSmartPicker()
            return .ok(["message": "Smart Picker refreshed", "songs": library.smartSongs.map(songPayload)])
        case ("POST", "/youtube/open"):
            let url = request.string("url").flatMap(URL.init(string:))
            openYouTube(url: url, search: request.string("search"))
            return .ok(["message": "YouTube browser opened", "url": youtubeAddress])
        case ("GET", "/youtube/search"), ("POST", "/youtube/search"):
            guard let query = request.string("q") ?? request.string("query"), !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .error("Provide a YouTube search query in the 'q' or 'query' field.", code: "missing_query")
            }
            do {
                let limit = Int(request.string("limit") ?? "") ?? 8
                let results = try await youtube.search(query: query, limit: limit)
                return .ok([
                    "query": query,
                    "results": results.map(importPreviewPayload)
                ])
            } catch {
                return bridgeError(for: error, fallbackCode: "youtube_search_failed")
            }
        case ("GET", "/youtube/import-activity"):
            return .ok(youtubeImportPayload())
        case ("POST", "/youtube/import"):
            guard let urlString = request.string("url"), let url = URL(string: urlString) else {
                return .error("Provide a YouTube URL in the 'url' field.")
            }
            if let song = await importYouTube(url: url, title: request.string("title")) {
                return .ok(["message": "Imported YouTube audio", "song": songPayload(song)])
            }
            return .error(
                importStatus,
                code: lastImportFailureCode ?? "youtube_import_failed",
                details: youtubeFailureDetails()
            )
        case ("POST", "/song/open-original"):
            guard let id = request.string("id"), let song = library.song(id: id) else {
                return .error("Song not found.", status: 404, code: "song_not_found")
            }
            guard let url = song.sourceURL else {
                return .error("This song does not have an original YouTube URL.", code: "missing_source_url")
            }
            openYouTube(url: url)
            return .ok(["message": "Original video opened", "url": url.absoluteString])
        default:
            return .error("Unknown endpoint \(request.method) \(request.path).", status: 404, code: "not_found")
        }
    }

    private func playBridge(_ request: BridgeRequest) -> BridgeReply {
        if let id = request.string("id") {
            guard playback.playSongID(id) else {
                return .error("Song id '\(id)' was not found.", status: 404, code: "song_not_found")
            }
            return .ok(["message": "Playing song", "song": playback.currentSong.map(songPayload) ?? NSNull()])
        }
        if let query = request.string("q") ?? request.string("query") {
            guard let match = library.searchMatches(query, limit: 1).first else {
                return .error("No song matched '\(query)'.", status: 404, code: "song_not_found")
            }
            let song = match.song
            let base = library.visibleSongs().contains(song) ? library.visibleSongs() : library.songs
            playback.play(song: song, queue: base, source: "Bridge search snapshot", manual: true)
            return .ok(["message": "Playing \(song.title)", "song": songPayload(song), "match": searchMatchPayload(match)])
        }
        return .error("Provide either 'id' or 'query' to play a song.")
    }

    private func statusPayload() -> [String: Any] {
        [
            "app": AppConfiguration.appName,
            "libraryPath": library.libraryURL.displayPath,
            "songCount": library.songs.count,
            "groups": library.groups,
            "playing": playback.isPlaying,
            "volume": playback.volume,
            "nowPlaying": playback.currentSong.map(songPayload) ?? NSNull(),
            "playback": playbackStatePayload(),
            "queue": playback.queueStatePayload(),
            "smartPicker": [
                "count": library.smartSongs.count,
                "lastRefreshAt": (library.lastSmartPickerRefreshAt.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull()) as Any
            ],
            "librarySync": library.syncDiagnosticsPayload(),
            "youtubeTools": [
                "ytDlpFound": youtube.ytDLPURL != nil,
                "ffmpegFound": youtube.ffmpegURL != nil
            ],
            "youtubeImport": youtubeImportPayload(),
            "bridge": [
                "url": bridgeBaseURL,
                "tokenFile": AppConfiguration.tokenURL.displayPath
            ]
        ]
    }

    private func capabilitiesPayload() -> [String: Any] {
        [
            "app": AppConfiguration.appName,
            "purpose": "Local-only structured control surface for Jarvis and terminal helpers.",
            "bridge": [
                "baseURL": bridgeBaseURL,
                "host": AppConfiguration.bridgeHost,
                "port": AppConfiguration.bridgePort,
                "requiresToken": true,
                "tokenHeader": "Authorization: Bearer <token>",
                "tokenFile": AppConfiguration.tokenURL.displayPath
            ],
            "cli": [
                "helper": "./script/jarvis-music-control",
                "environment": [
                    "JARVIS_MUSIC_URL": "Override the bridge URL.",
                    "JARVIS_MUSIC_TOKEN_FILE": "Override the token file path."
                ]
            ],
            "actions": [
                capabilityAction("health", "GET", "/health", false, "Check that Music is open and the local bridge is reachable."),
                capabilityAction("capabilities", "GET", "/capabilities", true, "Describe every supported bridge action for Jarvis."),
                capabilityAction("status", "GET", "/status", true, "Return library, queue, Smart Picker, YouTube-tool, volume, and bridge status."),
                capabilityAction("songs", "GET", "/songs", true, "List all songs, or ranked matches when q is provided.", [
                    parameter("q", required: false, description: "Optional title, artist, album, group, or filename query.")
                ]),
                capabilityAction("search", "GET", "/search", true, "Return ranked song candidates with matched fields.", [
                    parameter("q", required: true, description: "Natural song search query.")
                ]),
                capabilityAction("groups", "GET", "/groups", true, "List library groups and playlists, including Your Pick."),
                capabilityAction("playlist-songs", "GET", "/playlist/songs", true, "List songs in All Songs, Your Pick, or a custom playlist.", [
                    parameter("name", required: false, description: "Playlist name. Also accepts group or playlist."),
                    parameter("id", required: false, description: "Playlist id from /groups.")
                ]),
                capabilityAction("playlist-select", "POST", "/playlist/select", true, "Select a playlist in the visible app without starting playback.", [
                    parameter("name", required: false, description: "Playlist name. Also accepts group or playlist."),
                    parameter("id", required: false, description: "Playlist id from /groups.")
                ]),
                capabilityAction("playlist-play", "POST", "/playlist/play", true, "Play a snapshot of All Songs, Your Pick, or a custom playlist.", [
                    parameter("name", required: false, description: "Playlist name. Also accepts group or playlist."),
                    parameter("id", required: false, description: "Playlist id from /groups.")
                ]),
                capabilityAction("playlist-create", "POST", "/playlist/create", true, "Create an empty custom playlist.", [
                    parameter("name", required: true, description: "New custom playlist name.")
                ]),
                capabilityAction("playlist-rename", "POST", "/playlist/rename", true, "Rename a custom playlist.", [
                    parameter("oldName", required: false, description: "Existing playlist name. Also accepts from, old, group, playlist, or id."),
                    parameter("newName", required: true, description: "New playlist name. Also accepts to or name.")
                ]),
                capabilityAction("playlist-delete", "POST", "/playlist/delete", true, "Delete an empty or custom playlist and return its songs to All Songs.", [
                    parameter("name", required: false, description: "Playlist name. Also accepts group, playlist, or id.")
                ]),
                capabilityAction("song-move-to-playlist", "POST", "/song/move", true, "Move a song to All Songs or a custom playlist.", [
                    parameter("id", required: true, description: "Song id."),
                    parameter("group", required: true, description: "Destination playlist. Also accepts playlist or name.")
                ]),
                capabilityAction("now-playing", "GET", "/now-playing", true, "Return the current song and playback state."),
                capabilityAction("playback-state", "GET", "/playback-state", true, "Return current time, duration, shuffle, repeat, and queue snapshot state."),
                capabilityAction("volume-get", "GET", "/volume", true, "Return app playback volume."),
                capabilityAction("volume-set", "POST", "/volume", true, "Set app playback volume from 0.0 to 1.0.", [
                    parameter("level", required: true, description: "Volume as a decimal from 0.0 to 1.0. Also accepts value or volume.")
                ]),
                capabilityAction("seek", "POST", "/seek", true, "Seek the current track to a position in seconds.", [
                    parameter("seconds", required: true, description: "Target time in seconds. Also accepts time or position.")
                ]),
                capabilityAction("shuffle-set", "POST", "/shuffle", true, "Turn shuffle on or off.", [
                    parameter("enabled", required: true, description: "true or false. Also accepts value or shuffle.")
                ]),
                capabilityAction("repeat-set", "POST", "/repeat", true, "Set repeat mode: off, all, one, 0, 1, or 2.", [
                    parameter("mode", required: true, description: "off/all/one or 0/1/2. Also accepts value or repeat.")
                ]),
                capabilityAction("play", "POST", "/play", true, "Play by song id or by natural query using a queue snapshot.", [
                    parameter("id", required: false, description: "Exact song id."),
                    parameter("query", required: false, description: "Natural song query. Also accepts q.")
                ]),
                capabilityAction("play-by-id", "POST", "/play-by-id", true, "Play a specific song id.", [
                    parameter("id", required: true, description: "Exact song id.")
                ]),
                capabilityAction("play-by-query", "POST", "/play-by-query", true, "Play the top ranked song for a natural query.", [
                    parameter("query", required: true, description: "Natural song query. Also accepts q.")
                ]),
                capabilityAction("pause", "POST", "/pause", true, "Pause playback."),
                capabilityAction("resume", "POST", "/resume", true, "Resume playback."),
                capabilityAction("stop", "POST", "/stop", true, "Stop playback and clear active play state."),
                capabilityAction("next", "POST", "/next", true, "Skip to the next song in the current queue snapshot."),
                capabilityAction("previous", "POST", "/previous", true, "Return to the previous song in the current queue snapshot."),
                capabilityAction("refresh-library", "POST", "/refresh-library", true, "Rescan the shared MP3 library folder without duplicating files."),
                capabilityAction("library-sync", "GET", "/diagnostics/library-sync", true, "Return auto-sync state for the shared MP3 library folder."),
                capabilityAction("source-metadata-diagnostics", "GET", "/diagnostics/source-metadata", true, "Re-read a song file without database state and report source URL metadata recovery.", [
                    parameter("id", required: true, description: "Song id to inspect.")
                ]),
                capabilityAction("process-timeout-diagnostics", "POST", "/diagnostics/process-timeout", true, "Simulate a slow helper timeout in temporary storage and verify the shared MP3 library is unchanged."),
                capabilityAction("youtube-helper-error-diagnostics", "POST", "/diagnostics/youtube-helper-error", true, "Classify a captured yt-dlp/ffmpeg failure into Jarvis-safe YouTube error codes.", [
                    parameter("message", required: true, description: "Helper stderr/stdout text to classify."),
                    parameter("timedOut", required: false, description: "true when the helper was stopped by the timeout guard.")
                ]),
                capabilityAction("refresh-smart-picker", "POST", "/refresh-smart-picker", true, "Recompute Your Pick rankings from listening behavior without live reordering."),
                capabilityAction("youtube-open", "POST", "/youtube/open", true, "Open the in-app YouTube browser to a URL or search.", [
                    parameter("url", required: false, description: "Specific YouTube URL."),
                    parameter("search", required: false, description: "YouTube search terms.")
                ]),
                capabilityAction("youtube-search", "GET", "/youtube/search", true, "Return import candidates from YouTube search.", [
                    parameter("q", required: true, description: "Search terms. Also accepts query."),
                    parameter("limit", required: false, description: "Maximum result count.")
                ]),
                capabilityAction("youtube-import-activity", "GET", "/youtube/import-activity", true, "Return current YouTube import status, percent progress, and recent stages/outcomes."),
                capabilityAction("youtube-import", "POST", "/youtube/import", true, "Import audio from a specific YouTube video Leo is allowed to save.", [
                    parameter("url", required: true, description: "Specific YouTube watch/video URL."),
                    parameter("title", required: false, description: "Optional title override before saving.")
                ]),
                capabilityAction("open-original", "POST", "/song/open-original", true, "Open an imported song's original YouTube URL in the in-app browser.", [
                    parameter("id", required: true, description: "Song id with sourceURL metadata.")
                ])
            ],
            "responseShape": [
                "success": ["ok": true],
                "error": [
                    "ok": false,
                    "error": ["code": "machine_readable_code", "message": "Friendly human-readable message"]
                ]
            ],
            "notes": [
                "The app must be open before Jarvis calls protected endpoints.",
                "All protected endpoints accept the local token as a bearer header or token query/body field.",
                "Value-carrying POST endpoints accept JSON bodies or query parameters.",
                "Smart Picker playback uses queue snapshots; refresh-smart-picker recomputes rankings explicitly."
            ]
        ]
    }

    private func capabilityAction(_ id: String, _ method: String, _ path: String, _ auth: Bool, _ description: String, _ parameters: [[String: Any]] = []) -> [String: Any] {
        [
            "id": id,
            "method": method,
            "path": path,
            "auth": auth,
            "description": description,
            "parameters": parameters
        ]
    }

    private func parameter(_ name: String, required: Bool, description: String) -> [String: Any] {
        [
            "name": name,
            "required": required,
            "description": description
        ]
    }

    private func songPayload(_ song: Song) -> [String: Any] {
        [
            "id": song.id,
            "title": song.title,
            "artist": song.artist,
            "album": song.album,
            "duration": song.duration,
            "durationText": MusicFormatters.duration(song.duration),
            "group": song.group,
            "fileName": song.fileName,
            "relativePath": song.relativePath,
            "path": song.fileURLString,
            "sourceURL": song.sourceURLString ?? NSNull(),
            "stats": statsPayload(songID: song.id)
        ]
    }

    private func searchMatchPayload(_ match: SongSearchMatch) -> [String: Any] {
        [
            "score": match.score,
            "matchedFields": match.matchedFields,
            "song": songPayload(match.song)
        ]
    }

    private func playbackStatePayload() -> [String: Any] {
        [
            "nowPlaying": playback.currentSong.map(songPayload) ?? NSNull(),
            "playing": playback.isPlaying,
            "currentTime": playback.currentTime,
            "duration": playback.duration,
            "currentTimeText": MusicFormatters.duration(playback.currentTime),
            "durationText": MusicFormatters.duration(playback.duration),
            "volume": playback.volume,
            "shuffle": playback.shuffle,
            "repeatMode": playback.repeatMode,
            "repeatModeName": repeatModeName(playback.repeatMode),
            "queue": playback.queueStatePayload()
        ]
    }

    private func importPreviewPayload(_ preview: ImportPreview) -> [String: Any] {
        [
            "url": preview.url,
            "title": preview.title,
            "thumbnailURL": preview.thumbnailURL ?? NSNull(),
            "uploader": preview.uploader ?? NSNull(),
            "duration": preview.duration ?? NSNull(),
            "durationText": preview.duration.map(MusicFormatters.duration) ?? NSNull()
        ]
    }

    private func youtubeImportPayload() -> [String: Any] {
        [
            "isImporting": isImporting,
            "status": importStatus,
            "currentURL": youtubeCurrentURL,
            "titleDraft": importTitle,
            "lastFailureCode": lastImportFailureCode ?? NSNull(),
            "lastFailureRetryable": lastImportFailureRetryable ?? NSNull(),
            "lastRecoverySuggestion": lastImportRecoverySuggestion ?? NSNull(),
            "progress": youtubeImportProgressFraction,
            "progressPercent": Int((youtubeImportProgressFraction * 100).rounded()),
            "activity": importActivityLog.map(importActivityPayload)
        ]
    }

    private func importActivityPayload(_ entry: ImportActivityEntry) -> [String: Any] {
        [
            "id": entry.id.uuidString,
            "createdAt": ISO8601DateFormatter().string(from: entry.createdAt),
            "state": entry.state.rawValue,
            "stage": entry.stage?.rawValue ?? NSNull(),
            "title": entry.title,
            "detail": entry.detail
        ]
    }

    private func processTimeoutDiagnosticPayload() async throws -> [String: Any] {
        let startedAt = Date()
        let librarySongCountBefore = library.songs.count
        let libraryMP3CountBefore = mp3FileCount(in: library.libraryURL)
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MusicProcessTimeoutDiagnostic-\(UUID().uuidString)", isDirectory: true)
        let partialFile = tempDirectory.appendingPathComponent("partial-timeout.mp3")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let result = try await ProcessRunner.run(
            URL(fileURLWithPath: "/bin/sh"),
            arguments: [
                "-c",
                "printf 'partial diagnostic' > \"$1\"; exec sleep 10",
                "music-timeout-diagnostic",
                partialFile.path
            ],
            timeoutSeconds: 1
        )

        let partialExistedAfterTimeout = FileManager.default.fileExists(atPath: partialFile.path)
        try? FileManager.default.removeItem(at: tempDirectory)
        let tempDirectoryExistsAfterCleanup = FileManager.default.fileExists(atPath: tempDirectory.path)
        let partialExistsAfterCleanup = FileManager.default.fileExists(atPath: partialFile.path)
        let librarySongCountAfter = library.songs.count
        let libraryMP3CountAfter = mp3FileCount(in: library.libraryURL)
        let elapsed = Date().timeIntervalSince(startedAt)
        let sharedLibraryUnchanged = librarySongCountBefore == librarySongCountAfter && libraryMP3CountBefore == libraryMP3CountAfter
        let cleanupSucceeded = !tempDirectoryExistsAfterCleanup && !partialExistsAfterCleanup
        let processStopped = result.timedOut && result.status == -9 && elapsed < 5
        let passed = processStopped && partialExistedAfterTimeout && cleanupSucceeded && sharedLibraryUnchanged

        return [
            "passed": passed,
            "processStopped": processStopped,
            "timedOut": result.timedOut,
            "status": result.status,
            "timeoutSeconds": result.timeoutSeconds ?? NSNull(),
            "elapsedSeconds": elapsed,
            "partialExistedAfterTimeout": partialExistedAfterTimeout,
            "partialExistsAfterCleanup": partialExistsAfterCleanup,
            "tempDirectoryExistsAfterCleanup": tempDirectoryExistsAfterCleanup,
            "cleanupSucceeded": cleanupSucceeded,
            "sharedLibraryUnchanged": sharedLibraryUnchanged,
            "librarySongCountBefore": librarySongCountBefore,
            "librarySongCountAfter": librarySongCountAfter,
            "libraryMP3CountBefore": libraryMP3CountBefore,
            "libraryMP3CountAfter": libraryMP3CountAfter,
            "usedSharedLibrary": false,
            "stderr": result.stderr
        ]
    }

    private func youtubeHelperErrorDiagnosticPayload(_ request: BridgeRequest) -> [String: Any] {
        let message = request.string("message") ?? request.string("stderr") ?? request.string("detail") ?? ""
        let timedOut = request.string("timedOut")
            .flatMap(boolValue)
            ?? request.string("timeout").flatMap(boolValue)
            ?? false
        let error = YouTubeImportError.classifyHelperFailure(message: message, timedOut: timedOut)
        return [
            "code": error.bridgeCode,
            "message": friendly(error),
            "retryable": error.retryable,
            "recoverySuggestion": error.recoverySuggestion ?? NSNull(),
            "input": [
                "timedOut": timedOut,
                "message": MusicFormatters.clean(message, maxLength: 160)
            ]
        ]
    }

    private func mp3FileCount(in directory: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var count = 0
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "mp3" {
            count += 1
        }
        return count
    }

    private func groupPayloads() -> [[String: Any]] {
        let allSongs: [[String: Any]] = [
            [
                "id": "all-songs",
                "name": "All Songs",
                "type": "library",
                "songCount": library.songs.count,
                "smart": false
            ],
            [
                "id": "smart-picker",
                "name": "Your Pick",
                "type": "smart",
                "songCount": library.smartSongs.count,
                "smart": true,
                "lastRefreshAt": (library.lastSmartPickerRefreshAt.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull()) as Any
            ]
        ]

        let playlists = library.groups.map { group in
            [
                "id": StableID.shortHash(group, prefix: "group-"),
                "name": group,
                "type": "playlist",
                "songCount": library.songs.filter { $0.group == group }.count,
                "smart": false
            ] as [String: Any]
        }

        return allSongs + playlists
    }

    private struct PlaylistTarget {
        var id: String
        var name: String
        var type: String
        var smart: Bool
        var selection: LibrarySelection
        var songs: [Song]
    }

    private func playlistTarget(from request: BridgeRequest, oldNameKeys: Bool = false) -> PlaylistTarget? {
        let id = request.string("id")
        let name: String?
        if oldNameKeys {
            name = request.string("oldName")
                ?? request.string("from")
                ?? request.string("old")
                ?? request.string("group")
                ?? request.string("playlist")
        } else {
            name = request.string("name")
                ?? request.string("group")
                ?? request.string("playlist")
        }
        return playlistTarget(id: id, name: name)
    }

    private func playlistTarget(id: String? = nil, name: String? = nil) -> PlaylistTarget? {
        let cleanID = id.map { MusicFormatters.clean($0).lowercased() }
        let cleanName = name.map { MusicFormatters.clean($0).lowercased() }
        let allAliases = Set(["all", "all songs", "all-songs", "library"])
        if cleanID == "all-songs" || cleanName.map(allAliases.contains) == true {
            let songs = library.songs.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            return PlaylistTarget(id: "all-songs", name: "All Songs", type: "library", smart: false, selection: .allSongs, songs: songs)
        }

        let smartAliases = Set(["smart", "smart picker", "smart-picker", "your pick", "your-pick"])
        if cleanID == "smart-picker" || cleanName.map(smartAliases.contains) == true {
            return PlaylistTarget(id: "smart-picker", name: "Your Pick", type: "smart", smart: true, selection: .smartPicker, songs: library.smartSongs)
        }

        for group in library.groups {
            let groupID = StableID.shortHash(group, prefix: "group-")
            if cleanID == groupID.lowercased() || cleanName == group.lowercased() {
                let songs = library.songs
                    .filter { $0.group == group }
                    .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
                return PlaylistTarget(id: groupID, name: group, type: "playlist", smart: false, selection: .group(group), songs: songs)
            }
        }
        return nil
    }

    private func playlistPayload(_ target: PlaylistTarget) -> [String: Any] {
        [
            "id": target.id,
            "name": target.name,
            "type": target.type,
            "songCount": target.songs.count,
            "smart": target.smart
        ]
    }

    private func statsPayload(songID: String) -> [String: Any] {
        let stats = library.stats[songID] ?? ListeningStats(songID: songID)
        return [
            "plays": stats.plays,
            "skips": stats.skips,
            "completions": stats.completions,
            "repeats": stats.repeats,
            "manualSelections": stats.manualSelections,
            "completionRatio": stats.lastCompletionRatio,
            "lastPlayedAt": stats.lastPlayedAt.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull()
        ]
    }

    private func boolValue(_ value: String) -> Bool? {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on", "enabled":
            return true
        case "0", "false", "no", "off", "disabled":
            return false
        default:
            return nil
        }
    }

    private func repeatModeValue(_ value: String) -> Int? {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "0", "off", "none":
            return 0
        case "1", "all", "repeat", "on":
            return 1
        case "2", "one", "single":
            return 2
        default:
            return nil
        }
    }

    private func repeatModeName(_ mode: Int) -> String {
        switch mode {
        case 1:
            return "all"
        case 2:
            return "one"
        default:
            return "off"
        }
    }

    private func authorized(_ request: BridgeRequest) -> Bool {
        request.bearerToken == bridgeToken || request.string("token") == bridgeToken
    }

    private func loadOrCreateToken() -> String {
        try? FileManager.default.createDirectory(at: AppConfiguration.applicationSupportURL, withIntermediateDirectories: true)
        if let existing = try? String(contentsOf: AppConfiguration.tokenURL).trimmingCharacters(in: .whitespacesAndNewlines), !existing.isEmpty {
            return existing
        }
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "") + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        try? token.write(to: AppConfiguration.tokenURL, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: AppConfiguration.tokenURL.path)
        return token
    }

    private func friendly(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return error.localizedDescription
    }

    private func recoverySuggestion(for error: Error) -> String? {
        if let youtubeError = error as? YouTubeImportError {
            return youtubeError.recoverySuggestion
        }
        if let localized = error as? LocalizedError {
            return localized.recoverySuggestion
        }
        return nil
    }

    private func retryable(for error: Error) -> Bool {
        if let youtubeError = error as? YouTubeImportError {
            return youtubeError.retryable
        }
        return false
    }

    private func failureDetail(for error: Error) -> String {
        let message = friendly(error)
        guard let recoverySuggestion = recoverySuggestion(for: error), !recoverySuggestion.isEmpty else {
            return message
        }
        return "\(message) \(recoverySuggestion)"
    }

    private func bridgeError(for error: Error, fallbackCode: String, status: Int = 400) -> BridgeReply {
        BridgeReply.error(
            friendly(error),
            status: status,
            code: bridgeErrorCode(for: error, fallback: fallbackCode),
            details: bridgeErrorDetails(for: error)
        )
    }

    private func bridgeErrorDetails(for error: Error) -> [String: Any] {
        var details: [String: Any] = [
            "retryable": retryable(for: error)
        ]
        if let recoverySuggestion = recoverySuggestion(for: error), !recoverySuggestion.isEmpty {
            details["recoverySuggestion"] = recoverySuggestion
        }
        return details
    }

    private func youtubeFailureDetails() -> [String: Any] {
        var details: [String: Any] = [:]
        if let lastImportFailureRetryable {
            details["retryable"] = lastImportFailureRetryable
        }
        if let lastImportRecoverySuggestion {
            details["recoverySuggestion"] = lastImportRecoverySuggestion
        }
        return details
    }

    private func bridgeErrorCode(for error: Error, fallback: String) -> String {
        if let youtubeError = error as? YouTubeImportError {
            return youtubeError.bridgeCode
        }
        return fallback
    }
}
