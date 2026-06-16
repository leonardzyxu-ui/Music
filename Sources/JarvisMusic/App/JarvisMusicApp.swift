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
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 940, height: 700)
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
        }

        Settings {
            SettingsView(model: model)
                .frame(width: 560, height: 360)
        }
    }
}

@MainActor
enum MusicWindowActions {
    static func mainWindow() -> NSWindow? {
        NSApp.keyWindow
            ?? NSApp.mainWindow
            ?? NSApp.windows.first { $0.title == AppConfiguration.appName && $0.isVisible }
            ?? NSApp.windows.first { $0.isVisible }
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
            window.minSize = NSSize(width: 760, height: 560)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.titled)
            window.styleMask.insert(.fullSizeContentView)
            window.styleMask.insert([.closable, .miniaturizable, .resizable])
            window.toolbarStyle = .unified
            if #available(macOS 11.0, *) {
                window.titlebarSeparatorStyle = .none
            }
            window.isMovableByWindowBackground = false
            configureNativeWindowButtons(for: window)
            applyNativeWindowSurface(to: window)
            guard let screen = window.screen ?? NSScreen.main else { continue }
            let visible = screen.visibleFrame.insetBy(dx: 18, dy: 18)
            var frame = window.frame
            let shouldAdjust = frame.width > visible.width
                || frame.height > visible.height
                || frame.width < window.minSize.width
                || frame.height < window.minSize.height
                || frame.minX < visible.minX
                || frame.maxX > visible.maxX
                || frame.minY < visible.minY
                || frame.maxY > visible.maxY

            if shouldAdjust {
                frame.size.width = min(max(900, min(frame.width, 980)), visible.width)
                frame.size.height = min(max(640, min(frame.height, 740)), visible.height)
                frame.origin.x = visible.midX - frame.width / 2
                frame.origin.y = visible.midY - frame.height / 2
                window.makeKeyAndOrderFront(nil)
                window.setFrame(frame, display: true, animate: false)
                window.orderFrontRegardless()
            }
        }
    }

    private func applyNativeWindowSurface(to window: NSWindow) {
        window.isOpaque = true
        window.backgroundColor = MusicPalette.nsSpaceBlack
        window.hasShadow = true

        if let frameView = window.contentView?.superview {
            frameView.wantsLayer = true
            frameView.layer?.cornerRadius = 0
            frameView.layer?.masksToBounds = false
            frameView.layer?.backgroundColor = MusicPalette.nsSpaceBlack.cgColor
            removeFrameBackingView(from: frameView)
        }

        window.contentView?.wantsLayer = true
        window.contentView?.layer?.cornerRadius = 0
        window.contentView?.layer?.masksToBounds = false
        window.contentView?.layer?.backgroundColor = MusicPalette.nsSpaceBlack.cgColor
        window.invalidateShadow()
    }

    private func removeFrameBackingView(from frameView: NSView) {
        let identifier = NSUserInterfaceItemIdentifier("MusicWindowFrameBacking")
        frameView.subviews.first(where: { $0.identifier == identifier })?.removeFromSuperview()
    }

    private func configureNativeWindowButtons(for window: NSWindow) {
        guard
            let close = window.standardWindowButton(.closeButton),
            let minimize = window.standardWindowButton(.miniaturizeButton),
            let zoom = window.standardWindowButton(.zoomButton)
        else { return }

        for button in [close, minimize, zoom] {
            button.isHidden = false
            button.isEnabled = true
            button.alphaValue = 1
        }

        for (index, button) in [close, minimize, zoom].enumerated() {
            button.setFrameOrigin(
                NSPoint(
                    x: MusicWindowMetrics.trafficLightX + CGFloat(index) * 23,
                    y: MusicWindowMetrics.trafficLightY
                )
            )
        }
    }
}
