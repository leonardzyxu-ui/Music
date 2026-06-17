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
    static let normalMinimumSize = NSSize(width: 1180, height: 760)
    static let compactSize = NSSize(width: 430, height: 226)
    static var currentMinimumSize: NSSize {
        isCompactPresentationActive ? compactSize : normalMinimumSize
    }

    private static var isCompactPresentationActive = false
    private static var storedNormalFrame: NSRect?

    static func mainWindow() -> NSWindow? {
        NSApp.keyWindow
            ?? NSApp.mainWindow
            ?? NSApp.windows.first { $0.title == AppConfiguration.appName && $0.isVisible }
            ?? NSApp.windows.first { $0.isVisible }
    }

    static func applyPlayerPresentationMode(_ mode: PlayerPresentationMode) {
        guard let window = mainWindow() else { return }
        applyAcceptedChrome(to: window)
        switch mode {
        case .normal, .songFocus:
            isCompactPresentationActive = false
            window.minSize = normalMinimumSize
            if mode == .normal, let storedNormalFrame {
                window.setFrame(storedNormalFrame, display: true, animate: true)
                self.storedNormalFrame = nil
            } else if window.frame.width < normalMinimumSize.width || window.frame.height < normalMinimumSize.height {
                restoreNormalSize(window)
            }
        case .compact:
            isCompactPresentationActive = true
            storedNormalFrame = storedNormalFrame ?? window.frame
            window.minSize = compactSize
            let center = NSPoint(x: window.frame.midX, y: window.frame.midY)
            let compactFrame = NSRect(
                x: center.x - compactSize.width / 2,
                y: center.y - compactSize.height / 2,
                width: compactSize.width,
                height: compactSize.height
            )
            window.setFrame(compactFrame, display: true, animate: true)
        }
        applyAcceptedChrome(to: window)
        DispatchQueue.main.async {
            applyAcceptedChrome(to: window)
        }
    }

    static func applyAcceptedChrome(to window: NSWindow) {
        window.isOpaque = true
        window.backgroundColor = MusicPalette.nsSpaceBlack
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
    }

    private static func restoreNormalSize(_ window: NSWindow) {
        let screenFrame = (window.screen ?? NSScreen.main)?.visibleFrame ?? window.frame
        let width = min(normalMinimumSize.width, screenFrame.width - 36)
        let height = min(normalMinimumSize.height, screenFrame.height - 36)
        let frame = NSRect(
            x: screenFrame.midX - width / 2,
            y: screenFrame.midY - height / 2,
            width: width,
            height: height
        )
        window.setFrame(frame, display: true, animate: true)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        scheduleWindowFit()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        scheduleWindowFit()
    }

    private func scheduleWindowFit() {
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
            MusicWindowActions.applyAcceptedChrome(to: window)
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
                frame.origin.x = visible.midX - frame.width / 2
                frame.origin.y = visible.midY - frame.height / 2
                window.makeKeyAndOrderFront(nil)
                window.setFrame(frame, display: true, animate: false)
                window.orderFrontRegardless()
            }
        }
    }
}
