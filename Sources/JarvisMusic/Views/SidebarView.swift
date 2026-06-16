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

            List {
                Section("Library") {
                    Button {
                        select(.allSongs)
                    } label: {
                        SidebarSelectionRow(
                            icon: "music.note",
                            title: "Songs",
                            count: "\(library.songs.count)",
                            isSelected: library.selection == .allSongs
                        )
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())

                    Button {
                        select(.smartPicker)
                    } label: {
                        SidebarSelectionRow(
                            icon: "sparkles",
                            title: "Your Pick",
                            count: "\(library.smartSongs.count)",
                            isSelected: library.selection == .smartPicker
                        )
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                }

                Section("Playlists") {
                    ForEach(library.groups, id: \.self) { group in
                        Button {
                            select(.group(group))
                        } label: {
                            SidebarSelectionRow(
                                icon: "square.fill",
                                title: group,
                                count: "\(library.songs.filter { $0.group == group }.count)",
                                isSelected: library.selection == .group(group)
                            )
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
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
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                }

                Section("Import") {
                    Button {
                        select(.youtube)
                    } label: {
                        SidebarSelectionRow(
                            icon: "square.and.arrow.down",
                            title: "YouTube",
                            count: nil,
                            isSelected: library.selection == .youtube
                        )
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
    }

    private func select(_ selection: LibrarySelection) {
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            library.selection = selection
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
                .frame(width: 16)
            Text(title)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let count {
                Text(count)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(isSelected ? Color.red : .secondary)
            }
        }
        .font(MusicTypography.sidebarItem)
        .foregroundStyle(isSelected ? Color.red : .primary)
        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
        .contentShape(Rectangle())
    }
}
