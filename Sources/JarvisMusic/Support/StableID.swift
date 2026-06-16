import CryptoKit
import Foundation

enum StableID {
    static func songID(for url: URL) -> String {
        let normalized = url.standardizedFileURL.path.lowercased()
        let digest = SHA256.hash(data: Data(normalized.utf8))
        let hex = digest.compactMap { String(format: "%02x", $0) }.joined()
        return "song-" + String(hex.prefix(24))
    }

    static func shortHash(_ value: String, prefix: String = "") -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        let hex = digest.compactMap { String(format: "%02x", $0) }.joined()
        return prefix + String(hex.prefix(16))
    }
}
