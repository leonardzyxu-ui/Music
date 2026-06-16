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
            let showGroup = proxy.size.width > 620
            let showDuration = proxy.size.width > 520
            VStack(spacing: 0) {
                header(compact: proxy.size.width < 620)
                Divider()
                if library.visibleSongs().isEmpty {
                    ContentUnavailableView(
                        library.searchQuery.isEmpty ? "No Songs" : "No Results",
                        systemImage: "music.note",
                        description: Text(library.searchQuery.isEmpty ? "Add MP3 files to the shared library folder, then refresh." : "Try a different title, artist, or album.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(library.visibleSongs()) { song in
                        SongRow(
                            song: song,
                            isCurrent: playback.currentSong?.id == song.id,
                            isPlaying: playback.isPlaying && playback.currentSong?.id == song.id,
                            groups: library.groups,
                            showGroup: showGroup,
                            showDuration: showDuration,
                            play: {
                                playback.play(song: song, queue: library.visibleSongs(), source: library.selection?.title ?? "Library", manual: true)
                            },
                            moveToGroup: { group in
                                library.move(song: song, to: group)
                            },
                            rename: {
                                if let title = Prompt.text(title: "Rename Song", message: "Rename '\(song.title)' to:", defaultValue: song.title), !title.isEmpty {
                                    library.rename(song: song, to: title)
                                }
                            },
                            openOriginal: {
                                model.openOriginalVideo(for: song)
                            }
                        )
                        .listRowInsets(EdgeInsets(top: 5, leading: proxy.size.width < 620 ? 14 : 22, bottom: 5, trailing: proxy.size.width < 620 ? 12 : 22))
                        .listRowBackground(MusicPalette.spaceBlack)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(MusicPalette.spaceBlack)
            .padding(.top, 46)
        }
    }

    private func header(compact: Bool) -> some View {
        HStack(alignment: .bottom, spacing: 20) {
            if let heroSong, !compact {
                ArtworkView(song: heroSong, size: 112)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(library.selection?.title ?? "All Songs")
                    .font(MusicTypography.display(compact ? 30 : 38))
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
            if compact {
                Button {
                    playVisible()
                } label: {
                    Image(systemName: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.red)
                .disabled(library.visibleSongs().isEmpty)
            } else {
                Button {
                    playVisible()
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.red)
                .disabled(library.visibleSongs().isEmpty)
            }
        }
        .padding(.horizontal, compact ? 20 : 28)
        .padding(.vertical, compact ? 18 : 24)
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
    var groups: [String]
    var showGroup: Bool
    var showDuration: Bool
    var play: () -> Void
    var moveToGroup: (String) -> Void
    var rename: () -> Void
    var openOriginal: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ArtworkView(song: song, size: 46)
                .overlay {
                    if isCurrent {
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
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .font(MusicTypography.songSubtitle)
            }
            Spacer(minLength: 20)
            if showGroup {
                Text(song.group)
                    .foregroundStyle(.secondary)
                    .frame(width: 100, alignment: .leading)
                    .lineLimit(1)
            }
            if showDuration {
                Text(MusicFormatters.duration(song.duration))
                    .foregroundStyle(.secondary)
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 54, alignment: .trailing)
            }
            if song.sourceURL != nil {
                Button(action: openOriginal) {
                    Image(systemName: "play.rectangle")
                }
                .buttonStyle(.borderless)
                .help("Open Original Video")
            }
            Button(action: play) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(isPlaying ? .red : .primary)
            .help("Play")
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: play)
        .contextMenu {
            Button("Play", action: play)
            Button("Rename", action: rename)
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
            if song.sourceURL != nil {
                Button("Open Original Video", action: openOriginal)
            }
        }
    }
}
