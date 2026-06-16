import Foundation

enum MusicFormatters {
    static func duration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "--:--" }
        let total = Int(seconds.rounded())
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }

    static func relativeDate(_ date: Date?) -> String {
        guard let date else { return "Never" }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }

    static func clean(_ value: String, maxLength: Int = 180) -> String {
        String(value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxLength))
    }

    static func safeFileName(_ value: String, fallback: String = "Imported Song") -> String {
        let illegal = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let pieces = value.components(separatedBy: illegal).joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return pieces.isEmpty ? fallback : String(pieces.prefix(120))
    }
}

extension URL {
    var displayPath: String {
        path(percentEncoded: false)
    }
}
