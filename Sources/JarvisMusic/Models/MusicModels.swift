import Foundation

enum LibrarySelection: Hashable, Codable {
    case allSongs
    case smartPicker
    case recycleBin
    case group(String)
    case youtube

    var title: String {
        switch self {
        case .allSongs:
            return "All Songs"
        case .smartPicker:
            return "Your Pick"
        case .recycleBin:
            return "Recycle Bin"
        case .group(let name):
            return name
        case .youtube:
            return "YouTube Import"
        }
    }
}

struct Song: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var fileURLString: String
    var relativePath: String
    var fileName: String
    var group: String
    var artworkFileName: String?
    var sourceURLString: String?
    var createdAt: Date
    var updatedAt: Date
    var fileModifiedAt: Date
    var customTitle: String?

    var fileURL: URL {
        URL(fileURLWithPath: fileURLString)
    }

    var sourceURL: URL? {
        guard let sourceURLString else { return nil }
        return URL(string: sourceURLString)
    }
}

struct ListeningStats: Codable, Hashable {
    var songID: String
    var plays: Int = 0
    var skips: Int = 0
    var completions: Int = 0
    var repeats: Int = 0
    var manualSelections: Int = 0
    var totalListenedSeconds: TimeInterval = 0
    var lastCompletionRatio: Double = 0
    var lastPlayedAt: Date?
    var lastSkippedAt: Date?
    var lastCompletedAt: Date?
    var lastManualSelectionAt: Date?
    var rankScore: Double = 0
    var smartPickerRankOverride: Double?
}

struct ListeningEvent: Codable, Hashable {
    var songID: String
    var listenedSeconds: TimeInterval
    var durationSeconds: TimeInterval
    var completionRatio: Double
    var endedReason: String
    var repeatInRowCount: Int
    var manualSelection: Bool
    var skipped: Bool
    var earlySkip: Bool
    var createdAt: Date
}

struct QueueSnapshot: Codable, Hashable {
    var source: String
    var songIDs: [String]
    var createdAt: Date
}

struct LibraryDatabase: Codable {
    var version: Int = 1
    var songs: [Song] = []
    var stats: [String: ListeningStats] = [:]
    var events: [ListeningEvent] = []
    var smartRankingSongIDs: [String] = []
    var explicitGroups: [String] = []
    var trashedSongs: [Song]?
    var lastSmartPickerRefreshAt: Date?
}

struct ImportPreview: Codable, Hashable {
    var url: String
    var title: String
    var thumbnailURL: String?
    var uploader: String?
    var duration: TimeInterval?
}

enum ImportActivityState: String, Codable, Hashable {
    case active
    case success
    case failure
    case info

    var symbolName: String {
        switch self {
        case .active:
            return "arrow.triangle.2.circlepath"
        case .success:
            return "checkmark.circle.fill"
        case .failure:
            return "exclamationmark.triangle.fill"
        case .info:
            return "info.circle"
        }
    }
}

enum YouTubeImportStage: String, Codable, Hashable {
    case metadata
    case download
    case tagging
    case saving
    case refreshing
    case finished
    case failed

    var title: String {
        switch self {
        case .metadata:
            return "Reading YouTube metadata"
        case .download:
            return "Downloading audio"
        case .tagging:
            return "Tagging MP3"
        case .saving:
            return "Saving to library"
        case .refreshing:
            return "Refreshing library"
        case .finished:
            return "Import complete"
        case .failed:
            return "Import failed"
        }
    }

    var progressFraction: Double {
        switch self {
        case .metadata:
            return 0.12
        case .download:
            return 0.58
        case .tagging:
            return 0.78
        case .saving:
            return 0.88
        case .refreshing:
            return 0.94
        case .finished:
            return 1
        case .failed:
            return 0
        }
    }
}

struct ImportActivityEntry: Identifiable, Hashable {
    var id = UUID()
    var createdAt = Date()
    var state: ImportActivityState
    var stage: YouTubeImportStage?
    var title: String
    var detail: String
}

struct SongSearchMatch: Hashable {
    var song: Song
    var score: Double
    var matchedFields: [String]
}
