# Music App QA Checklist

## Recurring Visual Regressions To Catch Without Leo

- Traffic-light buttons must not sit in a transparent titlebar strip.
- Traffic-light buttons must not hug the top edge; compare their vertical offset to Apple Music before calling the window fixed.
- Traffic-light buttons must not hug the left edge; they should sit comfortably inside the sidebar/top-left chrome area.
- The whole app window must use one opaque, native space-black surface. Do not reintroduce a transparent custom shell/crescent while chasing larger corner radius.
- The sidebar remains the rounded inner pane, with no competing transparent rounded rectangle around the traffic lights.
- Current required shell metrics: native opaque outer window, sidebar inset `10`, inner sidebar radius `28`, traffic lights at `x=24/47/70`, `y=5`.
- `script/test_bridge_contract.py` must fail if custom frame/content masks return, if the window stops being opaque space-black, or if traffic lights move outside the accepted x range.
- `python3 script/audit_window_corners.py` must pass and produce a Music-window-only top-left crop before calling corner work done.
- The top titlebar area and app body must be one continuous Apple-style space-black surface, with no horizontal color band.
- The sidebar footer/avatar is optional. Do not re-add a large personal `LX Leo Xu` badge unless it is deliberately redesigned.
- Use Apple's system/SF Pro typography throughout. In SwiftUI this means default `.system(..., design: .default)` helpers, not rounded/non-native text styling.

## Window Shell

- App bundle uses the provided LocalOS Music logo for `AppLogo.png` and generated `AppIcon.icns`.
- App background is a consistent Apple-style graphite black, not pure RGB black and not patchy.
- The top, leftmost area, sidebar backing, and main content backing do not create obvious different black blocks or seam lines.
- Outer window corners are round enough and look concentric with the inner sidebar corners.
- No white, gray, or transparent light leaks appear on the left, right, top, or bottom edges.
- The sidebar has its own rounded rectangle shape and reaches the top area around the traffic lights.
- Traffic-light buttons are visible, correctly ordered, and vertically aligned like Apple Music.
- Traffic-light buttons have real AppKit actions, accessibility identifiers, direct mouse-down dispatch, and are not covered by the invisible top drag region.

## Layout And Scaling

- Typography should use Apple's system/SF Pro feel throughout, avoiding non-native rounded text where it looks less Apple Music-like.
- Core visible Music surfaces use explicit default system/SF-style font helpers.
- Songs without embedded cover art use the correct Music logo as fallback artwork, not the old generic gradient note tile.
- The app opens usable at the default window size without cropping sidebar labels, row controls, or the now-playing bar.
- Search sits at the top-right and does not cover the sidebar or title content.
- The sidebar selection uses red text/icons/counts.
- New Playlist opens an in-app centered liquid-glass dialog, not an old system prompt.
- New Playlist blurs/dims the rest of the app while the name field is focused.
- New Playlist can be submitted with Create/Return and dismissed with Cancel/Escape or outside click.
- The main song list stays readable at compact and wide widths.
- Play buttons and row text do not overlap at any tested window size.
- `Cmd-W` closes the main window.
- Local diagnostics verify the shared AppKit window-control action path. Manual QA still needs to confirm physical red/yellow/green clicks perform close, minimize, and zoom/full-screen behavior reliably on Leo's desktop.

## Now Playing Capsule

- The floating playback capsule uses semicircle ends and sits over content with visible glass/refraction.
- The playback capsule is slim like Apple Music in the normal state, not universally thick.
- Hovering the capsule does not change its physical size or move surrounding layout.
- The playback capsule has comfortable left and right insets and is not shoved against the right edge.
- The compact state shows transport controls, current track identity, a flat progress rail, and right-side action icons.
- The hover state shows elapsed time, a longer flat scrubber, and remaining time without a slider thumb/lump.
- The progress rail sits under the song identity, not through the song title/artwork.
- Capsule edge lighting is directional and natural, not a uniform white outline.

## Playback And Library

- Existing MP3s play natively from the shared MP3 folder without duplicating the library.
- Library refresh detects added MP3s.
- Auto-sync is active through a 10-second folder fingerprint check and exposes diagnostics for library path, scan interval, last scan time, song count, and added/removed/changed counts.
- Groups/playlists display and can be selected.
- Smart Picker refresh uses a snapshot ranking and does not live-reorder while playing.
- Latest verified library count: 49 songs after the YouTube progress-probe import and Leo's current library state.
- Silent native playback smoke test passes through the bridge: app volume is set to 0, the smoke import plays, `/now-playing` confirms it, playback stops, and app volume is restored.
- Bridge playback-state, seek, shuffle, and repeat controls are verified, and `stop` clears the queue snapshot back to `Idle`.

## YouTube Import

- YouTube Import must be native-first: search/results, paste-URL, rename, progress, and import controls are visible in Music without requiring Leo to browse YouTube first.
- The WKWebView browser is hidden by default. It should appear only after `Show Browser` or `Open Original`, and it must be dismissible.
- Search queries show selectable native results even if the WKWebView page is hidden, blank, or slow.
- At the default window size, candidates remain on the left and the rename/import/progress panel remains visible on the right.
- A fresh search must reset stale import failure text; the right panel should say `Choose a video, rename it, then import.` until a candidate is selected.
- The `Import Activity` panel shows recent browser/search/import stages, success states, and failure messages without covering the candidate list or import controls.
- Import progress uses a spinner plus a flat no-thumb progress bar and percentage.
- Import percentage is driven by streamed `yt-dlp` download output where available, not only coarse stage labels. Latest short-video probe observed `8 -> 12 -> 78 -> 84 -> 100`.
- Active import/search activity rows update or clear instead of piling up stale `active` rows after success/failure.
- Import is enabled only for a specific supported YouTube video URL.
- Import uses yt-dlp and ffmpeg, saves MP3 into the shared library, stores source URL, and refreshes the library.
- yt-dlp/ffmpeg helper subprocesses have bounded timeouts and return friendly errors instead of making the app or Jarvis bridge hang forever. Current search timeout is `60` seconds; full import remains bounded separately.
- The local Python bridge helper default timeout must be long enough for YouTube import/search (`360` seconds), not the old 8-second edge.
- Process timeout diagnostics simulate a slow helper outside the shared MP3 folder, stop it after one second, remove the fake partial temp MP3, and prove the shared library count is unchanged.
- Imported songs can open the original YouTube URL in the in-app browser.
- Verified import artifact: `Codex Import Smoke Test - With Loved Ones.mp3`.
- Verified progress-probe import artifact: `Codex Progress Probe - With Loved Ones.mp3`.
- Verified MP3 metadata: title, artist, embedded JPEG cover art, and original YouTube URL comment.
- Verified app database source URL and bridge `open-original` for imported song.
- Verified scanner source URL recovery from MP3 metadata with no prior database record through the protected `source-metadata` diagnostic.
- Invalid YouTube imports return typed JSON error codes, for example `not_youtube_video_url`, with friendly messages.
- Invalid YouTube imports are verified not to change the library song count.
- Bridge `youtube-import-activity` and `/status.youtubeImport` expose recent import activity for Jarvis.
- `script/jarvis_music_bridge.py youtube-import-watch` lets Jarvis/terminal run a YouTube import while polling progress snapshots instead of waiting silently.
- Cleanup helper exists and dry-runs by default: `script/cleanup_smoke_imports.sh`.

## Jarvis Bridge

- Local control bridge listens only on 127.0.0.1 and uses the local token.
- Capabilities, status, search, groups, playlist controls, play, pause, resume, stop, next, previous, now-playing, playback-state, seek, shuffle, repeat, volume, refresh-library, refresh-smart-picker, youtube-open, youtube-search, youtube-import-activity, and youtube-import return structured JSON.
- Jarvis can list playlist songs, select playlists, play playlist snapshots, create/rename/delete custom playlists, and move songs to playlists through typed bridge actions.
- Library sync diagnostics are available through the bridge, shell helper, and Python client.
- Source metadata diagnostics are available through the bridge, shell helper, and Python client for verifying imported-song source URL recovery.
- Process timeout diagnostics are available through the bridge, shell helper, and Python client for proving timeout cleanup without touching the shared MP3 folder.
- `/capabilities` includes the typed actions Jarvis needs: search, play, playlist controls, YouTube search/import/import-activity, open-original, volume set, and Smart Picker refresh.
- `script/jarvis_music_bridge.py` exposes an importable Python `MusicBridgeClient` for Jarvis-style code and a JSON CLI fallback.
- `MusicBridgeClient.youtube_import_with_progress(...)` exists for Jarvis-side progress callbacks during long imports.
- `script/test_bridge_contract.py` verifies the live app contract: auth, capabilities, status shape, library auto-sync diagnostics, window-control diagnostics, process timeout diagnostics, groups, playlist controls, playback controls, ranked candidates, multi-word search, Smart Picker refresh, volume restore, invalid import rejection, YouTube import activity, idle now-playing, and idle playback-state.
- Search returns ranked candidates so Jarvis can choose naturally instead of relying on brittle keywords.
- Error messages are friendly and product-facing.
- Protected endpoints reject missing or invalid tokens with JSON `401`.
- Multi-word query parameters decode correctly for Jarvis/CLI calls.
- `script/smoke_bridge.sh --youtube` verifies health, auth, status, capabilities, groups, search, process timeout diagnostics, Python client health/capabilities/candidates, the bridge contract test including window-control diagnostics, Smart Picker refresh, invalid import rejection with unchanged song count, YouTube search, smoke-test source metadata recovery, `open-original`, silent native playback, stop, and volume restore.
