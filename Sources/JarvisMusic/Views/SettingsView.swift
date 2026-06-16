import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("Library") {
                LabeledContent("Shared MP3 Folder", value: model.library.libraryURL.displayPath)
                LabeledContent("App Database", value: AppConfiguration.databaseURL.displayPath)
                LabeledContent("Project Reference", value: AppConfiguration.sharedLibraryReference.displayPath)
            }

            Section("Jarvis Control Bridge") {
                LabeledContent("Base URL", value: model.bridgeBaseURL)
                LabeledContent("Token File", value: AppConfiguration.tokenURL.displayPath)
            }

            Section("YouTube Helpers") {
                LabeledContent("yt-dlp", value: model.youtube.ytDLPURL?.displayPath ?? "Not found")
                LabeledContent("ffmpeg", value: model.youtube.ffmpegURL?.displayPath ?? "Not found")
            }
        }
        .padding(24)
    }
}
