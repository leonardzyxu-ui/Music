import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var library: LibraryStore
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isShowingNewPlaylistDialog = false
    @State private var newPlaylistName = ""

    init(model: AppModel) {
        self.model = model
        self.library = model.library
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                switch model.playerPresentationMode {
                case .normal:
                    libraryShell
                case .songFocus:
                    SongFocusView(model: model)
                        .ignoresSafeArea()
                case .compact:
                    CompactPlayerView(model: model)
                        .ignoresSafeArea()
                }

                if isShowingNewPlaylistDialog {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .overlay(Color.black.opacity(0.28))
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .onTapGesture(perform: dismissNewPlaylistDialog)

                    NewPlaylistGlassDialog(
                        name: $newPlaylistName,
                        create: createNewPlaylist,
                        cancel: dismissNewPlaylistDialog
                    )
                    .frame(width: min(390, max(320, proxy.size.width - 96)))
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
                    .zIndex(20)
                }
            }
        }
    }

    private var libraryShell: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                model: model,
                onNewPlaylist: presentNewPlaylistDialog
            )
            .navigationSplitViewColumnWidth(min: 190, ideal: 206, max: 232)
        } detail: {
            detailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MusicPalette.contentBlack)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Color.clear.frame(height: 112)
                }
                .overlay(alignment: .bottom) {
                    NowPlayingBar(model: model)
                        .padding(.horizontal, 18)
                }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 1180, minHeight: 760)
        .background(MusicPalette.spaceBlack)
        .modifier(
            LibrarySearchToolbar(
                text: Binding(
                    get: { library.searchQuery },
                    set: { library.searchQuery = $0 }
                ),
                isEnabled: library.selection != .youtube
            )
        )
    }

    @ViewBuilder
    private var detailContent: some View {
        if library.selection == .youtube {
            YouTubeImportView(model: model)
        } else {
            SongListView(model: model)
        }
    }

    private func presentNewPlaylistDialog() {
        newPlaylistName = ""
        isShowingNewPlaylistDialog = true
    }

    private func dismissNewPlaylistDialog() {
        isShowingNewPlaylistDialog = false
        newPlaylistName = ""
    }

    private func createNewPlaylist() {
        let name = newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        model.library.addGroup(name)
        model.library.selection = .group(name)
        dismissNewPlaylistDialog()
    }
}

private struct SongFocusView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var playback: PlaybackStore
    @State private var controlsHover = false

    init(model: AppModel) {
        self.model = model
        self.playback = model.playback
    }

    var body: some View {
        GeometryReader { proxy in
            let song = playback.currentSong
            ZStack {
                FocusBackdrop(song: song)
                    .ignoresSafeArea()

                VStack {
                    HStack {
                        HStack(spacing: 0) {
                            Button {
                                model.playerPresentationMode = .normal
                            } label: {
                                Image(systemName: "xmark")
                                    .font(MusicTypography.fixed(22, weight: .medium))
                                    .frame(width: 54, height: 44)
                            }
                            .buttonStyle(.plain)

                            Divider()
                                .frame(height: 24)
                                .overlay(Color.white.opacity(0.18))

                            Button {
                                model.playerPresentationMode = .compact
                            } label: {
                                Image(systemName: "rectangle.on.rectangle")
                                    .font(MusicTypography.fixed(20, weight: .semibold))
                                    .frame(width: 60, height: 44)
                            }
                            .buttonStyle(.plain)
                        }
                        .foregroundStyle(.white.opacity(0.92))
                        .background {
                            Capsule(style: .continuous)
                                .fill(.ultraThinMaterial)
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.07))
                        }
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(0.22), lineWidth: 1)
                        }

                        Spacer()
                    }
                    .padding(.top, 18)
                    .padding(.horizontal, 92)

                    Spacer()

                    VStack(alignment: .leading, spacing: 22) {
                        ArtworkView(song: song, size: min(280, max(190, proxy.size.width * 0.23)))
                            .shadow(color: .black.opacity(0.45), radius: 34, y: 18)

                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(song?.title ?? "Not Playing")
                                    .font(MusicTypography.fixed(20, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.94))
                                    .lineLimit(1)
                                Text(song?.artist ?? "Choose a song")
                                    .font(MusicTypography.fixed(15, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.72))
                                    .lineLimit(1)
                            }
                            Spacer()
                        }

                        FocusProgressBar(playback: playback)
                            .frame(width: min(430, proxy.size.width * 0.38), height: 24)

                        FocusTransportControls(playback: playback, showsSecondary: false)
                            .frame(width: min(430, proxy.size.width * 0.38))
                    }
                    .padding(.leading, 118)
                    .padding(.bottom, 58)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .onHover { controlsHover = $0 }
        }
        .background(MusicPalette.spaceBlack)
    }
}

private struct CompactPlayerView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var playback: PlaybackStore
    @State private var isHovering = false

    init(model: AppModel) {
        self.model = model
        self.playback = model.playback
    }

    var body: some View {
        ZStack(alignment: .top) {
            FocusBackdrop(song: playback.currentSong)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    ArtworkView(song: playback.currentSong, size: 54)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(playback.currentSong?.title ?? "Not Playing")
                            .font(MusicTypography.fixed(17, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.94))
                            .lineLimit(1)
                        Text(playback.currentSong?.artist ?? "Choose a song")
                            .font(MusicTypography.fixed(14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.68))
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .opacity(isHovering ? 0 : 1)

                FocusProgressBar(playback: playback)
                    .frame(height: 22)

                FocusTransportControls(playback: playback, showsSecondary: true)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)

            if isHovering {
                compactHoverChrome
                    .transition(.opacity)
            }
        }
        .frame(minWidth: 394, minHeight: 204)
        .onHover { hovering in
            withAnimation(.snappy(duration: 0.16)) {
                isHovering = hovering
            }
        }
    }

    private var compactHoverChrome: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                compactTrafficButton(color: Color(red: 1.0, green: 0.31, blue: 0.35), action: "close")
                compactTrafficButton(color: Color(red: 1.0, green: 0.78, blue: 0.16), action: "minimize")
                compactTrafficButton(color: Color(red: 0.20, green: 0.82, blue: 0.34), action: "zoom")
            }

            Spacer()

            HStack(spacing: 8) {
                compactIconButton(systemName: "arrow.down.right.and.arrow.up.left", help: "Expand Player") {
                    model.playerPresentationMode = .songFocus
                }
                compactIconButton(
                    systemName: playback.volume > 0 ? "speaker.wave.2.fill" : "speaker.slash.fill",
                    help: "Mute"
                ) {
                    playback.setVolume(playback.volume > 0 ? 0 : 0.9)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            }
        }
        .padding(.top, 16)
        .padding(.horizontal, 22)
    }

    private func compactTrafficButton(color: Color, action: String) -> some View {
        Button {
            _ = MusicWindowControls.perform(action)
        } label: {
            Circle()
                .fill(color)
                .frame(width: 13, height: 13)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func compactIconButton(systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            Image(systemName: systemName)
                .font(MusicTypography.fixed(19, weight: .semibold))
                .frame(width: 34, height: 34)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.92))
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct FocusBackdrop: View {
    var song: Song?

    var body: some View {
        ZStack {
            if let image = artworkImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 52)
                    .saturation(1.2)
                    .opacity(0.72)
            }

            LinearGradient(
                colors: [
                    dominantTint.opacity(0.72),
                    MusicPalette.spaceBlack.opacity(0.62),
                    Color.black.opacity(0.70)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .background(MusicPalette.spaceBlack)
    }

    private var artworkImage: NSImage? {
        guard let fileName = song?.artworkFileName else { return nil }
        return NSImage(contentsOf: AppConfiguration.artworkDirectoryURL.appendingPathComponent(fileName))
    }

    private var dominantTint: Color {
        guard let image = artworkImage else {
            return Color(red: 0.34, green: 0.36, blue: 0.38)
        }
        return ArtworkDominantColor.color(for: image)
    }
}

private struct FocusProgressBar: View {
    @ObservedObject var playback: PlaybackStore

    var body: some View {
        VStack(spacing: 5) {
            GeometryReader { proxy in
                let fraction = playback.duration > 0 ? min(max(playback.currentTime / playback.duration, 0), 1) : 0
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.20))
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.82))
                        .frame(width: max(0, proxy.size.width * fraction))
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            seek(at: value.location.x, width: proxy.size.width)
                        }
                )
            }
            .frame(height: 5)

            HStack {
                Text(MusicFormatters.duration(playback.currentTime))
                Spacer()
                Text(remainingText)
            }
            .font(MusicTypography.fixed(11, weight: .medium))
            .foregroundStyle(.white.opacity(0.64))
        }
    }

    private var remainingText: String {
        guard playback.duration > 0 else { return "--:--" }
        return "-\(MusicFormatters.duration(max(0, playback.duration - playback.currentTime)))"
    }

    private func seek(at xPosition: CGFloat, width: CGFloat) {
        guard playback.duration.isFinite, playback.duration > 0, width > 0 else { return }
        let fraction = min(max(Double(xPosition / width), 0), 1)
        playback.seek(to: playback.duration * fraction)
    }
}

private struct FocusTransportControls: View {
    @ObservedObject var playback: PlaybackStore
    var showsSecondary: Bool

    var body: some View {
        let hasSong = playback.currentSong != nil
        HStack(spacing: showsSecondary ? 18 : 30) {
            Button { playback.shuffle.toggle() } label: {
                Image(systemName: "shuffle")
                    .font(MusicTypography.fixed(23, weight: .semibold))
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.plain)
            .foregroundStyle(controlColor(hasSong: hasSong, active: playback.shuffle))
            .disabled(!hasSong)

            Button { playback.previous() } label: {
                Image(systemName: "backward.fill")
                    .font(MusicTypography.fixed(30, weight: .semibold))
                    .frame(width: 50, height: 46)
            }
            .buttonStyle(.plain)
            .foregroundStyle(controlColor(hasSong: hasSong))
            .disabled(!hasSong)

            Button { playback.isPlaying ? playback.pause() : playback.resume() } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(MusicTypography.fixed(38, weight: .semibold))
                    .frame(width: 64, height: 56)
            }
            .buttonStyle(.plain)
            .foregroundStyle(controlColor(hasSong: hasSong))
            .disabled(!hasSong)

            Button { playback.next() } label: {
                Image(systemName: "forward.fill")
                    .font(MusicTypography.fixed(30, weight: .semibold))
                    .frame(width: 50, height: 46)
            }
            .buttonStyle(.plain)
            .foregroundStyle(controlColor(hasSong: hasSong))
            .disabled(!hasSong)

            Button { playback.repeatMode = (playback.repeatMode + 1) % 3 } label: {
                Image(systemName: playback.repeatMode == 2 ? "repeat.1" : "repeat")
                    .font(MusicTypography.fixed(23, weight: .semibold))
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.plain)
            .foregroundStyle(controlColor(hasSong: hasSong, active: playback.repeatMode > 0))
            .disabled(!hasSong)
        }
        .contentShape(Rectangle())
    }

    private func controlColor(hasSong: Bool, active: Bool = false) -> Color {
        guard hasSong else { return Color.white.opacity(0.28) }
        return active ? .red : Color.white.opacity(0.92)
    }
}

private enum ArtworkDominantColor {
    static func color(for image: NSImage) -> Color {
        guard
            let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff)
        else {
            return Color(red: 0.34, green: 0.36, blue: 0.38)
        }

        var red = CGFloat(0)
        var green = CGFloat(0)
        var blue = CGFloat(0)
        var count = CGFloat(0)
        for xIndex in 0..<7 {
            for yIndex in 0..<7 {
                let x = min(bitmap.pixelsWide - 1, max(0, bitmap.pixelsWide * xIndex / 7))
                let y = min(bitmap.pixelsHigh - 1, max(0, bitmap.pixelsHigh * yIndex / 7))
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                red += color.redComponent
                green += color.greenComponent
                blue += color.blueComponent
                count += 1
            }
        }

        guard count > 0 else { return Color(red: 0.34, green: 0.36, blue: 0.38) }
        let color = NSColor(
            calibratedRed: red / count,
            green: green / count,
            blue: blue / count,
            alpha: 1
        ).usingColorSpace(.sRGB) ?? .darkGray
        return Color(
            red: min(max(color.redComponent * 0.92, 0.22), 0.52),
            green: min(max(color.greenComponent * 0.92, 0.22), 0.52),
            blue: min(max(color.blueComponent * 0.92, 0.22), 0.52)
        )
    }
}

private struct NewPlaylistGlassDialog: View {
    @Binding var name: String
    var create: () -> Void
    var cancel: () -> Void
    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("New Playlist")
                    .font(MusicTypography.fixed(22, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Create a playlist for your library.")
                    .font(MusicTypography.fixed(13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            TextField("Playlist name", text: $name)
                .textFieldStyle(.plain)
                .font(MusicTypography.fixed(16, weight: .medium))
                .padding(.horizontal, 18)
                .frame(height: 44)
                .background {
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.035))
                    Capsule(style: .continuous)
                        .stroke(.white.opacity(0.18), lineWidth: 1)
                }
                .focused($isNameFocused)
                .onSubmit(create)

            HStack(spacing: 10) {
                Spacer()
                Button("Cancel", action: cancel)
                    .musicPillButton(.secondary)
                    .keyboardShortcut(.cancelAction)
                Button("Create", action: create)
                    .keyboardShortcut(.defaultAction)
                    .musicPillButton(.primary)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.045))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.30),
                            Color.white.opacity(0.08),
                            Color.black.opacity(0.20)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: .black.opacity(0.38), radius: 28, y: 16)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                isNameFocused = true
            }
        }
    }
}

private struct LibrarySearchToolbar: ViewModifier {
    @Binding var text: String
    let isEnabled: Bool

    func body(content: Content) -> some View {
        content.toolbar {
            if isEnabled {
                ToolbarItem(placement: .principal) {
                    MusicToolbarSearchField(text: $text)
                        .frame(width: 372)
                        .offset(y: 3)
                }
            }
        }
    }
}

private struct MusicToolbarSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(MusicTypography.fixed(15, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField("Search songs, artists, albums", text: $text)
                .textFieldStyle(.plain)
                .font(.system(.callout, design: .default).weight(.medium))
                .lineLimit(1)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear Search")
            }
        }
        .padding(.horizontal, 13)
        .frame(height: 36)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(MusicPalette.rowBlack.opacity(0.22))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 1)
        }
    }
}
