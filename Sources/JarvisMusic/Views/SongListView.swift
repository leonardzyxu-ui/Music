import SwiftUI

struct SongListView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var library: LibraryStore
    @ObservedObject private var playback: PlaybackStore

    init(model: AppModel) {
        self.model = model
        self.library = model.library
        self.playback = model.playback
    }

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 760
            let showGroup = proxy.size.width > 760
            let showDuration = proxy.size.width > 620
            VStack(spacing: 0) {
                header(compact: compact)
                Divider()
                    .opacity(0.72)
                if library.visibleSongs().isEmpty {
                    ContentUnavailableView(
                        library.searchQuery.isEmpty ? "No Songs" : "No Results",
                        systemImage: "music.note",
                        description: Text(library.searchQuery.isEmpty ? "Add MP3 files to the shared library folder, then refresh." : "Try a different title, artist, or album.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollViewReader { scrollProxy in
                        List(library.visibleSongs(), selection: $library.selectedSongIDs) { song in
                            songRow(song, showGroup: showGroup, showDuration: showDuration)
                            .id(song.id)
                            .listRowInsets(EdgeInsets(top: 5, leading: compact ? 14 : 22, bottom: 5, trailing: compact ? 12 : 22))
                            .listRowBackground(MusicPalette.contentBlack)
                            .tag(song.id)
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            Color.clear.frame(height: 90)
                        }
                        .onChange(of: library.selectedSongIDs) { _, ids in
                            guard let id = ids.first else { return }
                            withAnimation(.snappy(duration: 0.25)) {
                                scrollProxy.scrollTo(id, anchor: .center)
                            }
                        }
                        .onAppear {
                            guard let id = library.selectedSongIDs.first else { return }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                                withAnimation(.snappy(duration: 0.25)) {
                                    scrollProxy.scrollTo(id, anchor: .center)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(MusicPalette.contentBlack)
        }
    }

    private func header(compact: Bool) -> some View {
        HStack(alignment: .center, spacing: 18) {
            if let heroSong, !compact {
                ArtworkView(song: heroSong, size: 92)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(library.selection?.title ?? "All Songs")
                    .font(MusicTypography.display(compact ? 30 : 42))
                HStack(spacing: 10) {
                    Text("\(library.visibleSongs().count) songs")
                    if library.selection == .smartPicker {
                        Text("Snapshot queue")
                        if let refreshed = library.lastSmartPickerRefreshAt {
                            Text("Refreshed \(MusicFormatters.relativeDate(refreshed))")
                        }
                    }
                }
                .foregroundStyle(.secondary)
                .font(.system(.callout, design: .default))
            }
            Spacer()
            if library.selection == .smartPicker {
                Button {
                    library.refreshSmartPicker()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .musicPillButton(.secondary)
                .help("Refresh Your Pick")
            }
            if compact {
                Button {
                    playVisible()
                } label: {
                    Image(systemName: "play.fill")
                }
                .musicPillButton(.primary)
                .disabled(library.visibleSongs().isEmpty)
            } else {
                Button {
                    playVisible()
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .musicPillButton(.primary)
                .disabled(library.visibleSongs().isEmpty)
            }
        }
        .padding(.horizontal, compact ? 20 : 30)
        .padding(.top, compact ? 20 : 26)
        .padding(.bottom, compact ? 16 : 20)
    }

    private func songRow(_ song: Song, showGroup: Bool, showDuration: Bool) -> some View {
        let isSmartPicker = library.selection == .smartPicker
        let isRecycleBin = library.selection == .recycleBin
        let isHighlighted = songIsHighlighted(song)
        return SongRow(
            song: song,
            isCurrent: playback.currentSong?.id == song.id,
            isPlaying: playback.isPlaying && playback.currentSong?.id == song.id,
            isHighlighted: isHighlighted,
            groups: library.groups,
            showGroup: showGroup,
            showDuration: showDuration,
            play: {
                library.selectedSongIDs = [song.id]
                playback.play(song: song, queue: library.visibleSongs(), source: library.selection?.title ?? "Library", manual: true)
            },
            moveToGroup: { group in
                library.move(song: song, to: group)
                if isSmartPicker {
                    library.removeFromSmartPicker(song)
                }
            },
            removeFromSmartPicker: isSmartPicker ? {
                library.removeFromSmartPicker(song)
            } : nil,
            restoreFromTrash: isRecycleBin ? {
                Task {
                    try? await library.restoreFromTrash(song)
                    library.selection = .allSongs
                    library.selectedSongIDs = [song.id]
                }
            } : nil,
            rename: {
                if let title = Prompt.text(title: "Rename Song", message: "Rename '\(song.title)' to:", defaultValue: song.title), !title.isEmpty {
                    library.rename(song: song, to: title)
                }
            },
            openOriginal: {
                model.openOriginalVideo(for: song)
            }
        )
    }

    private func songIsHighlighted(_ song: Song) -> Bool {
        library.selectedSongIDs.contains(song.id) || playback.currentSong?.id == song.id
    }

    private func playVisible() {
        if library.selection == .smartPicker {
            playback.playSmartPicker(from: library)
        } else if let first = library.visibleSongs().first {
            playback.play(song: first, queue: library.visibleSongs(), source: library.selection?.title ?? "Library", manual: true)
        }
    }

    private var heroSong: Song? {
        if let current = playback.currentSong {
            return current
        }
        if case .group = library.selection {
            return library.visibleSongs().first
        }
        return nil
    }
}

struct SongRow: View {
    var song: Song
    var isCurrent: Bool
    var isPlaying: Bool
    var isHighlighted: Bool
    var groups: [String]
    var showGroup: Bool
    var showDuration: Bool
    var play: () -> Void
    var moveToGroup: (String) -> Void
    var removeFromSmartPicker: (() -> Void)?
    var restoreFromTrash: (() -> Void)?
    var rename: () -> Void
    var openOriginal: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ArtworkView(song: song, size: 46)
                .overlay {
                    if isCurrent && !isHighlighted {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(.red.opacity(0.7), lineWidth: 2)
                    }
                }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(song.title)
                        .font(MusicTypography.songTitle)
                        .lineLimit(1)
                    if isPlaying {
                        Image(systemName: "waveform")
                            .foregroundStyle(.red)
                    }
                }
                Text(song.artist)
                    .foregroundStyle(isHighlighted ? .red.opacity(0.78) : .secondary)
                    .lineLimit(1)
                    .font(MusicTypography.songSubtitle)
            }

            Spacer(minLength: 20)
            Group {
                if song.sourceURL != nil {
                    Button(action: openOriginal) {
                        Image(systemName: "play.rectangle")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(isHighlighted ? .red : .secondary)
                    .help("Open Original Video")
                } else {
                    Color.clear
                }
            }
            .frame(width: 24, height: 24)

            if showGroup {
                Text(song.group)
                    .foregroundStyle(isHighlighted ? .red.opacity(0.78) : .secondary)
                    .frame(width: 100, alignment: .leading)
                    .lineLimit(1)
            }
            if showDuration {
                Text(MusicFormatters.duration(song.duration))
                    .foregroundStyle(isHighlighted ? .red.opacity(0.82) : .secondary)
                    .font(MusicTypography.fixed(14, weight: .medium))
                    .frame(width: 54, alignment: .trailing)
            }
            Button(action: play) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(isHighlighted ? .red : (isPlaying ? .red : .primary))
            .help("Play")
        }
        .foregroundStyle(isHighlighted ? .red : .primary)
        .overlay(alignment: .top) {
            selectedSeparator
        }
        .overlay(alignment: .bottom) {
            selectedSeparator
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: play)
        .contextMenu {
            Button("Play", action: play)
            Button("Rename", action: rename)
            if let removeFromSmartPicker {
                Button("Remove from Your Pick", action: removeFromSmartPicker)
            }
            if let restoreFromTrash {
                Button("Restore to All Songs", action: restoreFromTrash)
            } else {
                Menu("Move to Group") {
                    Button("All Songs") { moveToGroup("All Songs") }
                    ForEach(groups, id: \.self) { group in
                        Button(group) { moveToGroup(group) }
                    }
                    Divider()
                    Button("New Group...") {
                        if let group = Prompt.text(title: "Move to New Group", message: "Enter a group name:") {
                            moveToGroup(group)
                        }
                    }
                }
            }
            if song.sourceURL != nil {
                Button("Open Original Video", action: openOriginal)
            }
        }
    }

    @ViewBuilder
    private var selectedSeparator: some View {
        if isHighlighted {
            Rectangle()
                .fill(Color.red.opacity(0.48))
                .frame(height: 1)
                .padding(.leading, 60)
        }
    }
}
