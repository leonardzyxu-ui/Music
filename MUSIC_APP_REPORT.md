# Music App Report

## App Path

Project:
`/Users/leoxu/Library/CloudStorage/OneDrive-YKPaoSchool上海民办包玉刚实验学校/developer/Music App`

Runnable app bundle:
`/Users/leoxu/Library/CloudStorage/OneDrive-YKPaoSchool上海民办包玉刚实验学校/developer/Music App/dist/Music.app`

Shared MP3 reference:
`SharedMP3Library` points to the existing LocalOS MP3 folder and does not duplicate the library.

## Build And Run

```bash
cd "/Users/leoxu/Library/CloudStorage/OneDrive-YKPaoSchool上海民办包玉刚实验学校/developer/Music App"
./script/build_and_run.sh --verify
```

Jarvis/control helper:

```bash
./script/jarvis-music-control health
./script/jarvis-music-control capabilities
./script/jarvis-music-control library-sync
./script/jarvis-music-control source-metadata SONG_ID
./script/jarvis-music-control process-timeout-diagnostics
./script/jarvis-music-control youtube-error-classification "ERROR: Video unavailable"
./script/jarvis-music-control playlist-songs "Your Pick"
./script/jarvis-music-control playlist-select "All Songs"
./script/jarvis-music-control search Paradise
./script/jarvis-music-control play Paradise
./script/jarvis-music-control stop
./script/jarvis-music-control playback-state
./script/jarvis-music-control volume 0.9
python3 script/jarvis_music_bridge.py candidates Paradise --limit 3
./script/jarvis-music-control youtube-search "allowed video query"
./script/jarvis-music-control youtube-import-plan "https://www.youtube.com/watch?v=VIDEO_ID"
./script/jarvis-music-control youtube-import-activity
./script/jarvis-music-control youtube-import "https://www.youtube.com/watch?v=VIDEO_ID" "Optional Title"
python3 script/jarvis_music_bridge.py youtube-search "wait for me hadestown"
python3 script/jarvis_music_bridge.py youtube-import-plan "https://www.youtube.com/watch?v=VIDEO_ID"
python3 script/jarvis_music_bridge.py youtube-import-watch "https://www.youtube.com/watch?v=VIDEO_ID" "Optional Title"
./script/smoke_bridge.sh --youtube
python3 script/audit_window_corners.py
python3 script/test_bridge_contract.py
./script/cleanup_smoke_imports.sh
```

YouTube import helper:

```bash
./script/install_youtube_tools.sh
```

## Verified

- Built and launched as `Music.app` with bundle ID `com.leoxu.Music` using `./script/build_and_run.sh --verify`.
- Loaded 50 songs from the shared MP3 folder in the latest live status check.
- Native playback works through `AVPlayer`.
- Bridge commands verified: health, status, search, play, pause, resume, next, previous, stop, refresh library, refresh Smart Picker.
- Bridge playback controls now include `playback-state`, `seek`, `shuffle`, and `repeat`, so Jarvis can inspect and control playback timing/modes without UI hacks.
- Stop now clears the active queue snapshot and resets idle playback time, so Jarvis sees a true idle state after `stop`.
- Bridge search returns ranked candidates with matched fields for Jarvis, not just brittle exact keyword matches.
- Bridge is listening on `127.0.0.1:47879` and rejects tokenless protected requests with a friendly JSON `401`.
- Bridge query decoding now handles spaces correctly for CLI/Jarvis calls, including multi-word YouTube searches and import titles.
- Bridge now exposes `GET /capabilities` and `./script/jarvis-music-control capabilities`, so Jarvis can discover typed actions instead of relying on brittle hard-coded endpoint guesses.
- Bridge now exposes `GET /diagnostics/library-sync`, `./script/jarvis-music-control library-sync`, and `python3 script/jarvis_music_bridge.py library-sync`, so Jarvis can verify auto-sync state, library path, scan interval, last scan time, and added/removed/changed counts.
- Bridge now exposes typed playlist/group controls: list playlist songs, select a playlist, play a playlist snapshot, create/rename/delete custom playlists, and move a song to a playlist. The app supports both `/playlist/...` and `/group/...` aliases for compatibility.
- Added `script/jarvis_music_bridge.py`, an importable zero-dependency Python `MusicBridgeClient` plus JSON CLI fallback for Jarvis-style control without touching Jarvis itself.
- Added `MusicBridgeClient.youtube_import_with_progress(...)` and `python3 script/jarvis_music_bridge.py youtube-import-watch ...` so Jarvis/terminal can run a YouTube import while receiving progress snapshots instead of waiting silently.
- Added `script/test_bridge_contract.py`, a live contract test for auth, capabilities, status shape, library auto-sync diagnostics, native window-control diagnostics, process timeout diagnostics, YouTube helper error classification, groups, playlist controls, ranked candidates, multi-word search, Smart Picker refresh, volume restore, invalid import rejection, YouTube import activity, and idle now-playing.
- Added and verified `GET /volume` and `POST /volume?level=...` for app-local volume control without reintroducing a UI volume slider.
- Added and verified `script/smoke_bridge.sh`; default mode checks health, auth failure, status, capabilities, groups, search, Python client health/capabilities/candidates, bridge contract test, Smart Picker refresh, and invalid import rejection. `--youtube` additionally checks YouTube search, `open-original`, silent native playback, `/now-playing`, stop, and volume restore when the smoke-test import exists.
- Smart Picker refresh returns a snapshot ranking and does not live-reorder the active queue.
- YouTube helper tools are available: project-local `Tools/bin/yt-dlp`, Node for yt-dlp JavaScript evaluation, and Homebrew/system `ffmpeg`.
- YouTube helper subprocesses now have bounded timeouts: search has a 60-second cap, preview returns cleanly instead of hanging forever, full import gets a longer budget, and ffmpeg tagging has its own cap.
- The local Python bridge helper default timeout is now 360 seconds, so Jarvis/terminal YouTube search and import calls do not fail at the old 8-second edge while the app is legitimately working.
- YouTube download progress now streams from `yt-dlp` output and maps into the app/bridge percentage instead of relying only on coarse stage labels. The latest short-video probe observed progress values `8 -> 12 -> 78 -> 84 -> 100`.
- Active import/search activity rows update or clear when the matching success/failure arrives, so old `active` rows do not linger below a completed import.
- YouTube audio import now explicitly asks yt-dlp for audio only with `--format bestaudio[acodec!=none]/bestaudio`, passes `--ffmpeg-location`, extracts to MP3, embeds thumbnails, and forces ID3v2.3 metadata compatibility for macOS/Finder.
- The bridge exposes `youtube-import-plan`, a no-download diagnostic that simulates the yt-dlp selector and returns the chosen format id/codecs plus `audioOnly: true` and `sharedLibraryUnchanged: true` when the plan is safe.
- YouTube helper failures are classified into Jarvis-safe typed errors such as private/access-restricted, unavailable, protected content, timeout, and generic helper failure. Error JSON includes `retryable` and `recoverySuggestion` when useful.
- Process timeout cleanup is verified through protected diagnostics: a slow helper is stopped after one second, a fake partial temp MP3 is removed, and the shared library remains unchanged.
- YouTube Import is now native-first: search/paste URL, candidate rows, rename field, permission note, flat progress bar with percentage, and Import MP3 controls are visible in Music without requiring Leo to browse YouTube first.
- The embedded WKWebView browser is hidden by default and appears only through `Show Browser` or `Open Original`.
- At the default window size, candidates stay on the left and the rename/import/progress panel stays visible on the right.
- Fresh YouTube searches reset stale import failure text. Latest targeted app-window inspection showed 8 candidates and the clean status `Choose a video, rename it, then import.`
- YouTube Import now has an in-app `Import Activity` panel showing recent browser/search/import stages and failures without covering the native candidate list or import controls.
- Choosing a candidate switches to a specific `watch?v=...` URL, fills the default song title, and enables `Import MP3`.
- Bridge `youtube-search` returns structured JSON candidates.
- Bridge `youtube-import-activity` returns the same recent import/search/failure activity for Jarvis, and `/status` embeds it under `youtubeImport`.
- Bridge `youtube-import` rejects non-video/search URLs with a typed friendly JSON error, such as `not_youtube_video_url`, instead of downloading blindly.
- Invalid YouTube imports are now contract-tested to leave the library song count unchanged.
- Full YouTube import was verified with a short OurMusicBox royalty-free intro. It created:
  `Codex Import Smoke Test - With Loved Ones.mp3`
- The imported MP3 contains:
  title `Codex Import Smoke Test - With Loved Ones`, artist `OurMusicBox`, embedded JPEG cover art, and comment metadata with `Original YouTube URL: https://www.youtube.com/watch?v=3OJWfgCGGl0`.
- A second short import verified the real progress path and created:
  `Codex Progress Probe - With Loved Ones.mp3`
- The app database stores the imported song source URL, and `open-original` opens it in the in-app YouTube browser. Verified with app-window-only screenshot: `screenshots/youtube-open-original-final.png`.
- The scanner now recovers original YouTube URLs from MP3 metadata even when no prior database record is supplied. Verified through the protected `source-metadata` bridge diagnostic during `./script/smoke_bridge.sh --youtube`.
- `Cmd-W` closes the main window.
- The window shell now uses native AppKit titled hidden-titlebar chrome again. This removes the fragile clipped/borderless shell that caused broken corner resizing and non-working traffic lights.
- Native AppKit traffic-light buttons are present, visible, and enabled according to the protected `window-controls` diagnostic. Latest diagnostic places them at `x=24/47/70, y=5` after correcting the too-far-right and too-far-left attempts.
- The window now uses an opaque native space-black backing surface with no custom frame/content masks. This removes the transparent crescent that appeared when a custom rounded shell was layered inside the real NSWindow.
- The sidebar remains the rounded inner pane: 28-point radius after the 10-point sidebar inset. The bridge contract now fails if custom transparent masks return, if the backing stops being opaque space-black, or if the traffic lights drift out of range.
- Added `script/audit_window_corners.py`, a Music-window-only screenshot audit that saves `screenshots/window-corner-audit.png` plus a top-left crop and fails if the native corner crop falls outside the accepted range.
- The sidebar footer/avatar was removed; the left pane now ends cleanly instead of showing the oversized `LX Leo Xu` badge.
- New Playlist now opens a centered in-app liquid-glass dialog with the rest of the app blurred/dimmed, a focused playlist-name field, Create/Cancel buttons, Return submit, Escape cancel, and outside-click dismiss.
- Added a protected local diagnostics endpoint/client command for window controls. Diagnostics now report the native `standardWindowButton` controls.
- Core visible UI typography now uses explicit default system/SF Pro-style font helpers (`.system(..., design: .default)`) instead of rounded/non-native text styling.
- The bundled app logo is byte-for-byte the provided LocalOS Music logo and is used for `AppLogo.png`, generated `AppIcon.icns`, and in-app fallback artwork for songs without embedded cover art. Verified with app-window-only screenshot: `screenshots/logo-fallback-artwork-pass.png`.
- The now-playing progress rail now sits under the song identity instead of through it. Verified with app-window-only screenshot: `screenshots/now-playing-under-title.png`.
- UI checked by app-window-only screenshots; sidebar, window shell, YouTube Import, and bottom player no longer require full-desktop captures.

## Known Limitations

- YouTube import depends on Leo selecting content he is allowed to save. The app intentionally does not bypass DRM or frame the importer as piracy tooling.
- yt-dlp now receives Node as a JavaScript runtime, but YouTube may still warn that remote challenge-solver components are disabled. I did not silently enable remote code downloads overnight.
- Helper timeouts prevent app/bridge hangs, but a timed-out import still needs Leo/Jarvis to retry once the network or YouTube helper recovers.
- The outer window now favors real macOS hit-testing/resizing plus an opaque native backing over the earlier fragile transparent custom shell. Leo still needs to visually approve the exact native corner feel and traffic-light position in the live app.
- YouTube Import currently uses the native-first redesign. The browser remains available, but it is no longer the default surface.
- Media-key support is wired through `MPRemoteCommandCenter`, including play, pause, toggle, stop, next, previous, and change-playback-position. macOS can still prefer another active media app depending on system focus.
- System Now Playing text/position/queue metadata is enabled. Artwork injection into system Now Playing was tested and intentionally not kept because MediaPlayer asks for artwork from a background queue that crashes Swift actor isolation in this SwiftUI app.
- Existing MP3s without embedded source URLs cannot show an original-video button.
- The smoke/progress test imports were intentionally left in the shared MP3 folder for Leo to inspect. They are clearly named with `Codex Import Smoke Test` and `Codex Progress Probe`; `script/cleanup_smoke_imports.sh` dry-runs by default and can remove them with `--yes`.
- Library auto-sync uses a 10-second folder fingerprint check. New files should appear without manual refresh after the next interval; manual `refresh-library` remains available for immediate sync.

## Last Verification Pass

Last checked: `2026-06-17 01:36 CST`

Commands run:

```bash
./script/build_and_run.sh --verify
bash -n script/jarvis-music-control
./script/jarvis-music-control capabilities
./script/jarvis-music-control library-sync
# targeted app-window screenshot: screenshots/sf-pro-window-controls-pass-2.png
# targeted app-window screenshot: screenshots/logo-fallback-artwork-pass.png
./script/smoke_bridge.sh
./script/smoke_bridge.sh --youtube
python3 script/test_bridge_contract.py
./script/jarvis-music-control youtube-search "OurMusicBox With Loved Ones"
./script/jarvis-music-control youtube-import-plan "https://www.youtube.com/watch?v=Ys7-6_t7OEQ"
./script/jarvis-music-control youtube-open "OurMusicBox With Loved Ones"
./script/jarvis-music-control youtube-import-activity
./script/jarvis-music-control youtube-import "https://www.youtube.com/results?search_query=music" "Invalid"
./script/jarvis-music-control process-timeout-diagnostics
./script/jarvis-music-control youtube-error-classification "ERROR: Video unavailable"
python3 -m py_compile script/jarvis_music_bridge.py script/test_bridge_contract.py
python3 script/test_bridge_contract.py
./script/smoke_bridge.sh --youtube
./script/jarvis-music-control playback-state
./script/jarvis-music-control status
# targeted app-window screenshot: screenshots/youtube-import-activity.png
# targeted app-window screenshot: screenshots/native-window-behavior-pass.png
cmp -s Sources/JarvisMusic/Resources/AppLogo.png dist/Music.app/Contents/Resources/AppLogo.png
/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' dist/Music.app/Contents/Info.plist
python3 script/jarvis_music_bridge.py window-control-action zoom
python3 script/jarvis_music_bridge.py window-controls
python3 script/jarvis_music_bridge.py library-sync
python3 script/jarvis_music_bridge.py source-metadata SONG_ID
python3 script/jarvis_music_bridge.py playback-state
python3 script/jarvis_music_bridge.py seek 0
python3 script/jarvis_music_bridge.py shuffle false
python3 script/jarvis_music_bridge.py repeat off
python3 script/jarvis_music_bridge.py playlist-songs "Your Pick"
python3 script/jarvis_music_bridge.py playlist-select "All Songs"
python3 script/jarvis_music_bridge.py status
python3 script/jarvis_music_bridge.py now-playing
python3 script/jarvis_music_bridge.py volume
python3 script/jarvis_music_bridge.py youtube-open "wait for me hadestown"
python3 script/jarvis_music_bridge.py youtube-import-activity
python3 script/jarvis_music_bridge.py youtube-search "wait for me hadestown"
python3 script/jarvis_music_bridge.py youtube-import-plan "https://www.youtube.com/watch?v=Ys7-6_t7OEQ"
python3 script/jarvis_music_bridge.py youtube-import "https://www.youtube.com/watch?v=3OJWfgCGGl0" "Codex Progress Probe - With Loved Ones"
python3 script/jarvis_music_bridge.py youtube-import-watch --help
swift build
./script/build_and_run.sh --verify
python3 script/jarvis_music_bridge.py window-controls
python3 -m py_compile script/jarvis_music_bridge.py script/test_bridge_contract.py
python3 script/test_bridge_contract.py
python3 script/audit_window_corners.py
python3 script/jarvis_music_bridge.py youtube-search "beauty and a beat" --limit 2
lsof -nP -iTCP:47879 -sTCP:LISTEN
./script/jarvis-music-control now-playing
./script/jarvis-music-control volume
```

Result: build succeeded, targeted app-window inspection showed the native-first YouTube Import screen with browser hidden by default, native candidate search on the left, rename/import/progress controls visible on the right, and clean non-stale status text. Native traffic-light diagnostics report close/minimize/zoom buttons visible and enabled. Window-shape diagnostics now report an opaque native space-black backing with custom transparent frame/content masks disabled, traffic lights at `x=24/47/70, y=5`, and a 28-point rounded inner sidebar. The current live `/status` check reports 50 songs, selected `All Songs`, and idle YouTube import status. Fallback artwork uses the correct Music logo, playlist controls passed create/select/read/rename/delete checks, playback controls passed state/seek/shuffle/repeat checks, stop clears the queue snapshot to `Idle`, source URL metadata recovery passed against the smoke-test MP3 without relying on app database state, process-timeout diagnostics stopped a slow helper after about one second and cleaned temp output, YouTube helper error classification passed, YouTube search returned structured candidates with thumbnail URLs, invalid YouTube import returns typed code `not_youtube_video_url` and leaves song count unchanged, yt-dlp import planning verifies audio-only selection via `--format bestaudio[acodec!=none]/bestaudio` with `videoCodec: none`, `audioOnly: true`, and `sharedLibraryUnchanged: true`, real import progress streamed through the app/bridge during the progress probe, full bridge smoke tests and contract tests passed, playback ended stopped with idle queue/time, and app volume was restored.

## What I Will Do Next

Immediate overnight priorities:

1. Keep the native AppKit window chrome unless Leo explicitly accepts a lower-level custom window implementation. The previous fake rounded shell looked nicer but broke corner resize and traffic-light clicks.
2. Wire real click/selection QA for the native YouTube candidate rows once the Computer Use click-session issue is resolved; current bridge and visual checks pass, but the click tool refused to attach after app-state reads.
3. Keep strengthening Jarvis import flow: search, choose candidate, import, poll import activity, confirm song, and optionally open original video.
4. Keep the bridge contract stable for Jarvis: typed capabilities first, ranked candidates for natural selection, structured JSON errors, local-only token safety, and no UI-hack control path.
5. Prepare a Jarvis-side adapter plan, but do not touch Jarvis until Leo explicitly asks.

After Leo wakes up:

1. Have Leo physically try the red/yellow/green buttons and side/corner resize on the native-window build. If this still fails, the issue is no longer the fake shell and should be debugged as an AppKit/window-style problem.
2. Decide with Leo whether to enable yt-dlp remote challenge-solver components for stronger YouTube reliability, or keep the safer local-only helper setup.
3. Ask the Jarvis agent which integration it prefers long term: direct HTTP, the importable Python client, the local CLI wrapper, or a combination. My current recommendation is Python client inside Jarvis code, HTTP as the protocol contract, and CLI as a debugging/fallback surface.
4. After the Jarvis agent answers, write a tiny integration adapter on the Jarvis side only if Leo explicitly asks to modify Jarvis; until then, keep this app self-contained.
5. Decide whether to remove the Codex smoke/progress-test MP3s with `./script/cleanup_smoke_imports.sh --yes` after Leo inspects them.

## Open Questions

No blocking questions right now.
