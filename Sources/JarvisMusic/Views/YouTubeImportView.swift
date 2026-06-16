import SwiftUI
import WebKit
import AppKit

struct YouTubeImportView: View {
    @ObservedObject var model: AppModel
    @State private var searchDraft = ""
    @State private var directURLDraft = ""
    @State private var searchResults: [ImportPreview] = []
    @State private var searchStatus = "Search YouTube inside Music, or paste a video URL."
    @State private var showBrowser = false
    @State private var browserIsLoading = false
    @State private var browserProgress = 0.0
    @State private var browserError = ""

    private var selectedPreview: ImportPreview? {
        if let preview = model.importPreview {
            return preview
        }
        guard YouTubeImportService.isSupportedImportURL(model.youtubeCurrentURL) else { return nil }
        return ImportPreview(
            url: model.youtubeCurrentURL,
            title: model.importTitle.isEmpty ? model.youtubePageTitle : model.importTitle,
            thumbnailURL: nil,
            uploader: nil,
            duration: nil
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 760
            VStack(spacing: 0) {
                importHeader(compact: compact)
                    .padding(.top, 22)
                    .padding(.horizontal, compact ? 22 : 28)
                    .padding(.bottom, 18)

                Divider()
                    .opacity(0.72)

                ScrollView {
                    VStack(spacing: 18) {
                        if compact {
                            VStack(spacing: 16) {
                                searchPanel
                                importPanel
                            }
                        } else {
                            HStack(alignment: .top, spacing: 18) {
                                searchPanel
                                    .frame(minWidth: 330, idealWidth: 390, maxWidth: 430)
                                importPanel
                                    .frame(maxWidth: .infinity)
                            }
                        }

                        if showBrowser {
                            browserPanel
                                .frame(height: 360)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                    .padding(.horizontal, compact ? 22 : 28)
                    .padding(.vertical, 22)
                    .padding(.bottom, 96)
                }
            }
            .background(MusicPalette.contentBlack)
        }
        .onAppear(perform: syncDrafts)
        .onChange(of: model.youtubeAddress) { _, newValue in
            directURLDraft = YouTubeImportService.isSupportedImportURL(newValue) ? newValue : directURLDraft
            searchFromAddressIfNeeded(newValue)
        }
    }

    private func importHeader(compact: Bool) -> some View {
        HStack(alignment: .bottom, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("YouTube Import")
                    .font(MusicTypography.display(compact ? 32 : 42))
                    .foregroundStyle(.white)
                Text("Search, choose, rename, and save audio you are allowed to keep.")
                    .font(MusicTypography.fixed(14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Button {
                showBrowser.toggle()
                if showBrowser, let url = selectedPreview?.url {
                    model.youtubeAddress = url
                    model.youtubeCurrentURL = url
                }
            } label: {
                Label(showBrowser ? "Hide Browser" : "Show Browser", systemImage: showBrowser ? "eye.slash" : "globe")
            }
            .buttonStyle(.bordered)
            .tint(.white.opacity(0.34))
        }
    }

    private var searchPanel: some View {
        YouTubeGlassPanel {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Label("Find a Video", systemImage: "magnifyingglass")
                        .font(MusicTypography.fixed(18, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Music searches with yt-dlp and shows candidates here.")
                        .font(MusicTypography.fixed(12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.54))
                }

                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass")
                        .font(MusicTypography.fixed(15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.56))
                    TextField("Search YouTube", text: $searchDraft)
                        .textFieldStyle(.plain)
                        .font(MusicTypography.fixed(14, weight: .medium))
                        .onSubmit { startSearch() }
                    Button {
                        startSearch()
                    } label: {
                        Image(systemName: "arrow.right")
                            .font(MusicTypography.fixed(13, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .disabled(searchDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isImporting)
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background {
                    Capsule(style: .continuous)
                        .fill(Color.black.opacity(0.22))
                    Capsule(style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Already have the video?")
                        .font(MusicTypography.fixed(12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.62))

                    HStack(spacing: 9) {
                        Image(systemName: "link")
                            .font(MusicTypography.fixed(14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.50))
                        TextField("Paste YouTube video URL", text: $directURLDraft)
                            .textFieldStyle(.plain)
                            .font(MusicTypography.fixed(13, weight: .medium))
                            .onSubmit { prepareDirectURL() }
                        Button {
                            prepareDirectURL()
                        } label: {
                            Text("Use")
                                .font(MusicTypography.fixed(12, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.red, in: Capsule(style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(directURLDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isImporting)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.black.opacity(0.16))
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(.white.opacity(0.10), lineWidth: 1)
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: statusIcon)
                        .foregroundStyle(statusColor)
                    Text(searchStatus)
                        .font(MusicTypography.fixed(12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(2)
                }

                resultsList
            }
        }
    }

    private var resultsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Candidates")
                    .font(MusicTypography.fixed(13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.68))
                Spacer()
                if !searchResults.isEmpty {
                    Button {
                        searchResults = []
                        searchStatus = "Search YouTube inside Music, or paste a video URL."
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.42))
                    .help("Clear Results")
                }
            }

            if searchResults.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "music.note.list")
                        .font(MusicTypography.fixed(28, weight: .medium))
                        .foregroundStyle(.white.opacity(0.28))
                    Text("Results appear here")
                        .font(MusicTypography.fixed(13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.56))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.black.opacity(0.12))
                }
            } else {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(searchResults, id: \.url) { result in
                        candidateRow(result)
                    }
                }
            }
        }
    }

    private func candidateRow(_ result: ImportPreview) -> some View {
        let isSelected = model.importPreview?.url == result.url
        return Button {
            choose(result)
        } label: {
            HStack(spacing: 11) {
                YouTubeThumbnail(urlStrings: thumbnailURLs(for: result), size: 58)

                VStack(alignment: .leading, spacing: 4) {
                    Text(result.title)
                        .font(MusicTypography.fixed(13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        if let uploader = result.uploader, !uploader.isEmpty {
                            Text(uploader)
                        }
                        if let duration = result.duration {
                            Text(MusicFormatters.duration(duration))
                        }
                    }
                    .font(MusicTypography.fixed(11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.50))
                }

                Spacer(minLength: 8)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
                    .font(MusicTypography.fixed(19, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.red : Color.white.opacity(0.56))
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.095) : MusicPalette.rowBlack.opacity(0.68))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? Color.red.opacity(0.40) : Color.white.opacity(0.055), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var importPanel: some View {
        YouTubeGlassPanel {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 15) {
                    YouTubeThumbnail(urlStrings: thumbnailURLs(for: selectedPreview), size: 96)

                    VStack(alignment: .leading, spacing: 7) {
                        Text(selectedPreview?.title ?? "Choose a video")
                            .font(MusicTypography.fixed(22, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)

                        if let uploader = selectedPreview?.uploader {
                            Text(uploader)
                                .font(MusicTypography.fixed(13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.58))
                                .lineLimit(1)
                        } else {
                            Text("Search or paste a direct video URL first.")
                                .font(MusicTypography.fixed(13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.52))
                        }

                        if let duration = selectedPreview?.duration {
                            Text(MusicFormatters.duration(duration))
                                .font(MusicTypography.fixed(12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.46))
                        }
                    }

                    Spacer(minLength: 8)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Song name")
                        .font(MusicTypography.fixed(12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.64))

                    TextField("Name before saving", text: $model.importTitle)
                        .textFieldStyle(.plain)
                        .font(MusicTypography.fixed(16, weight: .semibold))
                        .padding(.horizontal, 13)
                        .frame(height: 40)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.black.opacity(0.18))
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(.white.opacity(0.12), lineWidth: 1)
                        }
                        .disabled(selectedPreview == nil || model.isImporting)
                }

                permissionNotice
                importProgressCard

                HStack(spacing: 10) {
                    Button {
                        Task { await previewSelectedURL() }
                    } label: {
                        Label("Read Title", systemImage: "text.magnifyingglass")
                    }
                    .buttonStyle(.bordered)
                    .disabled(selectedPreview == nil || model.isImporting)

                    Button {
                        if let url = selectedPreview?.url {
                            model.youtubeAddress = url
                            model.youtubeCurrentURL = url
                            showBrowser = true
                        }
                    } label: {
                        Label("Open Original", systemImage: "globe")
                    }
                    .buttonStyle(.bordered)
                    .disabled(selectedPreview == nil)

                    Spacer()

                    Button {
                        Task { await importSelectedURL() }
                    } label: {
                        Label(model.isImporting ? "Importing" : "Import MP3", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(canImportSelected ? .red : .gray)
                    .disabled(!canImportSelected || model.isImporting)
                }
                .controlSize(.large)

                importActivityPanel
            }
        }
    }

    private var permissionNotice: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.shield")
                .foregroundStyle(.green)
            Text("Only import audio Leo has rights or permission to save. Music extracts audio with helper tools and will not bypass DRM or access controls.")
                .font(MusicTypography.fixed(12, weight: .medium))
                .foregroundStyle(.white.opacity(0.56))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var importProgressCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                if model.isImporting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: progressIcon)
                        .foregroundStyle(progressColor)
                }

                Text(model.importStatus)
                    .font(MusicTypography.fixed(13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(2)

                Spacer()

                Text(progressPercentText)
                    .font(MusicTypography.fixed(13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.64))
                    .monospacedDigit()
            }

            FlatProgressBar(value: model.youtubeImportProgressFraction)
                .frame(height: 5)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.16))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.07), lineWidth: 1)
        }
    }

    private var importActivityPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("Import Activity", systemImage: "waveform.path.ecg")
                    .font(MusicTypography.fixed(13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.70))
                Spacer()
                if !model.importActivityLog.isEmpty {
                    Button {
                        model.clearImportActivity()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.42))
                    .help("Clear Import Activity")
                }
            }

            if model.importActivityLog.isEmpty {
                Text("No import activity yet.")
                    .font(MusicTypography.fixed(12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
                    .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(model.importActivityLog.prefix(4))) { entry in
                        importActivityRow(entry)
                    }
                }
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.12))
        }
    }

    private func importActivityRow(_ entry: ImportActivityEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: entry.state.symbolName)
                .font(MusicTypography.fixed(12, weight: .semibold))
                .foregroundStyle(importActivityColor(entry.state))
                .symbolEffect(.pulse, options: .repeating, isActive: entry.state == .active)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(entry.title)
                        .font(MusicTypography.fixed(12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(1)
                    Text(entry.createdAt, style: .time)
                        .font(MusicTypography.fixed(11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.34))
                }
                Text(entry.detail)
                    .font(MusicTypography.fixed(11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.48))
                    .lineLimit(2)
            }
        }
    }

    private var browserPanel: some View {
        YouTubeGlassPanel {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Label("Original YouTube Page", systemImage: "globe")
                        .font(MusicTypography.fixed(14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.78))
                    Text(browserHost)
                        .font(MusicTypography.fixed(12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                    Spacer()
                    if browserIsLoading {
                        ProgressView(value: browserProgress)
                            .frame(width: 120)
                    }
                    Button {
                        model.youtubeAddress = model.youtubeCurrentURL
                        browserError = ""
                    } label: {
                        Label("Reload", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    Button {
                        showBrowser = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.45))
                }
                .padding(.bottom, 12)

                ZStack {
                    YouTubeWebView(
                        address: $model.youtubeAddress,
                        currentURL: $model.youtubeCurrentURL,
                        pageTitle: $model.youtubePageTitle,
                        isLoading: $browserIsLoading,
                        estimatedProgress: $browserProgress,
                        errorMessage: $browserError
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .background(Color.black)

                    if !browserError.isEmpty {
                        browserOverlay
                    }
                }
            }
        }
    }

    private var browserOverlay: some View {
        VStack(spacing: 12) {
            Image(systemName: browserIsLoading ? "globe" : "exclamationmark.triangle")
                .font(MusicTypography.fixed(30, weight: .semibold))
                .foregroundStyle(browserIsLoading ? .white.opacity(0.6) : .yellow)
            Text(browserIsLoading ? "Loading YouTube..." : "YouTube did not load in the embedded browser.")
                .font(MusicTypography.fixed(16, weight: .semibold))
                .foregroundStyle(.white)
            if !browserError.isEmpty {
                Text(browserError)
                    .font(MusicTypography.fixed(12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.58))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            Text("You can still import from the selected URL without showing the website.")
                .font(MusicTypography.fixed(12, weight: .medium))
                .foregroundStyle(.white.opacity(0.50))
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding()
    }

    private var canImportSelected: Bool {
        guard let url = selectedPreview?.url else { return false }
        return YouTubeImportService.isSupportedImportURL(url) && !model.importTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var statusIcon: String {
        if searchStatus.localizedCaseInsensitiveContains("failed") || searchStatus.localizedCaseInsensitiveContains("not installed") {
            return "exclamationmark.triangle.fill"
        }
        if searchStatus.localizedCaseInsensitiveContains("ready") || searchStatus.localizedCaseInsensitiveContains("choose") {
            return "checkmark.circle.fill"
        }
        return "info.circle"
    }

    private var statusColor: Color {
        if statusIcon == "exclamationmark.triangle.fill" { return .red }
        if statusIcon == "checkmark.circle.fill" { return .green }
        return .white.opacity(0.42)
    }

    private var progressIcon: String {
        if model.importStatus.localizedCaseInsensitiveContains("failed") || model.importStatus.localizedCaseInsensitiveContains("not installed") {
            return "exclamationmark.triangle.fill"
        }
        if model.youtubeImportProgressFraction >= 1 {
            return "checkmark.circle.fill"
        }
        return "arrow.down.circle"
    }

    private var progressColor: Color {
        if progressIcon == "exclamationmark.triangle.fill" { return .red }
        if progressIcon == "checkmark.circle.fill" { return .green }
        return .white.opacity(0.50)
    }

    private var progressPercentText: String {
        "\(Int((model.youtubeImportProgressFraction * 100).rounded()))%"
    }

    private var browserHost: String {
        URL(string: model.youtubeCurrentURL)?.host() ?? "youtube.com"
    }

    private func syncDrafts() {
        if YouTubeImportService.isSupportedImportURL(model.youtubeCurrentURL) {
            directURLDraft = model.youtubeCurrentURL
        }
        searchFromAddressIfNeeded(model.youtubeAddress)
    }

    private func startSearch() {
        let query = searchDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        showBrowser = false
        Task { await searchYouTube(query) }
    }

    private func prepareDirectURL() {
        let value = directURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }

        if value.localizedCaseInsensitiveContains("youtube.com") || value.localizedCaseInsensitiveContains("youtu.be") {
            let normalized = normalizedURLString(value)
            model.youtubeAddress = normalized
            model.youtubeCurrentURL = normalized
            showBrowser = false
            browserError = ""

            if YouTubeImportService.isSupportedImportURL(normalized) {
                model.importStatus = "Reading title from pasted URL..."
                searchStatus = "Specific video URL ready."
                Task { await model.previewCurrentYouTubeURL() }
            } else {
                searchStatus = "Paste a specific YouTube video URL, not a channel or results page."
                model.noteImportActivity(.failure, stage: .failed, title: "URL needs a video", detail: searchStatus)
            }
        } else {
            searchDraft = value
            startSearch()
        }
    }

    private func normalizedURLString(_ value: String) -> String {
        if value.hasPrefix("http://") || value.hasPrefix("https://") {
            return value
        }
        return "https://\(value)"
    }

    private func previewSelectedURL() async {
        guard let url = selectedPreview?.url else { return }
        model.youtubeCurrentURL = url
        model.youtubeAddress = url
        await model.previewCurrentYouTubeURL()
    }

    private func importSelectedURL() async {
        guard let urlString = selectedPreview?.url, let url = URL(string: urlString) else { return }
        model.youtubeCurrentURL = urlString
        model.youtubeAddress = urlString
        _ = await model.importYouTube(url: url, title: model.importTitle)
    }

    private func searchYouTube(_ query: String) async {
        searchStatus = "Searching YouTube candidates..."
        model.importPreview = nil
        model.importTitle = ""
        model.importStatus = "Searching YouTube candidates..."
        model.noteImportActivity(.active, stage: nil, title: "Searching YouTube", detail: query)
        do {
            let results = try await model.youtube.search(query: query, limit: 8)
            searchResults = results
            searchStatus = results.isEmpty ? "No candidates found." : "Choose a video, rename it, then import."
            model.importStatus = results.isEmpty ? "No candidates found. Try a different search." : "Choose a video, rename it, then import."
            let detail = results.isEmpty ? "No import candidates found." : "\(results.count) import candidates ready."
            model.noteImportActivity(.success, stage: nil, title: "YouTube search complete", detail: detail)
        } catch {
            searchResults = []
            searchStatus = error.localizedDescription
            model.noteImportActivity(.failure, stage: .failed, title: "YouTube search failed", detail: error.localizedDescription)
        }
    }

    private func searchFromAddressIfNeeded(_ value: String) {
        guard let query = youtubeSearchQuery(from: value), !query.isEmpty else { return }
        searchDraft = query
        showBrowser = false
        Task { await searchYouTube(query) }
    }

    private func youtubeSearchQuery(from value: String) -> String? {
        guard
            let url = URL(string: value),
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            url.path(percentEncoded: false) == "/results"
        else { return nil }
        return components.queryItems?.first(where: { $0.name == "search_query" })?.value
    }

    private func choose(_ preview: ImportPreview) {
        model.importPreview = preview
        model.importTitle = preview.title
        model.importStatus = "Ready to import: \(preview.title)"
        model.youtubePageTitle = preview.title
        model.youtubeCurrentURL = preview.url
        model.youtubeAddress = preview.url
        directURLDraft = preview.url
        showBrowser = false
        browserError = ""
        model.noteImportActivity(.info, stage: nil, title: "Video chosen", detail: preview.title)
    }

    private func importActivityColor(_ state: ImportActivityState) -> Color {
        switch state {
        case .active:
            return .blue
        case .success:
            return .green
        case .failure:
            return .red
        case .info:
            return .white.opacity(0.52)
        }
    }

    private func thumbnailURLs(for preview: ImportPreview?) -> [String] {
        guard let preview else { return [] }
        return [preview.thumbnailURL, YouTubeImportService.inferredThumbnailURL(fromVideoURL: preview.url)]
            .compactMap { $0 }
            .uniqued()
    }
}

private struct YouTubeGlassPanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.075),
                            Color.white.opacity(0.018),
                            Color.black.opacity(0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.18),
                            Color.white.opacity(0.05),
                            Color.black.opacity(0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }
}

private struct YouTubeThumbnail: View {
    var urlStrings: [String]
    var size: CGFloat
    @StateObject private var loader = YouTubeThumbnailLoader()

    var body: some View {
        Group {
            if let image = loader.image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else if loader.isLoading {
                ZStack {
                    placeholder
                    ProgressView()
                        .controlSize(.small)
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: max(10, size * 0.18), style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: max(10, size * 0.18), style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
        .task(id: urlStrings.joined(separator: "|")) {
            await loader.load(urlStrings)
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.red.opacity(0.90),
                    Color.pink.opacity(0.78),
                    Color.blue.opacity(0.78)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "music.note")
                .font(MusicTypography.fixed(size * 0.38, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
        }
    }
}

@MainActor
private final class YouTubeThumbnailLoader: ObservableObject {
    @Published var image: NSImage?
    @Published var isLoading = false

    private static let cache = NSCache<NSString, NSImage>()

    func load(_ urlStrings: [String]) async {
        let candidates = expandedCandidates(from: urlStrings)
        guard !candidates.isEmpty else {
            image = nil
            isLoading = false
            return
        }

        let cacheKey = candidates.joined(separator: "|") as NSString
        if let cached = Self.cache.object(forKey: cacheKey) {
            image = cached
            isLoading = false
            return
        }

        isLoading = true
        defer { isLoading = false }

        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            if let loaded = await Self.fetchImage(from: url) {
                Self.cache.setObject(loaded, forKey: cacheKey)
                image = loaded
                return
            }
        }

        image = nil
    }

    private func expandedCandidates(from urlStrings: [String]) -> [String] {
        var candidates = urlStrings
        for value in urlStrings {
            guard let id = Self.youtubeID(fromThumbnailURL: value) else { continue }
            candidates.append("https://i.ytimg.com/vi/\(id)/hqdefault.jpg")
            candidates.append("https://i.ytimg.com/vi/\(id)/mqdefault.jpg")
            candidates.append("https://i.ytimg.com/vi/\(id)/default.jpg")
        }
        return candidates.uniqued()
    }

    private static func youtubeID(fromThumbnailURL value: String) -> String? {
        guard let url = URL(string: value) else { return nil }
        let parts = url.pathComponents
        guard let viIndex = parts.firstIndex(of: "vi") else { return nil }
        let idIndex = parts.index(after: viIndex)
        guard parts.indices.contains(idIndex), !parts[idIndex].isEmpty else { return nil }
        return parts[idIndex]
    }

    private static func fetchImage(from url: URL) async -> NSImage? {
        for configuration in [URLSessionConfiguration.ephemeral, localProxyConfiguration()] {
            guard let data = try? await URLSession(configuration: configuration).data(from: url).0,
                  let image = NSImage(data: data) else {
                continue
            }
            return image
        }
        return nil
    }

    private static func localProxyConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable as String: true,
            kCFNetworkProxiesHTTPProxy as String: "127.0.0.1",
            kCFNetworkProxiesHTTPPort as String: 7890,
            kCFNetworkProxiesHTTPSEnable as String: true,
            kCFNetworkProxiesHTTPSProxy as String: "127.0.0.1",
            kCFNetworkProxiesHTTPSPort as String: 7890
        ]
        return configuration
    }
}

private extension Array where Element == String {
    func uniqued() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}

private struct FlatProgressBar: View {
    var value: Double

    var body: some View {
        GeometryReader { proxy in
            let clamped = min(max(value, 0), 1)
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.14))
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.92))
                    .frame(width: proxy.size.width * clamped)
            }
        }
        .accessibilityLabel("Import progress")
        .accessibilityValue("\(Int((min(max(value, 0), 1) * 100).rounded())) percent")
    }
}

struct YouTubeWebView: NSViewRepresentable {
    @Binding var address: String
    @Binding var currentURL: String
    @Binding var pageTitle: String
    @Binding var isLoading: Bool
    @Binding var estimatedProgress: Double
    @Binding var errorMessage: String

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.observe(webView)
        context.coordinator.loadedAddress = address
        load(address, in: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.loadedAddress != address {
            context.coordinator.loadedAddress = address
            load(address, in: webView)
        }
    }

    private func load(_ value: String, in webView: WKWebView) {
        guard let url = URL(string: value) else { return }
        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData))
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: YouTubeWebView
        var loadedAddress = ""
        private var progressObservation: NSKeyValueObservation?
        private var loadingObservation: NSKeyValueObservation?

        init(_ parent: YouTubeWebView) {
            self.parent = parent
        }

        func observe(_ webView: WKWebView) {
            progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
                Task { @MainActor in
                    self?.parent.estimatedProgress = webView.estimatedProgress
                }
            }
            loadingObservation = webView.observe(\.isLoading, options: [.new]) { [weak self] webView, _ in
                Task { @MainActor in
                    self?.parent.isLoading = webView.isLoading
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.currentURL = webView.url?.absoluteString ?? parent.address
            parent.pageTitle = webView.title ?? "YouTube"
            parent.isLoading = false
            parent.estimatedProgress = 1
            parent.errorMessage = ""
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            parent.currentURL = webView.url?.absoluteString ?? parent.address
            parent.pageTitle = webView.title ?? "YouTube"
            parent.isLoading = true
            parent.errorMessage = ""
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
            parent.errorMessage = error.localizedDescription
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
            parent.errorMessage = error.localizedDescription
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }
    }
}
