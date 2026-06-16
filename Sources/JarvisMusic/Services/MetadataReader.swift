import AVFoundation
import Foundation

enum MetadataReader {
    static func readSong(at url: URL, existing: Song?) async -> Song {
        let fileManager = FileManager.default
        let attributes = (try? fileManager.attributesOfItem(atPath: url.path)) ?? [:]
        let modified = attributes[.modificationDate] as? Date ?? Date()
        let asset = AVURLAsset(url: url)

        let durationTime = (try? await asset.load(.duration)) ?? .zero
        let duration = max(0, CMTimeGetSeconds(durationTime))
        let metadata = (try? await asset.load(.commonMetadata)) ?? []
        let formatMetadata = await metadataItems(in: asset)
        let allMetadata = metadata + formatMetadata

        let extractedTitle = await firstString(in: allMetadata, key: .commonKeyTitle)
        let extractedArtist = await firstString(in: allMetadata, key: .commonKeyArtist)
        let extractedAlbum = await firstString(in: allMetadata, key: .commonKeyAlbumName)
        let artworkData = await firstData(in: allMetadata, key: .commonKeyArtwork)
        let extractedSourceURLString = await originalSourceURLString(in: allMetadata)
        let sourceURLString = existing?.sourceURLString ?? extractedSourceURLString

        let fallbackTitle = url.deletingPathExtension().lastPathComponent
        let id = existing?.id ?? StableID.songID(for: url)
        let title = existing?.customTitle?.isEmpty == false ? existing!.customTitle! : (extractedTitle?.isEmpty == false ? extractedTitle! : fallbackTitle)
        let artist = extractedArtist?.isEmpty == false ? extractedArtist! : "Unknown Artist"
        let album = extractedAlbum?.isEmpty == false ? extractedAlbum! : "Local Library"
        let artworkFileName = writeArtworkIfNeeded(data: artworkData, songID: id) ?? existing?.artworkFileName

        return Song(
            id: id,
            title: title,
            artist: artist,
            album: album,
            duration: duration.isFinite ? duration : 0,
            fileURLString: url.path,
            relativePath: relativePath(for: url),
            fileName: url.lastPathComponent,
            group: existing?.group ?? "All Songs",
            artworkFileName: artworkFileName,
            sourceURLString: sourceURLString,
            createdAt: existing?.createdAt ?? Date(),
            updatedAt: Date(),
            fileModifiedAt: modified,
            customTitle: existing?.customTitle
        )
    }

    private static func metadataItems(in asset: AVURLAsset) async -> [AVMetadataItem] {
        let formats = (try? await asset.load(.availableMetadataFormats)) ?? []
        var items: [AVMetadataItem] = []
        for format in formats {
            if let formatItems = try? await asset.loadMetadata(for: format) {
                items.append(contentsOf: formatItems)
            }
        }
        return items
    }

    private static func firstString(in metadata: [AVMetadataItem], key: AVMetadataKey) async -> String? {
        guard let item = metadata.first(where: { $0.commonKey == key }) else { return nil }
        return try? await item.load(.stringValue)
    }

    private static func firstData(in metadata: [AVMetadataItem], key: AVMetadataKey) async -> Data? {
        guard let item = metadata.first(where: { $0.commonKey == key }) else { return nil }
        return try? await item.load(.dataValue)
    }

    private static func originalSourceURLString(in metadata: [AVMetadataItem]) async -> String? {
        var labeledValues: [(label: String, value: String)] = []
        var unlabeledValues: [String] = []
        for item in metadata {
            guard let value = try? await item.load(.stringValue), !value.isEmpty else { continue }
            let label = [
                item.commonKey?.rawValue,
                item.keySpace?.rawValue,
                (item.key as? String),
                item.identifier?.rawValue
            ]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()

            if label.contains("purl")
                || label.contains("comment")
                || label.contains("source")
                || label.contains("url")
                || value.localizedCaseInsensitiveContains("Original YouTube URL") {
                labeledValues.append((label, value))
            } else {
                unlabeledValues.append(value)
            }
        }

        for value in labeledValues.map(\.value) + unlabeledValues {
            if let url = youtubeURL(in: value) {
                return url
            }
        }
        return nil
    }

    private static func youtubeURL(in value: String) -> String? {
        let pattern = #"https?://(?:www\.)?(?:youtube\.com/watch\?v=|youtu\.be/|youtube\.com/shorts/|youtube\.com/live/)[^\s<>"']+"#
        guard let range = value.range(of: pattern, options: .regularExpression) else { return nil }
        let raw = String(value[range])
        return raw.trimmingCharacters(in: CharacterSet(charactersIn: ".,);]}\n\r\t "))
    }

    private static func writeArtworkIfNeeded(data: Data?, songID: String) -> String? {
        guard let data, !data.isEmpty else { return nil }
        try? FileManager.default.createDirectory(at: AppConfiguration.artworkDirectoryURL, withIntermediateDirectories: true)
        let fileName = "\(songID)-artwork.jpg"
        let target = AppConfiguration.artworkDirectoryURL.appendingPathComponent(fileName)
        if !FileManager.default.fileExists(atPath: target.path) {
            try? data.write(to: target, options: .atomic)
        }
        return fileName
    }

    private static func relativePath(for url: URL) -> String {
        let root = AppConfiguration.musicLibraryURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        if path.hasPrefix(root) {
            return String(path.dropFirst(root.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return url.lastPathComponent
    }
}
