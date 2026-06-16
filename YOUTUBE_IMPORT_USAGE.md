# YouTube Import Usage

## In The App

1. Open `Music`.
2. Click `YouTube` in the left sidebar.
3. Use `Find a Video` to search YouTube inside Music, or paste a direct YouTube video URL into `Already have the video?`.
4. If you searched by words, choose one of the native candidate rows on the left.
5. Confirm or edit `Song name` in the right-side panel.
6. Click `Import MP3`.
7. Watch the spinner, flat progress bar, and percentage until the import finishes.
8. The app saves an MP3 into the shared MP3 library, stores the original YouTube URL, and refreshes the library.
9. The embedded browser is hidden by default. Use `Show Browser` or `Open Original` only when you actually want to view the YouTube page.
10. Imported songs can reopen their original video through the app/bridge `open-original` action.

Only import audio you have rights or permission to save. The importer uses `yt-dlp` and `ffmpeg`; it does not bypass DRM.

The `Import Activity` panel shows the latest browser, search, metadata, download, tagging, refresh, success, and failure stages. Use it when YouTube search/import feels slow so you can tell whether Music is working, waiting on a helper, or reporting a retryable error.

The helper calls are bounded: search has a 60-second timeout, metadata preview has a shorter timeout, the actual audio import has a longer timeout, and ffmpeg tagging has its own cap. If YouTube or the network stalls, Music should return a normal error instead of hanging.

During the download step, Music reads `yt-dlp` progress output and maps it into the import percentage. Very short videos may jump in larger steps because the helper finishes too quickly to emit many intermediate ticks.

## Jarvis / Terminal

```bash
cd "/Users/leoxu/Library/CloudStorage/OneDrive-YKPaoSchool上海民办包玉刚实验学校/developer/Music App"

./script/jarvis-music-control youtube-open "search words"
./script/jarvis-music-control youtube-search "search words"
./script/jarvis-music-control youtube-import-activity
./script/jarvis-music-control youtube-open "https://www.youtube.com/watch?v=VIDEO_ID"
./script/jarvis-music-control youtube-import "https://www.youtube.com/watch?v=VIDEO_ID" "Optional Title"
python3 script/jarvis_music_bridge.py youtube-import-watch "https://www.youtube.com/watch?v=VIDEO_ID" "Optional Title"
./script/jarvis-music-control open-original SONG_ID
./script/jarvis-music-control process-timeout-diagnostics
./script/jarvis-music-control volume 0.9
./script/cleanup_smoke_imports.sh
```

The app must be open for the local bridge commands to work.

Smoke test already verified:

```bash
./script/jarvis-music-control youtube-import \
  "https://www.youtube.com/watch?v=3OJWfgCGGl0" \
  "Codex Import Smoke Test - With Loved Ones"
```

That created `Codex Import Smoke Test - With Loved Ones.mp3` in the shared MP3 folder with embedded cover art and source URL metadata. A later progress probe created `Codex Progress Probe - With Loved Ones.mp3` and verified the live progress path. The smoke test also checks that the app can recover the original YouTube URL by rereading the MP3 metadata, not only from its app database.

`./script/smoke_bridge.sh --youtube` also uses that smoke-test song to prove native playback silently: it temporarily sets the app volume to `0`, plays the song, checks `now-playing`, stops, and restores the previous app volume.

To remove Codex-created smoke-test imports later:

```bash
./script/cleanup_smoke_imports.sh        # dry run
./script/cleanup_smoke_imports.sh --yes  # delete matching smoke/progress-test MP3s and refresh
```
