import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var isShowingNewPlaylistDialog = false
    @State private var newPlaylistName = ""
    private let outerCornerRadius = MusicWindowMetrics.outerCornerRadius
    private let sidebarInset = MusicWindowMetrics.sidebarInset

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 900
            let sidebarWidth = compact ? CGFloat(188) : CGFloat(228)
            ZStack {
                ZStack(alignment: .topTrailing) {
                    HStack(spacing: 0) {
                        SidebarView(
                            model: model,
                            compact: compact,
                            cornerRadius: MusicWindowMetrics.sidebarCornerRadius,
                            onNewPlaylist: presentNewPlaylistDialog
                        )
                        .frame(width: sidebarWidth)
                        .padding(.leading, sidebarInset)
                        .padding(.top, sidebarInset)
                        .padding(.bottom, sidebarInset)
                        .padding(.trailing, 12)
                        .ignoresSafeArea(.container, edges: [.top, .leading])

                        ZStack(alignment: .bottom) {
                            Group {
                                if model.library.selection == .youtube {
                                    YouTubeImportView(model: model)
                                } else {
                                    SongListView(model: model)
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                            NowPlayingBar(playback: model.playback)
                                .zIndex(20)
                        }
                        .background(MusicPalette.contentBlack)
                    }

                    WindowDragRegion()
                        .frame(height: 68)
                        .padding(.leading, 220)
                        .padding(.trailing, dragRegionTrailingInset(totalWidth: proxy.size.width, sidebarWidth: sidebarWidth))
                        .frame(maxWidth: .infinity)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .zIndex(10)

                    if model.library.selection != .youtube {
                        MusicSearchField(text: Binding(
                            get: { model.library.searchQuery },
                            set: { model.library.searchQuery = $0 }
                        ))
                        .frame(width: searchWidth(totalWidth: proxy.size.width, sidebarWidth: sidebarWidth))
                        .padding(.top, 10)
                        .padding(.trailing, 20)
                        .zIndex(80)
                    }
                }
                .blur(radius: isShowingNewPlaylistDialog ? 7 : 0)
                .saturation(isShowingNewPlaylistDialog ? 0.85 : 1)
                .animation(.snappy(duration: 0.2), value: isShowingNewPlaylistDialog)

                if isShowingNewPlaylistDialog {
                    Color.black.opacity(0.28)
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .onTapGesture(perform: dismissNewPlaylistDialog)

                    NewPlaylistGlassDialog(
                        name: $newPlaylistName,
                        create: createNewPlaylist,
                        cancel: dismissNewPlaylistDialog
                    )
                    .frame(width: min(390, max(300, proxy.size.width - 96)))
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
                    .zIndex(200)
                }
            }
            .ignoresSafeArea(.container, edges: .all)
            .background(MusicPalette.spaceBlack)
        }
        .frame(minWidth: 760, minHeight: 560)
        .background(MusicPalette.spaceBlack)
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

    private func searchWidth(totalWidth: CGFloat, sidebarWidth: CGFloat) -> CGFloat {
        let available = totalWidth - sidebarWidth - 94
        return min(390, max(260, available))
    }

    private func dragRegionTrailingInset(totalWidth: CGFloat, sidebarWidth: CGFloat) -> CGFloat {
        if model.library.selection == .youtube {
            return 18
        }
        return searchWidth(totalWidth: totalWidth, sidebarWidth: sidebarWidth) + 44
    }
}

private struct NewPlaylistGlassDialog: View {
    @Binding var name: String
    var create: () -> Void
    var cancel: () -> Void
    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("New Playlist")
                    .font(MusicTypography.fixed(22, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Name this playlist.")
                    .font(MusicTypography.fixed(13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            TextField("Playlist name", text: $name)
                .textFieldStyle(.plain)
                .font(MusicTypography.fixed(16, weight: .medium))
                .padding(.horizontal, 13)
                .frame(height: 38)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black.opacity(0.18))
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(0.14), lineWidth: 1)
                }
                .focused($isNameFocused)
                .onSubmit(create)

            HStack(spacing: 10) {
                Spacer()
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("Create", action: create)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .controlSize(.large)
        }
        .padding(22)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.10),
                            Color.white.opacity(0.025),
                            Color.black.opacity(0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
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

private struct WindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        DragView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

private struct MusicSearchField: View {
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
