#!/usr/bin/env bash
set -euo pipefail

BASE="${JARVIS_MUSIC_URL:-http://127.0.0.1:47879}"
TOKEN_FILE="${JARVIS_MUSIC_TOKEN_FILE:-$HOME/Library/Application Support/Music/control-token.txt}"

require_ok() {
  local label="$1"
  python3 -c '
import json
import sys

label = sys.argv[1]
payload = json.load(sys.stdin)
if payload.get("ok") is not True:
    raise SystemExit(f"{label} failed: {payload}")
print(f"ok: {label}")
' "$label"
}

authed_get() {
  local path="$1"
  local token
  token="$(cat "$TOKEN_FILE")"
  curl -fsS -H "Authorization: Bearer $token" "$BASE$path"
}

authed_post() {
  local path="$1"
  local token
  token="$(cat "$TOKEN_FILE")"
  curl -fsS -X POST -H "Authorization: Bearer $token" "$BASE$path"
}

curl -fsS "$BASE/health" | require_ok "health"

unauthorized_status="$(
  curl -sS -o /tmp/music-bridge-unauthorized.json -w "%{http_code}" "$BASE/status"
)"
if [[ "$unauthorized_status" != "401" ]]; then
  echo "auth failure check failed: expected 401, got $unauthorized_status" >&2
  cat /tmp/music-bridge-unauthorized.json >&2
  exit 1
fi
echo "ok: protected endpoints require token"

authed_get "/status" | require_ok "status"
authed_get "/capabilities" | python3 -c '
import json
import sys

payload = json.load(sys.stdin)
if payload.get("ok") is not True:
    raise SystemExit(f"capabilities failed: {payload}")
actions = {action.get("id") for action in payload.get("actions", [])}
required = {
    "search",
    "play",
    "playlist-songs",
    "playlist-select",
    "playlist-play",
    "playlist-create",
    "playlist-rename",
    "playlist-delete",
    "song-move-to-playlist",
    "youtube-search",
    "youtube-import-activity",
    "youtube-import",
    "open-original",
    "volume-set",
    "playback-state",
    "seek",
    "shuffle-set",
    "repeat-set",
    "library-sync",
    "source-metadata-diagnostics",
    "process-timeout-diagnostics",
    "youtube-helper-error-diagnostics",
    "refresh-smart-picker",
}
missing = sorted(required - actions)
if missing:
    raise SystemExit(f"capabilities missing actions: {missing}")
print("ok: capabilities")
'
authed_get "/groups" | require_ok "groups"
authed_get "/search?q=Paradise" | require_ok "search"
authed_post "/diagnostics/process-timeout" | python3 -c '
import json
import sys

payload = json.load(sys.stdin)
if payload.get("ok") is not True or payload.get("passed") is not True:
    raise SystemExit(f"process timeout diagnostic failed: {payload}")
if payload.get("usedSharedLibrary") is not False or payload.get("sharedLibraryUnchanged") is not True:
    raise SystemExit(f"process timeout diagnostic touched library: {payload}")
print("ok: process-timeout-diagnostics")
'
token="$(cat "$TOKEN_FILE")"
curl -sS -G -X POST -H "Authorization: Bearer $token" \
  --data-urlencode "message=ERROR: [youtube] abc: Private video. Sign in if you've been granted access." \
  "$BASE/diagnostics/youtube-helper-error" | python3 -c '
import json
import sys

payload = json.load(sys.stdin)
if payload.get("ok") is not True:
    raise SystemExit(f"youtube helper diagnostic failed: {payload}")
if payload.get("code") != "youtube_access_restricted" or payload.get("retryable") is not False:
    raise SystemExit(f"youtube helper diagnostic classified wrongly: {payload}")
if not payload.get("recoverySuggestion"):
    raise SystemExit(f"youtube helper diagnostic missing recovery: {payload}")
print("ok: youtube-helper-error-diagnostics")
'
python3 script/jarvis_music_bridge.py health | require_ok "python-client-health"
python3 script/jarvis_music_bridge.py capabilities | require_ok "python-client-capabilities"
python3 script/jarvis_music_bridge.py youtube-error-classification "ERROR: Video unavailable. This video has been removed." | python3 -c '
import json
import sys

payload = json.load(sys.stdin)
if payload.get("ok") is not True or payload.get("code") != "youtube_video_unavailable":
    raise SystemExit(f"python client youtube classification failed: {payload}")
print("ok: python-client-youtube-error-classification")
'
python3 script/jarvis_music_bridge.py candidates Paradise --limit 3 | python3 -c '
import json
import sys

payload = json.load(sys.stdin)
if payload.get("ok") is not True:
    raise SystemExit(f"python client candidates failed: {payload}")
if not payload.get("candidates"):
    raise SystemExit(f"python client candidates returned no matches: {payload}")
print("ok: python-client-candidates")
'
python3 script/test_bridge_contract.py | sed 's/^/contract: /'
authed_post "/refresh-smart-picker" | require_ok "refresh-smart-picker"
authed_get "/youtube/import-activity" | require_ok "youtube-import-activity"
song_count_before_invalid="$(
  authed_get "/status" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("songCount", -1))'
)"
curl -sS -X POST -H "Authorization: Bearer $token" \
  "$BASE/youtube/import?url=https%3A%2F%2Fwww.youtube.com%2Fresults%3Fsearch_query%3Dtest&title=Should%20Not%20Import" \
  | python3 -c '
import json
import sys

payload = json.load(sys.stdin)
if payload.get("ok") is not False:
    raise SystemExit(f"invalid YouTube import should fail, got: {payload}")
error = payload.get("error", {})
if error.get("code") != "not_youtube_video_url":
    raise SystemExit(f"invalid YouTube import should return typed error, got: {payload}")
message = error.get("message", "")
if "specific YouTube video" not in message:
    raise SystemExit(f"unexpected invalid import message: {payload}")
print("ok: invalid YouTube import rejected")
'
song_count_after_invalid="$(
  authed_get "/status" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("songCount", -2))'
)"
if [[ "$song_count_before_invalid" != "$song_count_after_invalid" ]]; then
  echo "invalid YouTube import changed song count: $song_count_before_invalid -> $song_count_after_invalid" >&2
  exit 1
fi
echo "ok: invalid YouTube import left library unchanged"

if [[ "${1:-}" == "--youtube" ]]; then
  authed_get "/youtube/search?q=royalty%20free%20audio%20test%205%20seconds" | require_ok "youtube-search"
  smoke_song_id="$(
    authed_get "/search?q=Codex%20Import%20Smoke%20Test" | python3 -c '
import json
import sys

payload = json.load(sys.stdin)
for song in payload.get("songs", []):
    if str(song.get("title", "")).startswith("Codex Import Smoke Test") and song.get("sourceURL"):
        print(song["id"])
        break
'
  )"
  if [[ -n "$smoke_song_id" ]]; then
    python3 script/jarvis_music_bridge.py source-metadata "$smoke_song_id" | python3 -c '
import json
import sys

payload = json.load(sys.stdin)
if payload.get("ok") is not True or payload.get("metadataHasSourceURL") is not True:
    raise SystemExit(f"source metadata recovery failed: {payload}")
print("ok: source-metadata")
'
    authed_post "/song/open-original?id=$smoke_song_id" | require_ok "open-original"
    original_volume="$(
      authed_get "/volume" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("volume", 0.9))'
    )"
    restore_volume() {
      authed_post "/volume?level=$original_volume" >/dev/null 2>&1 || true
    }
    trap restore_volume EXIT

    authed_post "/volume?level=0" | require_ok "mute-app-volume"
    authed_post "/play?id=$smoke_song_id" | require_ok "silent-play"
    sleep 0.7
    authed_get "/now-playing" | python3 -c '
import json
import sys

expected = sys.argv[1]
payload = json.load(sys.stdin)
song = payload.get("nowPlaying") or {}
if payload.get("playing") is not True or song.get("id") != expected:
    raise SystemExit(f"silent playback assertion failed: {payload}")
print("ok: silent-now-playing")
' "$smoke_song_id"
    authed_post "/stop" | require_ok "stop-after-silent-play"
    authed_post "/volume?level=$original_volume" | require_ok "restore-volume"
    trap - EXIT
  else
    echo "skip: open-original (no Codex smoke-test import with source URL)"
    echo "skip: silent playback (no Codex smoke-test import with source URL)"
  fi
fi
