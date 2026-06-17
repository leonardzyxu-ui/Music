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
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    SidebarView(
                        model: model,
                        onNewPlaylist: presentNewPlaylistDialog
                    )
                    .navigationSplitViewColumnWidth(min: 220, ideal: 236, max: 276)
                } detail: {
                    detailContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(MusicPalette.contentBlack)
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            Color.clear.frame(height: 90)
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
