import Foundation

typealias YouTubeImportProgressHandler = @MainActor (YouTubeImportStage, String, Double?) -> Void

enum YouTubeImportError: LocalizedError {
    case invalidURL
    case notVideoURL
    case missingTool(String)
    case helperTimedOut(String)
    case videoUnavailable(String)
    case videoAccessRestricted(String)
    case protectedContent(String)
    case helperFailed(String)
    case noOutput

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "That does not look like a valid YouTube URL."
        case .notVideoURL:
            return "Open a specific YouTube video before importing audio."
        case .missingTool(let tool):
            return "\(tool) is not installed or is not on the standard Mac helper path. Install it before importing YouTube audio."
        case .helperTimedOut:
            return "The YouTube helper took too long and was stopped. Check the network or try again in a moment."
        case .videoUnavailable:
            return "YouTube says this video is unavailable or has been removed. Choose another video or open the original page."
        case .videoAccessRestricted:
            return "YouTube says this video is private, age-restricted, or requires sign-in. Music can only import content Leo can access and is allowed to save."
        case .protectedContent:
            return "This content appears protected or restricted. Music will not bypass DRM or access controls."
        case .helperFailed(let message):
            let cleanMessage = Self.cleanedHelperMessage(message)
            return cleanMessage.isEmpty ? "The YouTube import helper failed." : cleanMessage
        case .noOutput:
            return "The import helper finished without creating an MP3."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .invalidURL:
            return "Paste a normal YouTube URL."
        case .notVideoURL:
            return "Open a specific watch, shorts, live, embed, or youtu.be video URL before importing."
        case .missingTool(let tool):
            return "Install \(tool), then run the import again."
        case .helperTimedOut:
            return "Retry after the network settles; Music already stopped the stuck helper process."
        case .videoUnavailable:
            return "Use a different video, or open the original page to confirm it is still available."
        case .videoAccessRestricted:
            return "Choose a video that does not require private access, age verification, or helper sign-in."
        case .protectedContent:
            return "Choose content Leo is allowed to save; Music will not attempt to bypass protection."
        case .helperFailed:
            return "Try again once. If it repeats, run YouTube search/import diagnostics and check yt-dlp."
        case .noOutput:
            return "Retry the import; if it repeats, verify ffmpeg and yt-dlp are working."
        }
    }

    var retryable: Bool {
        switch self {
        case .helperTimedOut, .helperFailed, .noOutput:
            return true
        case .invalidURL, .notVideoURL, .missingTool, .videoUnavailable, .videoAccessRestricted, .protectedContent:
            return false
        }
    }

    var bridgeCode: String {
        switch self {
        case .invalidURL:
            return "invalid_youtube_url"
        case .notVideoURL:
            return "not_youtube_video_url"
        case .missingTool:
            return "youtube_helper_missing"
        case .helperTimedOut:
            return "youtube_helper_timeout"
        case .videoUnavailable:
            return "youtube_video_unavailable"
        case .videoAccessRestricted:
            return "youtube_access_restricted"
        case .protectedContent:
            return "youtube_protected_content"
        case .helperFailed:
            return "youtube_helper_failed"
        case .noOutput:
            return "youtube_import_no_output"
        }
    }

    static func classifyHelperFailure(message: String, timedOut: Bool) -> YouTubeImportError {
        if timedOut {
            return .helperTimedOut(message)
        }

        let cleanMessage = cleanedHelperMessage(message)
        let lower = cleanMessage.lowercased()

        if lower.containsAny([
            "private video",
            "this video is private",
            "members-only",
            "join this channel",
            "sign in to confirm your age",
            "age-restricted",
            "age restricted",
            "login required",
            "requires sign in",
            "requires login",
            "sign in to confirm"
        ]) {
            return .videoAccessRestricted(cleanMessage)
        }

        if lower.containsAny([
            "remote component challenge solver",
            "remote-components",
            "js challenges",
            "javascript challenge",
            "challenge solver script"
        ]) {
            return .helperFailed("YouTube asked for a JavaScript challenge solver. Music now enables yt-dlp's EJS helper automatically; retry the import.")
        }

        if lower.containsAny([
            "video unavailable",
            "this video is unavailable",
            "has been removed",
            "not available in your country",
            "not available",
            "unavailable videos are hidden",
            "this live stream recording is not available"
        ]) {
            return .videoUnavailable(cleanMessage)
        }

        if lower.containsAny([
            "drm",
            "protected content",
            "copyright",
            "premium",
            "paid content",
            "purchase this"
        ]) {
            return .protectedContent(cleanMessage)
        }

        return .helperFailed(cleanMessage)
    }

    private static func cleanedHelperMessage(_ message: String) -> String {
        var cleaned = message
            .replacingOccurrences(of: "ERROR:", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "WARNING:", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.contains("  ") {
            cleaned = cleaned.replacingOccurrences(of: "  ", with: " ")
        }
        return MusicFormatters.clean(cleaned, maxLength: 220)
    }
}

@MainActor
final class YouTubeImportService {
    static let audioOnlyFormatSelector = "bestaudio[acodec!=none]/bestaudio"
    private static let remoteComponentArguments = ["--remote-components", "ejs:github"]

    private enum HelperTimeout {
        static let metadata: TimeInterval = 35
        static let search: TimeInterval = 60
        static let download: TimeInterval = 300
        static let tag: TimeInterval = 60
    }

    private struct YTDLPInfo: Decodable {
        var id: String?
        var title: String?
        var url: String?
        var thumbnail: String?
        var thumbnails: [YTDLPThumbnail]?
        var channel: String?
        var uploader: String?
        var duration: Double?
        var webpage_url: String?
    }

    private struct YTDLPThumbnail: Decodable {
        var url: String?
        var width: Int?
        var height: Int?
        var preference: Int?
    }

    private struct YTDLPSearchResult: Decodable {
        var entries: [YTDLPInfo]?
    }

    var ytDLPURL: URL? { ToolLookup.find("yt-dlp") }
    var ffmpegURL: URL? { ToolLookup.find("ffmpeg") }

    static func isSupportedImportURL(_ value: String) -> Bool {
        guard let url = URL(string: value) else { return false }
        return isLikelyVideoURL(url)
    }

    static func inferredThumbnailURL(fromVideoURL value: String?) -> String? {
        guard let id = youtubeVideoID(from: value) else { return nil }
        return "https://i.ytimg.com/vi/\(id)/hqdefault.jpg"
    }

    func fetchMetadata(url: URL) async throws -> ImportPreview {
        guard Self.isYouTubeURL(url) else { throw YouTubeImportError.invalidURL }
        guard Self.isLikelyVideoURL(url) else { throw YouTubeImportError.notVideoURL }
        guard let ytDLPURL else { throw YouTubeImportError.missingTool("yt-dlp") }

        let result = try await ProcessRunner.run(
            ytDLPURL,
            arguments: [
                "--dump-single-json",
                "--skip-download",
                "--no-playlist",
                "--socket-timeout", "20",
            ] + Self.remoteComponentArguments + [
                url.absoluteString
            ],
            timeoutSeconds: HelperTimeout.metadata
        )
        guard result.succeeded else {
            throw helperError(result)
        }

        let data = Data(result.stdout.utf8)
        let info = try JSONDecoder().decode(YTDLPInfo.self, from: data)
        return ImportPreview(
            url: info.webpage_url ?? url.absoluteString,
            title: info.title ?? "Imported YouTube Audio",
            thumbnailURL: resolvedThumbnailURL(info),
            uploader: info.uploader,
            duration: info.duration
        )
    }

    func search(query: String, limit: Int = 8) async throws -> [ImportPreview] {
        let cleanQuery = MusicFormatters.clean(query, maxLength: 120)
        guard !cleanQuery.isEmpty else { return [] }
        guard let ytDLPURL else { throw YouTubeImportError.missingTool("yt-dlp") }

        let safeLimit = min(max(limit, 1), 12)
        let result = try await ProcessRunner.run(
            ytDLPURL,
            arguments: [
                "--dump-single-json",
                "--skip-download",
                "--flat-playlist",
                "--no-warnings",
                "--socket-timeout", "15",
            ] + Self.remoteComponentArguments + [
                "ytsearch\(safeLimit):\(cleanQuery)"
            ],
            timeoutSeconds: HelperTimeout.search
        )
        guard result.succeeded else {
            throw helperError(result)
        }

        let data = Data(result.stdout.utf8)
        let decoded = try JSONDecoder().decode(YTDLPSearchResult.self, from: data)
        return (decoded.entries ?? []).compactMap { info in
            let resolvedURL = resolvedVideoURL(info)
            guard let resolvedURL else { return nil }
            return ImportPreview(
                url: resolvedURL,
                title: info.title ?? "YouTube Video",
                thumbnailURL: resolvedThumbnailURL(info),
                uploader: info.uploader ?? info.channel,
                duration: info.duration
            )
        }
    }

    func audioOnlyPlan(url: URL) async throws -> [String: Any] {
        guard Self.isYouTubeURL(url) else { throw YouTubeImportError.invalidURL }
        guard Self.isLikelyVideoURL(url) else { throw YouTubeImportError.notVideoURL }
        guard let ytDLPURL else { throw YouTubeImportError.missingTool("yt-dlp") }

        let result = try await ProcessRunner.run(
            ytDLPURL,
            arguments: [
                "--simulate",
                "--no-playlist",
                "--no-warnings",
                "--socket-timeout", "20",
                "--format", Self.audioOnlyFormatSelector,
                "--print", "%(format_id)s\t%(vcodec)s\t%(acodec)s\t%(ext)s",
            ] + Self.remoteComponentArguments + [
                url.absoluteString
            ],
            timeoutSeconds: HelperTimeout.metadata
        )
        guard result.succeeded else {
            throw helperError(result)
        }

        guard let line = result.stdout
            .split(separator: "\n")
            .map(String.init)
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw YouTubeImportError.noOutput
        }

        let pieces = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        let formatID = pieces.indices.contains(0) ? pieces[0] : ""
        let videoCodec = pieces.indices.contains(1) ? pieces[1] : ""
        let audioCodec = pieces.indices.contains(2) ? pieces[2] : ""
        let fileExtension = pieces.indices.contains(3) ? pieces[3] : ""
        let audioOnly = videoCodec == "none" && audioCodec != "none" && !audioCodec.isEmpty

        return [
            "url": url.absoluteString,
            "formatSelector": Self.audioOnlyFormatSelector,
            "formatID": formatID,
            "videoCodec": videoCodec,
            "audioCodec": audioCodec,
            "extension": fileExtension,
            "audioOnly": audioOnly,
            "sharedLibraryUnchanged": true
        ]
    }

    func importAudio(url: URL, titleOverride: String?, progress: YouTubeImportProgressHandler? = nil) async throws -> URL {
        guard Self.isYouTubeURL(url) else { throw YouTubeImportError.invalidURL }
        guard Self.isLikelyVideoURL(url) else { throw YouTubeImportError.notVideoURL }
        guard let ytDLPURL else { throw YouTubeImportError.missingTool("yt-dlp") }
        guard let ffmpegURL else { throw YouTubeImportError.missingTool("ffmpeg") }

        progress?(.metadata, "Reading title, uploader, thumbnail, and source URL.", 0.08)
        let preview = try await fetchMetadata(url: url)
        let displayTitle = MusicFormatters.clean(titleOverride?.isEmpty == false ? titleOverride! : preview.title)
        let fileTitle = MusicFormatters.safeFileName(displayTitle)
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("JarvisMusicImport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let outputTemplate = tempDir.appendingPathComponent("audio.%(ext)s").path
        progress?(.download, "Extracting audio with yt-dlp and solving YouTube's JavaScript challenge if needed.", 0.12)
        let downloadProgress = YouTubeDownloadProgressReporter { fraction, detail in
            progress?(.download, detail, fraction)
        }
        let download = try await ProcessRunner.run(
            ytDLPURL,
            arguments: [
                "--no-playlist",
                "--newline",
                "--socket-timeout", "20",
                "--retries", "3",
                "--fragment-retries", "3",
                "--format", Self.audioOnlyFormatSelector,
                "--ffmpeg-location", ffmpegURL.path,
                "--extract-audio",
                "--audio-format", "mp3",
                "--audio-quality", "0",
                "--embed-thumbnail",
                "--convert-thumbnails", "jpg",
                "--add-metadata",
                "--ppa", "ffmpeg:-id3v2_version 3",
                "--output", outputTemplate,
            ] + Self.remoteComponentArguments + [
                url.absoluteString
            ],
            timeoutSeconds: HelperTimeout.download,
            outputHandler: { chunk in
                downloadProgress.consume(chunk)
            }
        )
        guard download.succeeded else {
            throw helperError(download)
        }

        let downloaded = try findDownloadedMP3(in: tempDir)
        let tagged = tempDir.appendingPathComponent("tagged.mp3")
        progress?(.tagging, "Writing title and original YouTube URL metadata.", 0.84)
        let tagResult = try await ProcessRunner.run(
            ffmpegURL,
            arguments: [
                "-y",
                "-i", downloaded.path,
                "-codec", "copy",
                "-metadata", "title=\(displayTitle)",
                "-metadata", "comment=Original YouTube URL: \(url.absoluteString)",
                "-id3v2_version", "3",
                tagged.path
            ],
            timeoutSeconds: HelperTimeout.tag
        )

        let source = tagResult.succeeded && FileManager.default.fileExists(atPath: tagged.path) ? tagged : downloaded
        let target = uniqueTargetURL(title: fileTitle)
        progress?(.saving, "Moving MP3 into the shared Music library.", 0.92)
        try FileManager.default.moveItem(at: source, to: target)
        return target
    }

    private static func isYouTubeURL(_ url: URL) -> Bool {
        guard let host = url.host()?.lowercased() else { return false }
        return host == "youtu.be" || host.hasSuffix("youtube.com") || host.hasSuffix("youtube-nocookie.com")
    }

    private static func isLikelyVideoURL(_ url: URL) -> Bool {
        guard isYouTubeURL(url), let host = url.host()?.lowercased() else { return false }
        let path = url.path(percentEncoded: false)
        if host == "youtu.be" {
            return path.split(separator: "/").first != nil
        }
        if path == "/watch" {
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            return components?.queryItems?.contains { $0.name == "v" && ($0.value?.isEmpty == false) } == true
        }
        return path.hasPrefix("/shorts/") || path.hasPrefix("/live/") || path.hasPrefix("/embed/")
    }

    private func findDownloadedMP3(in directory: URL) throws -> URL {
        let contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        guard let mp3 = contents.first(where: { $0.pathExtension.lowercased() == "mp3" }) else {
            throw YouTubeImportError.noOutput
        }
        return mp3
    }

    private func uniqueTargetURL(title: String) -> URL {
        let library = AppConfiguration.musicLibraryURL
        var candidate = library.appendingPathComponent("\(title).mp3")
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = library.appendingPathComponent("\(title) \(index).mp3")
            index += 1
        }
        return candidate
    }

    private func resolvedVideoURL(_ info: YTDLPInfo) -> String? {
        let candidates = [info.webpage_url, info.url]
        if let direct = candidates.compactMap({ $0 }).first(where: { $0.hasPrefix("http://") || $0.hasPrefix("https://") }) {
            return direct
        }
        if let id = info.id, !id.isEmpty {
            return "https://www.youtube.com/watch?v=\(id)"
        }
        if let url = info.url, !url.isEmpty {
            return "https://www.youtube.com/watch?v=\(url)"
        }
        return nil
    }

    private func resolvedThumbnailURL(_ info: YTDLPInfo) -> String? {
        if let thumbnail = info.thumbnail, thumbnail.hasHTTPPrefix {
            return thumbnail
        }

        if let best = info.thumbnails?
            .compactMap({ thumbnail -> (url: String, score: Int)? in
                guard let url = thumbnail.url, url.hasHTTPPrefix else { return nil }
                let area = max(thumbnail.width ?? 0, 0) * max(thumbnail.height ?? 0, 0)
                let preference = thumbnail.preference ?? 0
                return (url, preference * 1_000_000 + area)
            })
            .max(by: { $0.score < $1.score }) {
            return best.url
        }

        if let id = info.id, !id.isEmpty {
            return Self.inferredThumbnailURL(fromVideoURL: "https://www.youtube.com/watch?v=\(id)")
        }

        return Self.inferredThumbnailURL(fromVideoURL: resolvedVideoURL(info))
    }

    private static func youtubeVideoID(from value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard let url = URL(string: value) else {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.count == 11 ? trimmed : nil
        }

        let host = url.host()?.lowercased() ?? ""
        if host == "youtu.be" {
            return url.pathComponents.dropFirst().first
        }

        if host.contains("youtube.com") {
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let id = components.queryItems?.first(where: { $0.name == "v" })?.value,
               !id.isEmpty {
                return id
            }

            let parts = url.pathComponents
            if let index = parts.firstIndex(where: { ["shorts", "embed", "live"].contains($0) }),
               parts.indices.contains(parts.index(after: index)) {
                return parts[parts.index(after: index)]
            }
        }

        return nil
    }

    private func helperError(_ result: ProcessResult) -> YouTubeImportError {
        let message = [result.stderr, result.stdout]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " ")
        return YouTubeImportError.classifyHelperFailure(message: message, timedOut: result.timedOut)
    }
}

private final class YouTubeDownloadProgressReporter: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""
    private var lastWholePercent = -1
    private let handler: @MainActor (Double, String) -> Void

    init(handler: @escaping @MainActor (Double, String) -> Void) {
        self.handler = handler
    }

    func consume(_ chunk: String) {
        let normalized = chunk.replacingOccurrences(of: "\r", with: "\n")
        lock.lock()
        buffer += normalized
        let pieces = buffer.components(separatedBy: "\n")
        buffer = pieces.last ?? ""
        let lines = pieces.dropLast()
        lock.unlock()

        for line in lines {
            parse(line)
        }
    }

    private func parse(_ line: String) {
        guard line.contains("[download]"), let percent = Self.percent(from: line) else { return }
        let clampedPercent = min(max(percent, 0), 100)
        let wholePercent = Int(clampedPercent.rounded(.down))
        lock.lock()
        let shouldEmit = wholePercent != lastWholePercent || wholePercent == 100
        if shouldEmit {
            lastWholePercent = wholePercent
        }
        lock.unlock()
        guard shouldEmit else { return }

        let overallFraction = 0.12 + (clampedPercent / 100 * 0.66)
        let eta = Self.eta(from: line)
        let detail = eta.isEmpty
            ? "Downloading audio: \(wholePercent)%"
            : "Downloading audio: \(wholePercent)% - ETA \(eta)"
        let handler = handler
        Task { @MainActor in
            handler(overallFraction, detail)
        }
    }

    private static func percent(from line: String) -> Double? {
        guard let percentRange = line.range(of: "%") else { return nil }
        let prefix = line[..<percentRange.lowerBound]
        let token = prefix
            .split(separator: " ")
            .last?
            .replacingOccurrences(of: "~", with: "")
        guard let token else { return nil }
        return Double(token)
    }

    private static func eta(from line: String) -> String {
        guard let range = line.range(of: "ETA ") else { return "" }
        let tail = line[range.upperBound...]
        return tail.split(separator: " ").first.map(String.init) ?? ""
    }
}

private extension String {
    var hasHTTPPrefix: Bool {
        hasPrefix("http://") || hasPrefix("https://")
    }

    func containsAny(_ needles: [String]) -> Bool {
        needles.contains { contains($0) }
    }
}
