import SwiftUI

struct SidebarView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var library: LibraryStore
    var compact: Bool
    var cornerRadius: CGFloat
    var onNewPlaylist: () -> Void

    init(
        model: AppModel,
        compact: Bool = false,
        cornerRadius: CGFloat = 22,
        onNewPlaylist: @escaping () -> Void = {}
    ) {
        self.model = model
        self.library = model.library
        self.compact = compact
        self.cornerRadius = cornerRadius
        self.onNewPlaylist = onNewPlaylist
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Music")
                .font(MusicTypography.sidebarTitle)
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.top, 86)
                .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    sidebarSection("Library") {
                        sidebarButton(selection: .allSongs, icon: "music.note", title: "Songs", count: library.songs.count)
                        sidebarButton(selection: .smartPicker, icon: "sparkles", title: "Your Pick", count: library.smartSongs.count)
                    }

                    sidebarSection("Playlists") {
                        ForEach(library.groups, id: \.self) { group in
                            sidebarButton(selection: .group(group), icon: "square.fill", title: group, count: library.songs.filter { $0.group == group }.count)
                                .contextMenu {
                                    Button("Rename") {
                                        if let name = Prompt.text(title: "Rename Group", message: "Rename '\(group)' to:", defaultValue: group) {
                                            library.renameGroup(group, to: name)
                                        }
                                    }
                                    Button("Delete", role: .destructive) {
                                        if Prompt.confirm(title: "Delete Group", message: "Move songs in '\(group)' back to All Songs?") {
                                            library.deleteGroup(group)
                                        }
                                    }
                                }
                        }

                        Button {
                            onNewPlaylist()
                        } label: {
                            Label("New Playlist", systemImage: "plus")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white.opacity(0.76))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }

                    sidebarSection("Import") {
                        sidebarButton(selection: .youtube, icon: "square.and.arrow.down", title: "YouTube", count: nil)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
            }

            Spacer(minLength: 22)
        }
        .background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(MusicPalette.sidebarBlack)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.014),
                            Color.clear,
                            Color.black.opacity(0.018)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.13),
                            Color.white.opacity(0.045),
                            Color.black.opacity(0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }

    private func sidebarSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(MusicTypography.sectionLabel)
                    .foregroundStyle(.white.opacity(0.56))
                    .textCase(.uppercase)
                Spacer()
            }
            .padding(.horizontal, 10)

            VStack(spacing: 3) {
                content()
            }
        }
    }

    private func sidebarButton(selection: LibrarySelection, icon: String, title: String, count: Int?) -> some View {
        let isSelected = library.selection == selection
        return Button {
            library.selection = selection
        } label: {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .frame(width: 18)
                Text(title)
                    .lineLimit(1)
                Spacer()
                if let count {
                    Text("\(count)")
                        .foregroundStyle(isSelected ? Color.red : Color.white.opacity(0.64))
                        .font(.system(.caption, design: .default))
                        .opacity(compact ? 0 : 1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.075))
                }
            }
            .foregroundStyle(isSelected ? Color.red : Color.white.opacity(0.86))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
