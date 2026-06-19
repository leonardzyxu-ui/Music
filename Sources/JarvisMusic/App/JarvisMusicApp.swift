import AppKit
import SwiftUI

@main
struct JarvisMusicApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .task {
                    await model.start()
                }
        }
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .windowArrangement) {
                Button("Close Window") {
                    MusicWindowActions.mainWindow()?.performClose(nil)
                }
                .keyboardShortcut("w", modifiers: [.command])
            }

            CommandMenu("Playback") {
                Button(model.playback.isPlaying ? "Pause" : "Play") {
                    model.playback.isPlaying ? model.playback.pause() : model.playback.resume()
                }
                .keyboardShortcut(.space, modifiers: [])

                Button("Next") { model.playback.next() }
                    .keyboardShortcut(.rightArrow, modifiers: [.command])
                Button("Previous") { model.playback.previous() }
                    .keyboardShortcut(.leftArrow, modifiers: [.command])
                Divider()
                Button("Refresh Library") {
                    Task { await model.library.scanLibrary() }
                }
                .keyboardShortcut("r", modifiers: [.command])
                Button("Refresh Smart Picker") {
                    model.library.refreshSmartPicker()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }

            CommandMenu("Song") {
                Button("Move to Recycle Bin") {
                    Task {
                        await model.moveSelectedSongsToTrash()
                    }
                }
                .disabled(model.library.selectedSongs.isEmpty)
            }
        }

        Settings {
            SettingsView(model: model)
                .frame(width: 560, height: 360)
        }
    }
}

@MainActor
enum MusicWindowActions {
    static let normalMinimumSize = NSSize(width: 1180, height: 796)
    static let songFocusMinimumSize = NSSize(width: 920, height: 620)
    static let compactSize = NSSize(width: 394, height: 204)
    static var currentMinimumSize: NSSize {
        minimumSize(for: currentPresentationMode)
    }

    private static var isCompactPresentationActive = false
    private static var currentPresentationMode: PlayerPresentationMode = .normal
    private static var storedNormalFrame: NSRect?
    private static let resizeDelegate = MusicWindowResizeDelegate()

    static func mainWindow() -> NSWindow? {
        NSApp.keyWindow
            ?? NSApp.mainWindow
            ?? NSApp.windows.first { $0.title == AppConfiguration.appName && $0.isVisible }
            ?? NSApp.windows.first { $0.isVisible }
    }

    static func applyPlayerPresentationMode(_ mode: PlayerPresentationMode) {
        guard let window = mainWindow() else { return }
        currentPresentationMode = mode
        applyChrome(to: window, mode: mode)
        switch mode {
        case .normal:
            isCompactPresentationActive = false
            window.contentMinSize = contentMinimumSize(for: .normal)
            window.minSize = normalMinimumSize
            window.maxSize = unconstrainedMaximumSize
            if mode == .normal, let storedNormalFrame {
                window.setFrame(storedNormalFrame, display: true, animate: true)
                self.storedNormalFrame = nil
            } else if window.frame.width < normalMinimumSize.width || window.frame.height < normalMinimumSize.height {
                restoreNormalSize(window)
            }
        case .songFocus:
            isCompactPresentationActive = false
            window.contentMinSize = contentMinimumSize(for: .songFocus)
            window.minSize = songFocusMinimumSize
            window.maxSize = unconstrainedMaximumSize
            if window.frame.width < songFocusMinimumSize.width || window.frame.height < songFocusMinimumSize.height {
                restoreMinimumSize(songFocusMinimumSize, window: window)
            }
        case .compact:
            isCompactPresentationActive = true
            storedNormalFrame = storedNormalFrame ?? window.frame
            window.contentMinSize = contentMinimumSize(for: .compact)
            window.minSize = compactSize
            window.maxSize = compactSize
            let center = NSPoint(x: window.frame.midX, y: window.frame.midY)
            let compactFrame = NSRect(
                x: center.x - compactSize.width / 2,
                y: center.y - compactSize.height / 2,
                width: compactSize.width,
                height: compactSize.height
            )
            window.setFrame(compactFrame, display: true, animate: true)
        }
        applyChrome(to: window, mode: mode)
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async {
            applyChrome(to: window, mode: mode)
            window.makeKeyAndOrderFront(nil)
        }
    }

    static func applyAcceptedChrome(to window: NSWindow) {
        applyChrome(to: window, mode: .normal)
    }

    static func applyCurrentChrome(to window: NSWindow) {
        applyChrome(to: window, mode: currentPresentationMode)
    }

    private static func applyChrome(to window: NSWindow, mode: PlayerPresentationMode) {
        installResizeProtection(on: window)
        window.contentMinSize = contentMinimumSize(for: mode)
        window.minSize = minimumSize(for: mode)
        window.maxSize = maximumSize(for: mode)
        window.hasShadow = true
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.titled)
        window.styleMask.insert(.fullSizeContentView)
        window.styleMask.insert([.closable, .miniaturizable, .resizable])
        window.toolbarStyle = .unified
        if #available(macOS 11.0, *) {
            window.titlebarSeparatorStyle = .none
        }
        defer {
            enforceCurrentSizeConstraints(on: window, animate: false)
        }

        switch mode {
        case .normal:
            window.isOpaque = true
            window.backgroundColor = MusicPalette.nsSpaceBlack
            window.isMovableByWindowBackground = false
            resetRoundedMask(on: window)
        case .songFocus:
            window.styleMask.remove(.titled)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.isMovableByWindowBackground = false
            applyRoundedMask(on: window, radius: 34)
        case .compact:
            window.styleMask.remove(.titled)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.isMovableByWindowBackground = true
            applyRoundedMask(on: window, radius: 30)
        }
        window.contentMinSize = contentMinimumSize(for: mode)
        window.minSize = minimumSize(for: mode)
        window.maxSize = maximumSize(for: mode)
    }

    private static func applyRoundedMask(on window: NSWindow, radius: CGFloat) {
        for buttonType in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(buttonType)?.isHidden = true
        }
        if let frameLayer = window.contentView?.superview?.layer {
            frameLayer.cornerRadius = radius
            frameLayer.cornerCurve = .continuous
            frameLayer.masksToBounds = true
        }
        if let contentLayer = window.contentView?.layer {
            contentLayer.cornerRadius = radius
            contentLayer.cornerCurve = .continuous
            contentLayer.masksToBounds = true
        }
    }

    private static func resetRoundedMask(on window: NSWindow) {
        if let frameLayer = window.contentView?.superview?.layer {
            frameLayer.cornerRadius = 0
            frameLayer.masksToBounds = false
        }
        if let contentLayer = window.contentView?.layer {
            contentLayer.cornerRadius = 0
            contentLayer.masksToBounds = false
        }
        for buttonType in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(buttonType)?.isHidden = false
        }
    }

    static func refreshVisibleWindows() {
        for window in NSApp.windows where window.isVisible || window.title == AppConfiguration.appName {
            applyCurrentChrome(to: window)
            enforceCurrentSizeConstraints(on: window, animate: false)
        }
    }

    static func clampedWindowSize(_ proposedSize: NSSize, for window: NSWindow? = nil) -> NSSize {
        let liveMinimumSize = window?.minSize ?? .zero
        let minimumSize = NSSize(
            width: max(currentMinimumSize.width, liveMinimumSize.width),
            height: max(currentMinimumSize.height, liveMinimumSize.height)
        )
        let maximumSize = maximumSize(for: currentPresentationMode)
        return NSSize(
            width: min(max(proposedSize.width, minimumSize.width), maximumSize.width),
            height: min(max(proposedSize.height, minimumSize.height), maximumSize.height)
        )
    }

    static func enforceCurrentSizeConstraints(on window: NSWindow, animate: Bool) {
        let clampedSize = clampedWindowSize(window.frame.size, for: window)
        guard clampedSize.width != window.frame.width || clampedSize.height != window.frame.height else {
            return
        }
        var frame = window.frame
        let oldMaxY = frame.maxY
        frame.size = clampedSize
        frame.origin.y = oldMaxY - clampedSize.height
        window.setFrame(frame, display: true, animate: animate)
    }

    private static func installResizeProtection(on window: NSWindow) {
        if window.delegate !== resizeDelegate {
            window.delegate = resizeDelegate
        }
    }

    private static func restoreNormalSize(_ window: NSWindow) {
        restoreMinimumSize(normalMinimumSize, window: window)
    }

    private static func restoreMinimumSize(_ minimumSize: NSSize, window: NSWindow) {
        let screenFrame = (window.screen ?? NSScreen.main)?.visibleFrame ?? window.frame
        let width = min(minimumSize.width, screenFrame.width - 36)
        let height = min(minimumSize.height, screenFrame.height - 36)
        let frame = NSRect(
            x: screenFrame.midX - width / 2,
            y: screenFrame.midY - height / 2,
            width: width,
            height: height
        )
        window.setFrame(frame, display: true, animate: true)
    }

    private static func minimumSize(for mode: PlayerPresentationMode) -> NSSize {
        switch mode {
        case .normal:
            return normalMinimumSize
        case .songFocus:
            return songFocusMinimumSize
        case .compact:
            return compactSize
        }
    }

    private static func maximumSize(for mode: PlayerPresentationMode) -> NSSize {
        mode == .compact ? compactSize : unconstrainedMaximumSize
    }

    private static func contentMinimumSize(for mode: PlayerPresentationMode) -> NSSize {
        switch mode {
        case .normal:
            return NSSize(width: 1, height: 1)
        case .songFocus, .compact:
            return minimumSize(for: mode)
        }
    }

    private static var unconstrainedMaximumSize: NSSize {
        NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    }
}

@MainActor
private final class MusicWindowResizeDelegate: NSObject, NSWindowDelegate {
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        MusicWindowActions.clampedWindowSize(frameSize, for: sender)
    }

    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        MusicWindowActions.enforceCurrentSizeConstraints(on: window, animate: false)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        scheduleInitialWindowFit()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        MusicWindowActions.refreshVisibleWindows()
    }

    private func scheduleInitialWindowFit() {
        for delay in [0.1, 0.35, 0.8, 1.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self.fitVisibleWindows()
            }
        }
    }

    private func fitVisibleWindows() {
        for window in NSApp.windows where window.isVisible || window.title == AppConfiguration.appName {
            let minimumWindowSize = MusicWindowActions.currentMinimumSize
            window.minSize = minimumWindowSize
            MusicWindowActions.applyCurrentChrome(to: window)
            MusicWindowActions.enforceCurrentSizeConstraints(on: window, animate: false)
            guard let screen = window.screen ?? NSScreen.main else { continue }
            let visible = screen.visibleFrame.insetBy(dx: 18, dy: 18)
            var frame = window.frame
            let shouldAdjust = frame.width > visible.width
                || frame.height > visible.height
                || frame.width < minimumWindowSize.width
                || frame.height < minimumWindowSize.height
                || frame.minX < visible.minX
                || frame.maxX > visible.maxX
                || frame.minY < visible.minY
                || frame.maxY > visible.maxY

            if shouldAdjust {
                frame.size.width = min(max(frame.width, minimumWindowSize.width), visible.width)
                frame.size.height = min(max(frame.height, minimumWindowSize.height), visible.height)
                let maximumX = max(visible.minX, visible.maxX - frame.width)
                let maximumY = max(visible.minY, visible.maxY - frame.height)
                frame.origin.x = min(max(frame.minX, visible.minX), maximumX)
                frame.origin.y = min(max(frame.minY, visible.minY), maximumY)
                window.setFrame(frame, display: true, animate: false)
            }
        }
    }
}
