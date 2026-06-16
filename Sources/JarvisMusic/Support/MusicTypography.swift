import SwiftUI

enum MusicTypography {
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .default)
    }

    static func fixed(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static let sidebarTitle = Font.system(.title2, design: .default).weight(.semibold)
    static let sidebarItem = Font.system(.callout, design: .default).weight(.medium)
    static let sectionLabel = Font.system(.caption, design: .default).weight(.semibold)
    static let songTitle = Font.system(.headline, design: .default)
    static let songSubtitle = Font.system(.subheadline, design: .default)
    static let playerTitle = Font.system(.callout, design: .default).weight(.semibold)
    static let playerSubtitle = Font.system(.caption, design: .default)
}
