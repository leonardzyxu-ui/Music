import Foundation

enum AppConfiguration {
    static let appName = "Music"
    static let bundleIdentifier = "com.leoxu.Music"
    static let bridgeHost = "127.0.0.1"
    static let bridgePort: UInt16 = 47879

    static let projectRoot = URL(fileURLWithPath: "/Users/leoxu/Library/CloudStorage/OneDrive-YKPaoSchool上海民办包玉刚实验学校/developer/Music App", isDirectory: true)
    static let sharedLibraryReference = projectRoot.appendingPathComponent("SharedMP3Library", isDirectory: true)
    static let fallbackLibrary = URL(fileURLWithPath: "/Users/leoxu/Library/CloudStorage/OneDrive-YKPaoSchool上海民办包玉刚实验学校/developer/localOSroot/localOS/localFiles/mp3", isDirectory: true)

    static var musicLibraryURL: URL {
        if FileManager.default.fileExists(atPath: sharedLibraryReference.path) {
            return sharedLibraryReference.resolvingSymlinksInPath()
        }
        return fallbackLibrary
    }

    static var applicationSupportURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent(appName, isDirectory: true)
    }

    static var databaseURL: URL {
        applicationSupportURL.appendingPathComponent("library.json")
    }

    static var artworkDirectoryURL: URL {
        applicationSupportURL.appendingPathComponent("Artwork", isDirectory: true)
    }

    static var recycleBinURL: URL {
        applicationSupportURL.appendingPathComponent("Recycle Bin", isDirectory: true)
    }

    static var tokenURL: URL {
        applicationSupportURL.appendingPathComponent("control-token.txt")
    }

    static var windowControlDiagnosticsURL: URL {
        applicationSupportURL.appendingPathComponent("window-control-events.log")
    }
}
