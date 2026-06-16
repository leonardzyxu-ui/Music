# Music Bridge Integration For Jarvis

App: `Music`

Local bridge base URL: `http://127.0.0.1:47879`

Token file: `~/Library/Application Support/Music/control-token.txt`

The bridge is bound to `127.0.0.1` and protected endpoints require the local
token. Query parameters use normal form decoding, so multi-word values from
Jarvis or the CLI arrive with spaces intact.

The provided Python and shell helpers bypass `http_proxy`/`https_proxy` for
`127.0.0.1` and `localhost`, so Leo can leave a local proxy enabled while
Jarvis still talks directly to Music.

Jarvis should read the token locally and send it as:

```http
Authorization: Bearer <token>
```

Health does not require the token:

```bash
curl http://127.0.0.1:47879/health
```

Jarvis can introspect the full typed control surface before choosing actions:

```bash
./script/jarvis-music-control capabilities
```

Importable Python client for Jarvis-side code:

```python
from pathlib import Path
import sys

sys.path.append("/Users/leoxu/Library/CloudStorage/OneDrive-YKPaoSchool上海民办包玉刚实验学校/developer/Music App/script")

from jarvis_music_bridge import MusicBridgeClient

music = MusicBridgeClient()
print(music.health())
print(music.candidates("Paradise", limit=3))
music.play(query="Paradise")
```

The Python client returns the same JSON dictionaries as the HTTP bridge and
raises `MusicBridgeError` only for local transport/setup problems such as the
app not being open or the token file missing.

For YouTube imports, the Python client also has
`youtube_import_with_progress(url, title=None, on_progress=callback)`. It starts
the import on one bridge request while polling `/youtube/import-activity` on
another, so Jarvis can show progress without freezing its own conversation.

Useful endpoints. Value-carrying `POST` endpoints accept either JSON bodies or
query parameters, which makes them easy for Jarvis to call from Python, Swift,
or a shell helper:

- `GET /capabilities`
- `GET /status`
- `GET /songs`
- `GET /search?q=<query>`
- `GET /groups`
- `GET /playlist/songs?name=<playlist-name>` or `GET /playlist/songs?id=<playlist-id>`
- `GET /now-playing`
- `GET /playback-state`
- `GET /volume`
- `GET /diagnostics/library-sync`
- `GET /diagnostics/window-controls`
- `GET /diagnostics/source-metadata?id=<song-id>`
- `GET /diagnostics/youtube-import-plan?url=<youtube-url>`
- `POST /diagnostics/process-timeout`
- `POST /play?id=<song-id>` or `POST /play?query=<song title>`
- `POST /play-by-id?id=<song-id>`
- `POST /play-by-query?query=<song title>`
- `POST /playlist/select?name=<playlist-name>` or `POST /playlist/select?id=<playlist-id>`
- `POST /playlist/play?name=<playlist-name>` or `POST /playlist/play?id=<playlist-id>`
- `POST /playlist/create?name=<playlist-name>`
- `POST /playlist/rename?oldName=<old-name>&newName=<new-name>`
- `POST /playlist/delete?name=<playlist-name>`
- `POST /song/move?id=<song-id>&group=<playlist-name>`
- `POST /pause`
- `POST /resume`
- `POST /stop`
- `POST /volume?level=<0.0-1.0>`
- `POST /seek?seconds=<position>`
- `POST /shuffle?enabled=true|false`
- `POST /repeat?mode=off|all|one`
- `POST /next`
- `POST /previous`
- `POST /refresh-library`
- `POST /refresh-smart-picker`
- `POST /youtube/open?url=<youtube-url>` or `POST /youtube/open?search=<query>`
- `GET /youtube/search?q=<query>`
- `GET /youtube/import-activity`
- `POST /youtube/import?url=<youtube-url>&title=<optional title>`
- `POST /song/open-original?id=<song-id>`

Recommended Jarvis flow:

1. Call `/health`; if unavailable, ask Leo to open `Music`.
2. Call `/capabilities` when Jarvis wants the current typed action list instead of relying on hard-coded docs.
3. Call `/search?q=...` or `/songs` to get candidate IDs and titles.
4. Choose naturally from returned candidates.
5. Call `/play` with the selected `id`.
6. Use `/now-playing` to confirm playback state.

Recommended playlist flow:

1. Call `/groups` to get playlist IDs, names, and counts.
2. Call `/playlist/songs?name=...` when Jarvis needs candidates inside one playlist.
3. Call `/playlist/play?name=...` to play a snapshot of `All Songs`, `Your Pick`, or a custom playlist.
4. Use `/playlist/create`, `/playlist/rename`, `/playlist/delete`, and `/song/move` only when Leo explicitly asks to manage playlists.

Recommended YouTube import flow:

1. Call `/youtube/search?q=...` to get structured candidates.
2. Ask Leo or Jarvis policy to choose only content Leo is allowed to save.
3. Call `/diagnostics/youtube-import-plan?url=...` before a real import. A safe plan reports `audioOnly: true`, `videoCodec: "none"`, and `sharedLibraryUnchanged: true`.
4. Call `/youtube/import?url=...&title=...`.
5. Poll `/youtube/import-activity` while the import is running. The payload includes `progress`, `progressPercent`, `status`, and recent metadata/download/tagging/refresh/success/failure activity.
6. Call `/search?q=<title>` to confirm the imported song and stored source URL.
7. Call `/song/open-original?id=...` when Leo asks to view the original video.

Recommended Python flow when Jarvis wants a single helper call:

```python
def show_music_progress(snapshot):
    print(snapshot["progressPercent"], snapshot["status"])

payload = music.youtube_import_with_progress(
    "https://www.youtube.com/watch?v=VIDEO_ID",
    title="Optional Title",
    on_progress=show_music_progress,
)
```

YouTube helper subprocesses are bounded inside Music. Jarvis should treat timeout
messages as retryable user-facing failures, not as a bridge crash.
Invalid import attempts use typed codes such as `not_youtube_video_url`,
`invalid_youtube_url`, `youtube_helper_missing`, `youtube_helper_timeout`,
`youtube_helper_failed`, and `youtube_import_no_output`.

The bridge returns JSON only. Errors use:

```json
{
  "ok": false,
  "error": {
    "code": "song_not_found",
    "message": "Friendly message here."
  }
}
```

CLI helper:

```bash
./script/jarvis-music-control status
./script/jarvis-music-control capabilities
./script/jarvis-music-control library-sync
./script/jarvis-music-control window-controls
./script/jarvis-music-control source-metadata SONG_ID
./script/jarvis-music-control process-timeout-diagnostics
./script/jarvis-music-control playlist-songs "Your Pick"
./script/jarvis-music-control playlist-select "All Songs"
./script/jarvis-music-control search Paradise
./script/jarvis-music-control play Paradise
./script/jarvis-music-control stop
./script/jarvis-music-control playback-state
./script/jarvis-music-control seek 0
./script/jarvis-music-control shuffle false
./script/jarvis-music-control repeat off
./script/jarvis-music-control volume 0.9
./script/jarvis-music-control youtube-search "lofi study music"
./script/jarvis-music-control youtube-import-plan "https://www.youtube.com/watch?v=VIDEO_ID"
./script/jarvis-music-control youtube-import-activity
python3 script/jarvis_music_bridge.py youtube-import-watch "https://www.youtube.com/watch?v=VIDEO_ID" "Optional Title"
```

Python helper:

```bash
python3 script/jarvis_music_bridge.py status
python3 script/jarvis_music_bridge.py library-sync
python3 script/jarvis_music_bridge.py window-controls
python3 script/jarvis_music_bridge.py source-metadata SONG_ID
python3 script/jarvis_music_bridge.py process-timeout-diagnostics
python3 script/jarvis_music_bridge.py playlist-songs "Your Pick"
python3 script/jarvis_music_bridge.py playlist-select "All Songs"
python3 script/jarvis_music_bridge.py candidates Paradise --limit 3
python3 script/jarvis_music_bridge.py play Paradise
python3 script/jarvis_music_bridge.py stop
python3 script/jarvis_music_bridge.py playback-state
python3 script/jarvis_music_bridge.py seek 0
python3 script/jarvis_music_bridge.py shuffle false
python3 script/jarvis_music_bridge.py repeat off
python3 script/jarvis_music_bridge.py youtube-search "lofi study music"
python3 script/jarvis_music_bridge.py youtube-import-plan "https://www.youtube.com/watch?v=VIDEO_ID"
python3 script/jarvis_music_bridge.py youtube-import-activity
python3 script/jarvis_music_bridge.py youtube-import-watch "https://www.youtube.com/watch?v=VIDEO_ID" "Optional Title"
```

Bridge self-test:

```bash
python3 script/test_bridge_contract.py
./script/smoke_bridge.sh
./script/smoke_bridge.sh --youtube
```

`test_bridge_contract.py` verifies the live app contract: health, auth failure,
capabilities, status shape, library auto-sync diagnostics, window-control
diagnostics, process timeout diagnostics, groups, playlist create/select/read/rename/delete controls, ranked
candidates, playback state/seek/shuffle/repeat controls, multi-word search,
Smart Picker refresh, volume restore, invalid import rejection, YouTube import activity/progress shape, idle
now-playing, and idle playback-state.
`--youtube` also verifies process timeout cleanup, invalid import rejection
without changing song count, YouTube search, and, when the Codex smoke-test
import exists, source URL recovery from MP3 metadata, `/song/open-original`, a
silent app-volume playback start, `/now-playing`, stop, and volume restore.

Smoke-test cleanup:

```bash
./script/cleanup_smoke_imports.sh
./script/cleanup_smoke_imports.sh --yes
```
