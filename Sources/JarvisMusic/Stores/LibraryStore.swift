import Foundation
import SwiftUI

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var songs: [Song] = []
    @Published private(set) var stats: [String: ListeningStats] = [:]
    @Published private(set) var events: [ListeningEvent] = []
    @Published private(set) var smartRankingSongIDs: [String] = []
    @Published private(set) var explicitGroups: [String] = []
    @Published private(set) var lastSmartPickerRefreshAt: Date?
    @Published var selection: LibrarySelection? = .allSongs
    @Published var searchQuery = ""
    @Published var isScanning = false
    @Published var lastScanSummary = "Ready"
    @Published private(set) var isAutoRefreshActive = false
    @Published private(set) var lastScanAt: Date?
    @Published private(set) var lastAutoScanAt: Date?
    @Published private(set) var lastScanAddedCount = 0
    @Published private(set) var lastScanRemovedCount = 0
    @Published private(set) var lastScanChangedCount = 0

    private var database = LibraryDatabase()
    private var autoRefreshTask: Task<Void, Never>?
    private var lastLibraryFingerprint = ""
    private let autoRefreshIntervalSeconds: UInt64 = 10

    var libraryURL: URL {
        AppConfiguration.musicLibraryURL
    }

    var groups: [String] {
        let songGroups = songs.map(\.group).filter { $0 != "All Songs" && !$0.isEmpty }
        return Array(Set(explicitGroups + songGroups)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var smartSongs: [Song] {
        let byID = Dictionary(uniqueKeysWithValues: songs.map { ($0.id, $0) })
        let ranked = smartRankingSongIDs.compactMap { byID[$0] }
        let used = Set(ranked.map(\.id))
        return Array((ranked + songs.filter { !used.contains($0.id) }).prefix(min(20, songs.count)))
    }

    func load() async {
        ensureStorage()
        loadDatabase()
        await scanLibrary()
        if smartRankingSongIDs.isEmpty {
            refreshSmartPicker()
        }
        startAutoRefresh()
    }

    func startAutoRefresh() {
        autoRefreshTask?.cancel()
        isAutoRefreshActive = true
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                await self?.scanLibrary(silent: true, automatic: true)
            }
        }
    }

    func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
        isAutoRefreshActive = false
    }

    func visibleSongs() -> [Song] {
        let base: [Song]
        switch selection ?? .allSongs {
        case .allSongs:
            base = songs.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .smartPicker:
            base = smartSongs
        case .group(let group):
            base = songs.filter { $0.group == group }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .youtube:
            base = []
        }

        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return base }
        return base.filter { song in
            song.title.localizedCaseInsensitiveContains(query)
                || song.artist.localizedCaseInsensitiveContains(query)
                || song.album.localizedCaseInsensitiveContains(query)
                || song.fileName.localizedCaseInsensitiveContains(query)
        }
    }

    func song(id: String) -> Song? {
        songs.first { $0.id == id }
    }

    func searchSongs(_ query: String, limit: Int = 12) -> [Song] {
        searchMatches(query, limit: limit).map(\.song)
    }

    func searchMatches(_ query: String, limit: Int = 12) -> [SongSearchMatch] {
        let trimmed = MusicFormatters.clean(query)
        guard !trimmed.isEmpty else {
            return Array(songs.prefix(limit)).map {
                SongSearchMatch(song: $0, score: 0, matchedFields: [])
            }
        }

        let queryText = normalizedSearchText(trimmed)
        let tokens = searchTokens(trimmed)
        let effectiveTokens = tokens.isEmpty ? [queryText].filter { !$0.isEmpty } : tokens

        return songs.compactMap { song -> SongSearchMatch? in
            let title = normalizedSearchText(song.title)
            let artist = normalizedSearchText(song.artist)
            let album = normalizedSearchText(song.album)
            let file = normalizedSearchText(song.fileName)
            let group = normalizedSearchText(song.group)
            let fields = [
                ("title", title, 72.0),
                ("artist", artist, 38.0),
                ("album", album, 20.0),
                ("file", file, 18.0),
                ("group", group, 8.0)
            ]

            var score = 0.0
            var matchedFields: Set<String> = []

            for (name, value, weight) in fields {
                guard !value.isEmpty else { continue }
                if value == queryText {
                    score += weight * 2.2
                    matchedFields.insert(name)
                } else if value.hasPrefix(queryText) {
                    score += weight * 1.45
                    matchedFields.insert(name)
                } else if value.contains(queryText) {
                    score += weight
                    matchedFields.insert(name)
                }

                for token in effectiveTokens where value.contains(token) {
                    score += weight / 3.4
                    matchedFields.insert(name)
                    if value.hasPrefix(token) {
                        score += weight / 8
                    }
                }
            }

            let allWords = [title, artist, album, file].joined(separator: " ")
            if effectiveTokens.allSatisfy({ allWords.contains($0) }) {
                score += 34
            }

            guard score > 0 else { return nil }
            return SongSearchMatch(song: song, score: score, matchedFields: Array(matchedFields).sorted())
        }
        .sorted { left, right in
            if abs(left.score - right.score) > 0.001 {
                return left.score > right.score
            }
            return left.song.title.localizedCaseInsensitiveCompare(right.song.title) == .orderedAscending
        }
        .prefix(limit)
        .map { $0 }
    }

    func scanLibrary(silent: Bool = false, automatic: Bool = false) async {
        if isScanning { return }
        isScanning = true
        if !silent { lastScanSummary = "Scanning \(libraryURL.displayPath)" }
        defer { isScanning = false }

        let fileURLs = discoverAudioFiles()
        let nextFingerprint = fingerprint(for: fileURLs)
        if silent, nextFingerprint == lastLibraryFingerprint {
            let now = Date()
            lastScanAt = now
            if automatic { lastAutoScanAt = now }
            lastScanAddedCount = 0
            lastScanRemovedCount = 0
            lastScanChangedCount = 0
            lastScanSummary = "\(songs.count) songs synced"
            return
        }

        let oldSongsByID = Dictionary(uniqueKeysWithValues: songs.map { ($0.id, $0) })
        let oldSongIDs = Set(oldSongsByID.keys)
        let existingByID = Dictionary(uniqueKeysWithValues: database.songs.map { ($0.id, $0) })
        let existingByPath = Dictionary(uniqueKeysWithValues: database.songs.map { ($0.fileURLString, $0) })
        var scannedSongs: [Song] = []

        for url in fileURLs {
            let id = StableID.songID(for: url)
            let existing = existingByID[id] ?? existingByPath[url.path]
            let song = await MetadataReader.readSong(at: url, existing: existing)
            scannedSongs.append(song)
        }

        database.songs = scannedSongs.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        songs = database.songs
        let newSongIDs = Set(songs.map(\.id))
        lastScanAddedCount = newSongIDs.subtracting(oldSongIDs).count
        lastScanRemovedCount = oldSongIDs.subtracting(newSongIDs).count
        lastScanChangedCount = songs.reduce(0) { count, song in
            guard let oldSong = oldSongsByID[song.id] else { return count }
            return oldSong.fileModifiedAt != song.fileModifiedAt || oldSong.title != song.title || oldSong.artist != song.artist ? count + 1 : count
        }
        stats = database.stats
        events = database.events
        smartRankingSongIDs = database.smartRankingSongIDs.filter { id in songs.contains { $0.id == id } }
        explicitGroups = database.explicitGroups
        lastSmartPickerRefreshAt = database.lastSmartPickerRefreshAt
        pruneMissingData()
        saveDatabase()

        let count = songs.count
        let delta = scanDeltaSummary(added: lastScanAddedCount, removed: lastScanRemovedCount, changed: lastScanChangedCount)
        lastScanSummary = count == 1 ? "1 song synced\(delta)" : "\(count) songs synced\(delta)"
        let now = Date()
        lastScanAt = now
        if automatic { lastAutoScanAt = now }
        lastLibraryFingerprint = nextFingerprint
    }

    func syncDiagnosticsPayload() -> [String: Any] {
        [
            "libraryPath": libraryURL.displayPath,
            "autoRefreshActive": isAutoRefreshActive,
            "autoRefreshIntervalSeconds": autoRefreshIntervalSeconds,
            "isScanning": isScanning,
            "lastScanSummary": lastScanSummary,
            "lastScanAt": lastScanAt.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull(),
            "lastAutoScanAt": lastAutoScanAt.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull(),
            "songCount": songs.count,
            "lastScanDelta": [
                "added": lastScanAddedCount,
                "removed": lastScanRemovedCount,
                "changed": lastScanChangedCount
            ],
            "fingerprintKnown": !lastLibraryFingerprint.isEmpty
        ]
    }

    func refreshSmartPicker() {
        let ranked = rankSongs()
        database.smartRankingSongIDs = ranked.map(\.id)
        database.lastSmartPickerRefreshAt = Date()
        smartRankingSongIDs = database.smartRankingSongIDs
        lastSmartPickerRefreshAt = database.lastSmartPickerRefreshAt
        saveDatabase()
    }

    func record(_ event: ListeningEvent) {
        var next = database.stats[event.songID] ?? ListeningStats(songID: event.songID)
        next.plays += event.endedReason == "start" ? 0 : 1
        next.totalListenedSeconds += max(0, event.listenedSeconds)
        next.lastCompletionRatio = event.completionRatio
        next.lastPlayedAt = event.createdAt
        if event.skipped {
            next.skips += 1
            next.lastSkippedAt = event.createdAt
        }
        if event.completionRatio >= 0.8 {
            next.completions += 1
            next.lastCompletedAt = event.createdAt
        }
        if event.repeatInRowCount > 1 {
            next.repeats += 1
        }
        if event.manualSelection {
            next.manualSelections += 1
            next.lastManualSelectionAt = event.createdAt
        }
        next.rankScore = score(stats: next, recentEvents: database.events.filter { $0.songID == event.songID } + [event])

        database.stats[event.songID] = next
        database.events.append(event)
        database.events = Array(database.events.suffix(500))
        events = database.events
        stats = database.stats
        saveDatabase()
    }

    func updateSong(_ song: Song) {
        guard let index = database.songs.firstIndex(where: { $0.id == song.id }) else { return }
        database.songs[index] = song
        songs = database.songs
        saveDatabase()
    }

    func rename(song: Song, to title: String) {
        var next = song
        next.customTitle = title
        next.title = title
        next.updatedAt = Date()
        updateSong(next)
    }

    func addGroup(_ name: String) {
        let cleanName = MusicFormatters.clean(name, maxLength: 60)
        guard !cleanName.isEmpty, cleanName != "All Songs", cleanName != "Your Pick" else { return }
        if !database.explicitGroups.contains(cleanName) {
            database.explicitGroups.append(cleanName)
            database.explicitGroups.sort()
            explicitGroups = database.explicitGroups
            saveDatabase()
        }
    }

    func move(song: Song, to group: String) {
        let cleanGroup = MusicFormatters.clean(group, maxLength: 60)
        guard !cleanGroup.isEmpty, cleanGroup != "Your Pick" else { return }
        if cleanGroup != "All Songs" {
            addGroup(cleanGroup)
        }
        var next = song
        next.group = cleanGroup
        next.updatedAt = Date()
        updateSong(next)
    }

    func renameGroup(_ oldName: String, to newName: String) {
        let cleanName = MusicFormatters.clean(newName, maxLength: 60)
        guard !cleanName.isEmpty, cleanName != "All Songs", cleanName != "Your Pick" else { return }
        database.songs = database.songs.map { song in
            var next = song
            if next.group == oldName { next.group = cleanName }
            return next
        }
        database.explicitGroups = database.explicitGroups.map { $0 == oldName ? cleanName : $0 }
        if selection == .group(oldName) {
            selection = .group(cleanName)
        }
        songs = database.songs
        explicitGroups = Array(Set(database.explicitGroups)).sorted()
        database.explicitGroups = explicitGroups
        saveDatabase()
    }

    func deleteGroup(_ name: String) {
        database.songs = database.songs.map { song in
            var next = song
            if next.group == name { next.group = "All Songs" }
            return next
        }
        database.explicitGroups.removeAll { $0 == name }
        if selection == .group(name) {
            selection = .allSongs
        }
        songs = database.songs
        explicitGroups = database.explicitGroups
        saveDatabase()
    }

    func upsertImportedSong(from fileURL: URL, title: String?, sourceURL: URL?) async -> Song {
        let id = StableID.songID(for: fileURL)
        let existing = database.songs.first { $0.id == id }
        var song = await MetadataReader.readSong(at: fileURL, existing: existing)
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            song.title = title
            song.customTitle = title
        }
        song.sourceURLString = sourceURL?.absoluteString
        song.updatedAt = Date()

        if let index = database.songs.firstIndex(where: { $0.id == id }) {
            database.songs[index] = song
        } else {
            database.songs.append(song)
        }
        songs = database.songs.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        database.songs = songs
        saveDatabase()
        return song
    }

    private func ensureStorage() {
        try? FileManager.default.createDirectory(at: AppConfiguration.applicationSupportURL, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: AppConfiguration.artworkDirectoryURL, withIntermediateDirectories: true)
    }

    private func loadDatabase() {
        guard let data = try? Data(contentsOf: AppConfiguration.databaseURL) else {
            database = LibraryDatabase()
            applyDatabase()
            return
        }
        database = (try? JSONDecoder.music.decode(LibraryDatabase.self, from: data)) ?? LibraryDatabase()
        applyDatabase()
    }

    private func applyDatabase() {
        songs = database.songs
        stats = database.stats
        events = database.events
        smartRankingSongIDs = database.smartRankingSongIDs
        explicitGroups = database.explicitGroups
        lastSmartPickerRefreshAt = database.lastSmartPickerRefreshAt
    }

    private func saveDatabase() {
        ensureStorage()
        if let data = try? JSONEncoder.music.encode(database) {
            try? data.write(to: AppConfiguration.databaseURL, options: .atomic)
        }
    }

    private func discoverAudioFiles() -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: libraryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        let supported = Set(["mp3", "m4a", "aac", "wav"])
        return enumerator.compactMap { item -> URL? in
            guard let url = item as? URL else { return nil }
            return supported.contains(url.pathExtension.lowercased()) ? url : nil
        }
        .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func fingerprint(for urls: [URL]) -> String {
        urls.map { url in
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let modified = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
            let size = values?.fileSize ?? 0
            return "\(url.path)|\(Int(modified))|\(size)"
        }
        .joined(separator: "\n")
    }

    private func scanDeltaSummary(added: Int, removed: Int, changed: Int) -> String {
        let parts = [
            added == 0 ? nil : "+\(added)",
            removed == 0 ? nil : "-\(removed)",
            changed == 0 ? nil : "\(changed) changed"
        ].compactMap { $0 }
        return parts.isEmpty ? "" : " (\(parts.joined(separator: ", ")))"
    }

    private func pruneMissingData() {
        let ids = Set(database.songs.map(\.id))
        database.stats = database.stats.filter { ids.contains($0.key) }
        database.events = database.events.filter { ids.contains($0.songID) }
        database.smartRankingSongIDs = database.smartRankingSongIDs.filter { ids.contains($0) }
    }

    private func rankSongs() -> [Song] {
        let recentEventsBySong = Dictionary(grouping: database.events, by: \.songID)
        return songs.sorted { left, right in
            let leftStats = database.stats[left.id] ?? ListeningStats(songID: left.id)
            let rightStats = database.stats[right.id] ?? ListeningStats(songID: right.id)
            let leftScore = score(stats: leftStats, recentEvents: recentEventsBySong[left.id] ?? [])
            let rightScore = score(stats: rightStats, recentEvents: recentEventsBySong[right.id] ?? [])
            if abs(leftScore - rightScore) > 0.001 {
                return leftScore > rightScore
            }
            let leftDate = leftStats.lastPlayedAt ?? .distantPast
            let rightDate = rightStats.lastPlayedAt ?? .distantPast
            if leftDate != rightDate {
                return leftDate > rightDate
            }
            return left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
        }
    }

    private func score(stats: ListeningStats, recentEvents: [ListeningEvent]) -> Double {
        var score = 0.0
        score += Double(stats.completions) * 8
        score += min(12, stats.totalListenedSeconds / 60)
        score += Double(stats.manualSelections) * 2.5
        score += Double(stats.repeats) * 1.4
        score -= Double(stats.skips) * 4
        if let lastPlayed = stats.lastPlayedAt {
            score += max(0, 4 - Date().timeIntervalSince(lastPlayed) / 86_400)
        }
        for event in recentEvents.suffix(20) {
            let age = Date().timeIntervalSince(event.createdAt)
            let decay = pow(0.5, age / 86_400)
            var eventScore = event.completionRatio >= 0.8 ? 8 : max(0, event.listenedSeconds / 30)
            if event.manualSelection { eventScore += 2.5 }
            if event.earlySkip { eventScore -= 8 }
            else if event.skipped { eventScore -= 4 }
            score += eventScore * decay
        }
        return score
    }

    private func searchTokens(_ value: String) -> [String] {
        let stopWords: Set<String> = [
            "a", "an", "and", "by", "can", "could", "find", "for", "from", "me",
            "music", "play", "please", "search", "song", "songs", "the", "track", "with", "you"
        ]
        let words = normalizedSearchText(value)
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count > 1 && !stopWords.contains($0) }
        return Array(NSOrderedSet(array: words)) as? [String] ?? words
    }

    private func normalizedSearchText(_ value: String) -> String {
        let folded = value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
        let replaced = folded.replacingOccurrences(of: #"[^a-z0-9\p{Han}\p{Hiragana}\p{Katakana}]+"#, with: " ", options: .regularExpression)
        return MusicFormatters.clean(replaced).lowercased()
    }
}

extension JSONEncoder {
    static var music: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var music: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
