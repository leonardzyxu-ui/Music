# Music

Native macOS SwiftUI music app for Leo.

## What It Does

- Plays MP3s from the shared LocalOS music library via `SharedMP3Library`.
- Provides Apple Music-inspired library, playlist, Smart Picker, search, and now-playing UI.
- Includes YouTube audio import for content Leo is allowed to save, using `yt-dlp` plus `ffmpeg`.
- Exposes a local-only JSON control bridge for Jarvis on `127.0.0.1`.

## Build And Run

```bash
swift build
./script/build_and_run.sh --verify
```

The bundled app is created at:

```text
dist/Music.app
```

## YouTube Tools

Install/update the local `yt-dlp` helper payload:

```bash
./script/install_youtube_tools.sh
```

`ffmpeg` must also be available on the Mac, for example through Homebrew.

## Jarvis Bridge

Useful local checks:

```bash
python3 script/jarvis_music_bridge.py health
python3 script/jarvis_music_bridge.py status
python3 script/jarvis_music_bridge.py capabilities
python3 script/jarvis_music_bridge.py youtube-import-plan "https://www.youtube.com/watch?v=VIDEO_ID"
python3 script/test_bridge_contract.py
```

See `JARVIS_BRIDGE_INTEGRATION.md` for the full contract.
