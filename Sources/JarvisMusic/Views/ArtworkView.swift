import AppKit
import SwiftUI

struct ArtworkView: View {
    var song: Song?
    var size: CGFloat

    var body: some View {
        ZStack {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let logo = appLogo {
                RoundedRectangle(cornerRadius: max(8, size * 0.16), style: .continuous)
                    .fill(MusicPalette.rowBlack)
                Image(nsImage: logo)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.08)
            } else {
                RoundedRectangle(cornerRadius: max(8, size * 0.16), style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.90, green: 0.12, blue: 0.24),
                                Color(red: 0.96, green: 0.36, blue: 0.48),
                                Color(red: 0.45, green: 0.43, blue: 0.92)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Circle()
                    .strokeBorder(.white.opacity(0.28), lineWidth: max(1, size * 0.035))
                    .padding(size * 0.16)
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.34, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: max(8, size * 0.16), style: .continuous))
        .shadow(color: .black.opacity(0.20), radius: size * 0.08, y: size * 0.04)
        .accessibilityHidden(true)
    }

    private var image: NSImage? {
        guard let fileName = song?.artworkFileName else { return nil }
        return NSImage(contentsOf: AppConfiguration.artworkDirectoryURL.appendingPathComponent(fileName))
    }

    private var appLogo: NSImage? {
        guard let url = Bundle.module.url(forResource: "AppLogo", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }
}
