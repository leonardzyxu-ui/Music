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

    static func snapshotPayload() -> [String: Any] {
        guard let window = MusicWindowActions.mainWindow() else {
            return [
                "captured": false,
                "reason": "No visible Music window is available."
            ]
        }
        MusicWindowActions.applyCurrentChrome(to: window)
        guard let view = window.contentView?.superview ?? window.contentView else {
            return [
                "captured": false,
                "reason": "Music window has no renderable root view."
            ]
        }

        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0 else {
            return [
                "captured": false,
                "reason": "Music window root view has an empty size."
            ]
        }

        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: bounds) else {
            return [
                "captured": false,
                "reason": "Music could not allocate an app-owned bitmap snapshot."
            ]
        }

        let appearance = window.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? window.effectiveAppearance
            : NSAppearance(named: .darkAqua) ?? window.effectiveAppearance
        appearance.performAsCurrentDrawingAppearance {
            view.cacheDisplay(in: bounds, to: bitmap)
        }
        guard bitmapLooksVisuallyTrustworthy(bitmap) else {
            return [
                "captured": false,
                "method": "appkit-view-cache-fallback",
                "reason": "AppKit offscreen material rendering did not match the live dark Music window."
            ]
        }
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            return [
                "captured": false,
                "reason": "Music could not encode the app-owned snapshot as PNG."
            ]
        }

        let url = AppConfiguration.appOwnedWindowSnapshotURL
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try png.write(to: url, options: .atomic)
            return [
                "captured": true,
                "method": "appkit-view-cache-fallback",
                "path": url.path,
                "width": bitmap.pixelsWide,
                "height": bitmap.pixelsHigh,
                "scale": bitmap.size.width > 0 ? Double(bitmap.pixelsWide) / bitmap.size.width : 0,
                "visualFidelityWarning": "AppKit offscreen material rendering may differ from the live window.",
                "windowShape": windowShapePayload()
            ]
        } catch {
            return [
                "captured": false,
                "reason": error.localizedDescription,
                "path": url.path
            ]
        }
    }

    private static func bitmapLooksVisuallyTrustworthy(_ bitmap: NSBitmapImageRep) -> Bool {
        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        guard width > 0, height > 0 else { return false }

        var brightPixels = 0
        var darkPixels = 0
        var coloredPixels = 0
        var leftMaterialBrightPixels = 0
        var leftMaterialSamples = 0
        let xStep = max(1, width / 20)
        let yStep = max(1, height / 20)
        for y in stride(from: 0, to: height, by: yStep) {
            for x in stride(from: 0, to: width, by: xStep) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let brightness = (color.redComponent + color.greenComponent + color.blueComponent) / 3
                if brightness > 0.18 { brightPixels += 1 }
                if brightness < 0.05 { darkPixels += 1 }
                if max(color.redComponent, color.greenComponent, color.blueComponent) - min(color.redComponent, color.greenComponent, color.blueComponent) > 0.08 {
                    coloredPixels += 1
                }
                if x < width / 5 {
                    leftMaterialSamples += 1
                    if brightness > 0.72 {
                        leftMaterialBrightPixels += 1
                    }
                }
            }
        }
        let leftMaterialIsBlownOut = leftMaterialSamples > 0
            && Double(leftMaterialBrightPixels) / Double(leftMaterialSamples) > 0.35
        return brightPixels > 8 && darkPixels > 8 && coloredPixels > 2 && !leftMaterialIsBlownOut
    }

    private static func windowShapePayload() -> [String: Any] {
        guard let window = MusicWindowActions.mainWindow() else {
            return ["available": false]
        }
        MusicWindowActions.applyCurrentChrome(to: window)
        let frameLayer = window.contentView?.superview?.layer
        let contentLayer = window.contentView?.layer
        return [
            "available": true,
            "outerCornerMode": "nativeSystemRounded",
            "titlebarAppearsTransparent": window.titlebarAppearsTransparent,
            "titleHidden": window.titleVisibility == .hidden,
            "toolbarStyle": String(describing: window.toolbarStyle),
            "usesFullSizeContentView": window.styleMask.contains(.fullSizeContentView),
            "windowNumber": window.windowNumber,
            "sharingType": String(describing: window.sharingType),
            "sharingTypeRawValue": window.sharingType.rawValue,
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
