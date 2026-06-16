# Prompt For Separate AI Model: Fix Music Window Corner UI Immediately

You are working on Leo's native macOS Swift/SwiftUI app named `Music`.

Repo path:

`/Users/leoxu/Library/CloudStorage/OneDrive-YKPaoSchool上海民办包玉刚实验学校/developer/Music App`

This is the only priority. Do not work on YouTube import, Jarvis bridge, playlists, Smart Picker, or any other feature until the window corner/chrome UI is fixed and verified.

## Goal

Restore Leo's previously beautiful Apple Music-style UI and fix the whole-window top-left corner/chrome bug once and for all.

Leo's exact requirement:

- Do not add a separate transparent shell, transparent strip, or fake outer container.
- Do not make the inside/sidebar pane rounder as a workaround.
- Make the whole app window itself rounder.
- The outer window corner, inner sidebar pane, and leftmost traffic-light button should visually belong to one concentric geometry.
- The red/yellow/green buttons must be real native working window buttons, not dummy controls.
- The traffic lights must not sit in a transparent titlebar strip.
- The background around the buttons must be the same solid Apple-like space black as the app surface.
- The final top-left corner must look intentional, native, and Apple Music-like.

## Current User-Visible Failure

Leo is currently angry because the latest attempt produced exactly the wrong thing:

- A visible transparent/white/clear shell at the top-left.
- A rounded inner pane that looks like a separate fake rectangle.
- Traffic lights floating in the wrong place inside that fake/transparent area.
- The whole window still does not look rounder in the way Leo asked.

Most recent user-provided screenshot of the bad result:

`/var/folders/38/hlx1c1150v93cm98nkwn8f8c0000gn/T/TemporaryItems/NSIRD_screencaptureui_mxcjfX/Screenshot 2026-06-16 at 6.04.34 PM.png`

Current app-only screenshots captured by Codex:

- `/Users/leoxu/Library/CloudStorage/OneDrive-YKPaoSchool上海民办包玉刚实验学校/developer/Music App/screenshots/window-corner-audit.png`
- `/Users/leoxu/Library/CloudStorage/OneDrive-YKPaoSchool上海民办包玉刚实验学校/developer/Music App/screenshots/window-corner-audit-crop.png`

Apple Music/concentric reference screenshot supplied by Leo:

`/var/folders/38/hlx1c1150v93cm98nkwn8f8c0000gn/T/codex-clipboard-092ad95e-03df-4769-9d69-b9be9c174ca6.png`

## What Has Already Been Tried And Failed

You must inspect the current git diff before changing anything:

```bash
git status --short --branch
git diff -- Sources/JarvisMusic/App/JarvisMusicApp.swift Sources/JarvisMusic/Support/MusicWindowMetrics.swift Sources/JarvisMusic/Views/ContentView.swift Sources/JarvisMusic/Support/MusicWindowControls.swift script/audit_window_corners.py script/test_bridge_contract.py
```

Failed approach 1:

- `window.isOpaque = true`
- `window.backgroundColor = MusicPalette.nsSpaceBlack`
- frame/content layer corner radius set to `0`
- custom transparent masks/backing disabled
- This avoided the transparent shell, but it left the system window's default corner radius. Leo still said the whole-window corner rounding was wrong.

Failed approach 2, currently in the working tree:

- `MusicWindowMetrics.outerCornerRadius = 36`
- `sidebarInset = 10`
- `sidebarCornerRadius = outerCornerRadius - sidebarInset`
- `trafficLightX = 28`
- `trafficLightY` was tried around `12` and then `22`
- `window.isOpaque = false`
- `window.backgroundColor = .clear`
- frame/content layers set to corner radius `36`, `masksToBounds = true`
- `installFrameBackingView(...)` adds `MusicWindowFrameBacking`
- This produced the transparent/fake shell Leo hates. Do not repeat this design.

Earlier transparent backing attempts also caused visible artifacts around the top-left. Do not assume that "clear window plus rounded backing view" is acceptable unless your screenshot proves there is no visible extra shell, no white/clear region, and no fake inner container effect.

## Files And Areas To Inspect First

Start with these files:

- `Sources/JarvisMusic/App/JarvisMusicApp.swift`
- `Sources/JarvisMusic/Support/MusicWindowMetrics.swift`
- `Sources/JarvisMusic/Support/MusicWindowControls.swift`
- `Sources/JarvisMusic/Views/ContentView.swift`
- `Sources/JarvisMusic/Views/SidebarView.swift`
- `script/audit_window_corners.py`
- `script/test_bridge_contract.py`

Before editing, create or update a short note in the repo named:

`MUSIC_UI_PROTECTED_AREAS.md`

In that note, explicitly list which files or parts of files must not be changed because they affect the already-good Music UI. At minimum, protect these unless you can prove a change is necessary:

- `Sources/JarvisMusic/Views/NowPlayingBar.swift`: protect the liquid-glass floating now-playing bar, capsule/semicircle ends, control layout, hover behavior, progress placement, and thickness.
- `Sources/JarvisMusic/Views/SongListView.swift`: protect the Apple Music-like list, row art, row spacing, row separators, title/artist layout, and play buttons.
- `Sources/JarvisMusic/Views/YouTubeImportView.swift`: protect the polished native import UI and candidate thumbnail behavior. Do not bring back a normal YouTube website/browser as the default flow.
- `Sources/JarvisMusic/Support/MusicPalette.swift`: protect the current space-black/Apple Music dark palette unless the window fix absolutely requires one color adjustment.
- `Sources/JarvisMusic/Support/MusicTypography.swift`: protect SF/system typography choices and weights.
- `Sources/JarvisMusic/Views/SidebarView.swift`: protect white sidebar text and red selected state. Only change sidebar layout if needed for the window-corner fix or tab click responsiveness.
- `Sources/JarvisMusic/Views/ContentView.swift`: protect overall Apple Music layout. Only change the root/sidebar/window hit-test/layout path if required.
- All library/playback/bridge/import service code: do not change for this bug unless tests reveal a direct dependency.

## Important Existing Non-Corner Fix To Preserve

There is a separate UI responsiveness bug: when Leo is in YouTube Import and clicks `Songs`, the main pane can stay stuck on YouTube Import until some other state change forces a redraw.

Root cause found:

- `ContentView` observes `AppModel`, but the selected sidebar tab lives inside nested `model.library`.
- SwiftUI may not redraw `ContentView` when `LibraryStore.selection` changes unless `ContentView` also observes `LibraryStore`.

Preserve or implement this fix:

- `ContentView` should hold `@ObservedObject private var library: LibraryStore`
- initialize it with `self.library = model.library`
- use `library.selection` and `library.searchQuery` in the root view switch/search binding

This tab-switching fix is important, but do not let it distract from the main corner/chrome bug.

## Required UI Regression Checklist

After your fix, verify every item below. Do not call the work done until all are true in screenshots and/or tests.

Window/chrome:

- Whole window has rounder outer corners.
- There is no transparent/white/clear fake shell at the top-left.
- There is no separate strip above the app content where the traffic lights float.
- Traffic lights are real native macOS buttons and visibly enabled.
- Red/yellow/green controls close/minimize/zoom correctly.
- `Cmd+W` closes the window.
- Traffic lights are not too high.
- The leftmost close button visually aligns with the rounded outer window geometry.
- Sidebar/inner pane rounding is concentric with the outer window, not independently over-rounded.
- The app background is a uniform Apple-like space black; no obvious top/left shade seam.

Sidebar/navigation:

- Sidebar text is white normally.
- Selected sidebar item text/icon/count are red.
- Sidebar rows are clickable across the full row, including side space.
- Clicking `YouTube`, then clicking `Songs`, switches the main pane immediately.
- Clicking `New Playlist`, then canceling, is not required to force the UI to update.

Now-playing bar:

- Floating bottom bar remains Apple Music-like and liquid-glass.
- Capsule/semicircle ends remain correct.
- Bar does not become universally too thick.
- Bar has enough right margin and is not jammed against the screen/window edge.
- Hover progress behavior remains good.
- Slider/progress line does not run through song title/art; it belongs under the content.
- No large volume slider reappears.

Main app:

- Search field stays top-right and polished.
- Song list still looks like the previously good UI.
- YouTube Import still shows native search/results UI, not the normal YouTube website by default.
- YouTube candidate rows still show real thumbnails.
- Existing 49-song library still appears; do not duplicate or move MP3 files.

## Build And Test Commands

Run all of these from the repo root unless your investigation proves one is obsolete:

```bash
swift build
./script/build_and_run.sh --verify
python3 script/audit_window_corners.py
python3 script/test_bridge_contract.py
python3 script/jarvis_music_bridge.py window-controls
```

Also test proxy-safe local bridge behavior because Leo often exports proxy env vars:

```bash
export https_proxy=http://127.0.0.1:7890 http_proxy=http://127.0.0.1:7890 all_proxy=socks5://127.0.0.1:7890
python3 script/jarvis_music_bridge.py health
```

Take app-only screenshots. Do not capture Leo's whole desktop or personal information.

Use the existing app-only capture script:

```bash
python3 script/audit_window_corners.py
```

If you need another app-only capture, use the same strategy: locate the `Music` window ID and call `screencapture -x -o -l <windowID>`.

## Suggested Direction

Do not blindly keep the current transparent rounded-backing approach. It is visibly wrong.

Investigate whether a more native solution exists:

- Use normal titled/hidden-titlebar NSWindow with native window buttons.
- Avoid adding a second visible outer shape.
- Avoid clear areas around the frame.
- If AppKit cannot change the actual NSWindow outer radius cleanly, consider returning to the opaque native window and matching the inner/sidebar geometry to the native system radius instead of faking a larger outer radius. Leo asked for "rounder", but he hates the fake shell more than the less-rounded native corner.
- If you do use a borderless or shaped window, you must preserve real close/minimize/zoom behavior, resizing, dragging, and no disappearing-on-edge bugs.

The final solution must be judged by screenshots, not by theory.

## Commit Scope

Only commit files directly needed for:

- window corner/chrome fix,
- sidebar tab redraw fix,
- tests/diagnostics that prevent this regression.

Do not commit screenshots. Screenshot paths are ignored and should stay untracked.

## Final Response Expected From You

When done, report:

- exact files changed,
- which files/areas you marked protected,
- test commands run and pass/fail,
- screenshot paths proving the final top-left corner,
- any remaining risk.

If you cannot fix it confidently, stop and explain exactly why, with screenshots and the smallest remaining unknown.
