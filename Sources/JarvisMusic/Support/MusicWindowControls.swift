import AppKit
import Foundation

@MainActor
enum MusicWindowControls {
    static func perform(_ action: String, window: NSWindow? = nil) -> Bool {
        record(action)
        guard let target = window ?? MusicWindowActions.mainWindow() else {
            return false
        }

        switch action {
        case "close":
            target.performClose(nil)
            if target.isVisible {
                target.close()
            }
        case "minimize":
            target.performMiniaturize(nil)
        case "zoom":
            target.performZoom(nil)
        default:
            return false
        }
        return true
    }

    static func diagnosticsPayload() -> [String: Any] {
        [
            "visibleWindowCount": NSApp.windows.filter(\.isVisible).count,
            "mainWindowVisible": MusicWindowActions.mainWindow()?.isVisible ?? false,
            "nativeButtons": nativeButtonPayload(),
            "windowShape": windowShapePayload(),
            "events": recentEvents(limit: 12),
            "mode": "native AppKit standardWindowButton controls with unified full-size-content window chrome"
        ]
    }

    private static func windowShapePayload() -> [String: Any] {
        guard let window = MusicWindowActions.mainWindow() else {
            return ["available": false]
        }
        MusicWindowActions.applyAcceptedChrome(to: window)
        let frameLayer = window.contentView?.superview?.layer
        let contentLayer = window.contentView?.layer
        return [
            "available": true,
            "outerCornerMode": "nativeSystemRounded",
            "titlebarAppearsTransparent": window.titlebarAppearsTransparent,
            "titleHidden": window.titleVisibility == .hidden,
            "toolbarStyle": String(describing: window.toolbarStyle),
            "usesFullSizeContentView": window.styleMask.contains(.fullSizeContentView),
            "frameCornerRadius": frameLayer?.cornerRadius ?? 0,
            "frameMasksToBounds": frameLayer?.masksToBounds ?? false,
            "contentCornerRadius": contentLayer?.cornerRadius ?? 0,
            "contentMasksToBounds": contentLayer?.masksToBounds ?? false,
            "isOpaque": window.isOpaque,
            "backgroundIsClear": window.backgroundColor == .clear,
            "backgroundIsSpaceBlack": window.backgroundColor == MusicPalette.nsSpaceBlack
        ]
    }

    private static func nativeButtonPayload() -> [[String: Any]] {
        guard let window = MusicWindowActions.mainWindow() else { return [] }
        let items: [(String, NSWindow.ButtonType)] = [
            ("close", .closeButton),
            ("minimize", .miniaturizeButton),
            ("zoom", .zoomButton)
        ]
        return items.map { name, type in
            let button = window.standardWindowButton(type)
            let frame = button?.frame ?? .zero
            return [
                "name": name,
                "exists": button != nil,
                "visible": button?.isHidden == false,
                "enabled": button?.isEnabled ?? false,
                "frame": [
                    "x": frame.origin.x,
                    "y": frame.origin.y,
                    "width": frame.size.width,
                    "height": frame.size.height
                ]
            ]
        }
    }

    private static func record(_ action: String) {
        try? FileManager.default.createDirectory(at: AppConfiguration.applicationSupportURL, withIntermediateDirectories: true)
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(timestamp) \(action)\n"
        let url = AppConfiguration.windowControlDiagnosticsURL
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private static func recentEvents(limit: Int) -> [String] {
        guard let text = try? String(contentsOf: AppConfiguration.windowControlDiagnosticsURL, encoding: .utf8) else {
            return []
        }
        return Array(text.split(separator: "\n").suffix(limit)).map(String.init)
    }
}
