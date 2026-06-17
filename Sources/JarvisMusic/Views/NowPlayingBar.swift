import AppKit
import SwiftUI

struct NowPlayingBar: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var playback: PlaybackStore
    @ObservedObject private var library: LibraryStore
    @State private var isScrubberHovering = false

    init(model: AppModel) {
        self.model = model
        self.playback = model.playback
        self.library = model.library
    }

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 700
            let leadingInset = compact ? CGFloat(18) : CGFloat(34)
            let trailingInset = compact ? CGFloat(18) : CGFloat(50)
            let barWidth = max(0, proxy.size.width - leadingInset - trailingInset)
            let expanded = isScrubberHovering && playback.duration > 0
            let contentPadding = compact ? CGFloat(16) : CGFloat(18)
            let itemSpacing = compact ? CGFloat(14) : CGFloat(16)
            let leftWidth = compact ? CGFloat(150) : CGFloat(238)
            let rightWidth = compact ? CGFloat(0) : CGFloat(142)
            let spacingBudget = compact ? itemSpacing : itemSpacing * 2
            let availableCenter = barWidth - contentPadding * 2 - leftWidth - rightWidth - spacingBudget
            let centerWidth = max(compact ? CGFloat(112) : CGFloat(178), availableCenter)
            let barHeight = CGFloat(50)

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                HStack {
                    HStack(spacing: itemSpacing) {
                        transportControls(includeModes: !compact)
                            .frame(width: leftWidth, alignment: .leading)

                        centerScrubber(width: centerWidth, expanded: expanded)
                            .frame(maxWidth: .infinity)

                        if !compact {
                            secondaryControls
                                .frame(width: rightWidth, alignment: .trailing)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: barHeight)
                    .padding(.horizontal, contentPadding)
                    .background {
                        Capsule(style: .continuous)
                            .fill(Color.black.opacity(expanded ? 0.016 : 0.008))
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        nowPlayingTint.opacity(expanded ? 0.30 : 0.20),
                                        Color.white.opacity(expanded ? 0.045 : 0.028),
                                        Color.clear,
                                        Color.black.opacity(expanded ? 0.038 : 0.020)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .modifier(NowPlayingGlassSurface(tint: nowPlayingTint))
                    .overlay { capsuleLighting(expanded: expanded) }
                    .shadow(color: .black.opacity(0.22), radius: expanded ? 17 : 13, y: expanded ? 7 : 5)
                    .compositingGroup()
                    .animation(.snappy(duration: 0.18), value: expanded)
                }
                .padding(.leading, leadingInset)
                .padding(.trailing, trailingInset)
                .padding(.bottom, 18)
            }
        }
        .frame(height: 88)
    }

    private func transportControls(includeModes: Bool) -> some View {
        let hasSong = playback.currentSong != nil
        return HStack(spacing: includeModes ? 7 : 13) {
            if includeModes {
                Button {
                    playback.shuffle.toggle()
                } label: {
                    Image(systemName: "shuffle")
                        .font(MusicTypography.fixed(22, weight: .semibold))
                        .frame(width: 40, height: 40)
                        .contentShape(Circle())
                }
                .foregroundStyle(transportColor(hasSong: hasSong, isActive: playback.shuffle))
                .buttonStyle(.plain)
                .help("Shuffle")
                .disabled(!hasSong)
            }

            HStack(spacing: 14) {
                Button { playback.previous() } label: {
                    Image(systemName: "backward.fill")
                        .frame(width: 38, height: 40)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .font(.title2)
                .foregroundStyle(transportColor(hasSong: hasSong))
                .help("Previous")
                .disabled(!hasSong)

                Button {
                    playback.isPlaying ? playback.pause() : playback.resume()
                } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(MusicTypography.fixed(29, weight: .semibold))
                        .frame(width: 44, height: 40)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(transportColor(hasSong: hasSong))
                .help(playback.isPlaying ? "Pause" : "Play")
                .disabled(!hasSong)

                Button { playback.next() } label: {
                    Image(systemName: "forward.fill")
                        .frame(width: 38, height: 40)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .font(.title2)
                .foregroundStyle(transportColor(hasSong: hasSong))
                .help("Next")
                .disabled(!hasSong)
            }

            if includeModes {
                Button {
                    playback.repeatMode = (playback.repeatMode + 1) % 3
                } label: {
                    Image(systemName: playback.repeatMode == 2 ? "repeat.1" : "repeat")
                        .font(MusicTypography.fixed(22, weight: .semibold))
                        .frame(width: 40, height: 40)
                        .contentShape(Circle())
                }
                .foregroundStyle(transportColor(hasSong: hasSong, isActive: playback.repeatMode > 0))
                .buttonStyle(.plain)
                .help("Repeat")
                .disabled(!hasSong)
            }
        }
    }

    private func transportColor(hasSong: Bool, isActive: Bool = false) -> Color {
        guard hasSong else { return Color.secondary.opacity(0.34) }
        return isActive ? .red : .white
    }

    private func centerScrubber(width: CGFloat, expanded: Bool) -> some View {
        Group {
            if expanded {
                ZStack {
                    trackIdentity
                        .blur(radius: 6)
                        .opacity(0.28)

                    HStack(spacing: 10) {
                        Text(MusicFormatters.duration(playback.currentTime))
                            .font(MusicTypography.fixed(14, weight: .semibold))
                            .frame(width: 54, alignment: .trailing)

                        FlatScrubBar(
                            currentTime: playback.currentTime,
                            duration: playback.duration,
                            seek: playback.seek(to:)
                        )
                        .frame(maxWidth: .infinity)

                        Text(remainingText)
                            .font(MusicTypography.fixed(14, weight: .semibold))
                            .frame(width: 58, alignment: .leading)
                    }
                    .foregroundStyle(.primary)
                }
                .contentShape(Rectangle())
                .onHover { hovering in
                    isScrubberHovering = hovering
                }
            } else {
                VStack(spacing: 5) {
                    trackIdentity
                        .offset(y: 3)
                    compactProgressBar
                        .frame(height: 3)
                        .padding(.horizontal, playback.currentSong == nil ? 28 : 0)
                        .padding(.top, 5)
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            isScrubberHovering = hovering
                        }
                        .opacity(playback.duration > 0 ? 1 : 0.45)
                }
            }
        }
        .frame(width: width)
    }

    private var trackIdentity: some View {
        HStack(spacing: 9) {
            if playback.currentSong != nil {
                ArtworkView(song: playback.currentSong, size: 28)
                    .offset(y: 2)
            } else if let image = appLogoImage {
                image
                    .resizable()
                    .scaledToFit()
                    .frame(width: 31, height: 31)
                    .opacity(0.42)
            } else {
                Image(systemName: "music.note")
                    .font(MusicTypography.fixed(24, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.38))
            }

            if playback.currentSong != nil {
                VStack(alignment: .leading, spacing: 2) {
                    Text(playback.currentSong?.title ?? "")
                        .font(MusicTypography.playerTitle)
                        .lineLimit(1)
                    Text(playback.currentSong?.artist ?? "")
                        .font(MusicTypography.playerSubtitle)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var compactProgressBar: some View {
        GeometryReader { proxy in
            let fraction = playback.duration > 0 ? min(max(playback.currentTime / playback.duration, 0), 1) : 0
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.18))
                Capsule()
                    .fill(Color.white.opacity(0.92))
                    .frame(width: max(0, proxy.size.width * fraction))
            }
        }
    }

    private var secondaryControls: some View {
        HStack(spacing: 12) {
            Menu {
                if let song = playback.currentSong {
                    Button(playback.isPlaying ? "Pause" : "Play") {
                        playback.isPlaying ? playback.pause() : playback.resume()
                    }
                    Button("Rename") {
                        if let title = Prompt.text(title: "Rename Song", message: "Rename '\(song.title)' to:", defaultValue: song.title), !title.isEmpty {
                            library.rename(song: song, to: title)
                        }
                    }
                    Section("Move to Group") {
                        Button("All Songs") {
                            moveNowPlayingSong(song, to: "All Songs")
                        }
                        ForEach(library.groups, id: \.self) { group in
                            Button(group) {
                                moveNowPlayingSong(song, to: group)
                            }
                        }
                        Divider()
                        Button("New Group...") {
                            if let group = Prompt.text(title: "Move to New Group", message: "Enter a group name:") {
                                moveNowPlayingSong(song, to: group)
                            }
                        }
                    }
                    if song.sourceURL != nil {
                        Button("Open Original Video") {
                            model.openOriginalVideo(for: song)
                        }
                    }
                    Divider()
                    Button("Move to Recycle Bin", role: .destructive) {
                        library.selectedSongIDs = [song.id]
                        Task { await model.moveSelectedSongsToTrash() }
                    }
                } else {
                    Text("No song selected")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(MusicTypography.fixed(22, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .contentShape(Circle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("More")

            Menu {
                Text(playback.queueSnapshot.source)
                Divider()
                if playback.queueSnapshot.songIDs.isEmpty {
                    Text("Queue is empty")
                } else {
                    ForEach(playback.queueSnapshot.songIDs.prefix(12), id: \.self) { id in
                        if let song = library.song(id: id) {
                            Button(song.title) {
                                _ = playback.playSongID(id)
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "list.bullet")
                    .font(MusicTypography.fixed(22, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .contentShape(Circle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("Queue")

            Button {
                playback.setVolume(playback.volume > 0 ? 0 : 0.9)
            } label: {
                Image(systemName: playback.volume > 0 ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(MusicTypography.fixed(22, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .contentShape(Circle())
            }
            .help("Mute")
        }
        .font(MusicTypography.fixed(21, weight: .semibold))
        .foregroundStyle(.primary.opacity(0.74))
        .buttonStyle(.plain)
    }

    private var appLogoImage: Image? {
        guard
            let url = Bundle.module.url(forResource: "AppLogo", withExtension: "png"),
            let nsImage = NSImage(contentsOf: url)
        else { return nil }
        return Image(nsImage: nsImage)
    }

    private var nowPlayingTint: Color {
        Color.white.opacity(0.10)
    }

    private var remainingText: String {
        guard playback.duration.isFinite, playback.duration > 0 else { return "--:--" }
        let remaining = max(0, playback.duration - playback.currentTime)
        return "-\(MusicFormatters.duration(remaining))"
    }

    private func moveNowPlayingSong(_ song: Song, to group: String) {
        library.move(song: song, to: group)
        if shouldDemoteFromSmartPicker() {
            library.removeFromSmartPicker(song)
        }
    }

    private func shouldDemoteFromSmartPicker() -> Bool {
        if library.selection == .smartPicker {
            return true
        }
        if playback.queueSnapshot.source.localizedCaseInsensitiveContains("Your Pick") {
            return true
        }
        return false
    }

    private func capsuleLighting(expanded: Bool) -> some View {
        ZStack {
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(expanded ? 0.26 : 0.17), lineWidth: 1)
                .mask(
                    LinearGradient(
                        colors: [
                            Color.white,
                            Color.white.opacity(0.55),
                            Color.clear,
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .blendMode(.screen)

            Capsule(style: .continuous)
                .stroke(Color.black.opacity(expanded ? 0.18 : 0.12), lineWidth: 1)
                .mask(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color.clear,
                            Color.black.opacity(0.45),
                            Color.black
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .blendMode(.multiply)

            Capsule(style: .continuous)
                .inset(by: 1.25)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(expanded ? 0.10 : 0.07),
                            Color.clear,
                            Color.white.opacity(expanded ? 0.07 : 0.04)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.75
                )
        }
    }
}

private struct FlatScrubBar: View {
    var currentTime: TimeInterval
    var duration: TimeInterval
    var seek: (TimeInterval) -> Void

    var body: some View {
        GeometryReader { proxy in
            let safeDuration = max(duration, 1)
            let fraction = duration > 0 ? min(max(currentTime / safeDuration, 0), 1) : 0

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.26))
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.92))
                    .frame(width: max(0, proxy.size.width * fraction))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let x = min(max(value.location.x, 0), proxy.size.width)
                        let target = safeDuration * (x / max(proxy.size.width, 1))
                        seek(target)
                    }
            )
        }
        .frame(height: 7)
    }
}

private struct NowPlayingGlassSurface: ViewModifier {
    var tint: Color

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular.tint(tint).interactive(), in: Capsule(style: .continuous))
        } else {
            content
                .background {
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                }
        }
    }
}
