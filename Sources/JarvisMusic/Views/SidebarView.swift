import SwiftUI

struct SidebarView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var library: LibraryStore
    var onNewPlaylist: () -> Void

    init(
        model: AppModel,
        onNewPlaylist: @escaping () -> Void = {}
    ) {
        self.model = model
        self.library = model.library
        self.onNewPlaylist = onNewPlaylist
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Music")
                    .font(MusicTypography.display(24))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    SidebarSection(title: "Library") {
                        sidebarButton(
                            selection: .allSongs,
                            icon: "music.note",
                            title: "Songs",
                            count: "\(library.songs.count)"
                        )
                        sidebarButton(
                            selection: .smartPicker,
                            icon: "sparkles",
                            title: "Your Pick",
                            count: "\(library.smartSongs.count)"
                        )
                        sidebarButton(
                            selection: .recycleBin,
                            icon: "trash",
                            title: "Recycle Bin",
                            count: "\(library.trashedSongs.count)"
                        )
                    }

                    SidebarSection(title: "Playlists") {
                        ForEach(library.groups, id: \.self) { group in
                            sidebarButton(
                                selection: .group(group),
                                icon: "square.fill",
                                title: group,
                                count: "\(library.songs.filter { $0.group == group }.count)"
                            )
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

                        Button(action: onNewPlaylist) {
                            Label("New Playlist", systemImage: "plus")
                                .font(MusicTypography.sidebarItem)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }

                    SidebarSection(title: "Import") {
                        sidebarButton(
                            selection: .youtube,
                            icon: "play.rectangle",
                            title: "YouTube",
                            count: nil
                        )
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func sidebarButton(selection: LibrarySelection, icon: String, title: String, count: String?) -> some View {
        Button {
            select(selection)
        } label: {
            SidebarSelectionRow(
                icon: icon,
                title: title,
                count: count,
                isSelected: library.selection == selection
            )
        }
        .buttonStyle(.plain)
    }

    private func select(_ selection: LibrarySelection) {
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            library.selection = selection
        }
    }
}

private struct SidebarSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(MusicTypography.fixed(13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.34))
                .textCase(nil)
                .padding(.horizontal, 8)
            VStack(spacing: 6) {
                content
            }
        }
    }
}

private struct SidebarSelectionRow: View {
    let icon: String
    let title: String
    let count: String?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 18)
            Text(title)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let count {
                Text(count)
                    .font(MusicTypography.fixed(12, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.red : .white.opacity(0.56))
            }
        }
        .font(MusicTypography.sidebarItem)
        .foregroundStyle(isSelected ? Color.red : .white)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.085))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
