#!/usr/bin/env python3
"""Integration contract checks for the live Music bridge.

Run with the Music app open:
  python3 script/test_bridge_contract.py
"""

from __future__ import annotations

import json
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from jarvis_music_bridge import MusicBridgeClient, MusicBridgeError  # noqa: E402


REQUIRED_ACTIONS = {
    "health",
    "capabilities",
    "status",
    "search",
    "playlist-songs",
    "playlist-select",
    "playlist-play",
    "playlist-create",
    "playlist-rename",
    "playlist-delete",
    "song-move-to-playlist",
    "play",
    "pause",
    "resume",
    "stop",
    "next",
    "previous",
    "now-playing",
    "playback-state",
    "volume-get",
    "volume-set",
    "seek",
    "shuffle-set",
    "repeat-set",
    "refresh-library",
    "library-sync",
    "source-metadata-diagnostics",
    "process-timeout-diagnostics",
    "youtube-helper-error-diagnostics",
    "refresh-smart-picker",
    "youtube-open",
    "youtube-search",
    "youtube-import-activity",
    "youtube-import",
    "open-original",
}


def main() -> int:
    client = MusicBridgeClient(timeout=10)
    checks = [
        ("health", lambda: assert_ok(client.health())),
        ("unauthorized-status", lambda: assert_unauthorized(client.base_url)),
        ("capabilities", lambda: assert_capabilities(client.capabilities())),
        ("status", lambda: assert_status(client.status())),
        ("library-sync", lambda: assert_library_sync(client.library_sync())),
        ("window-control-diagnostics", lambda: assert_window_controls(client.window_controls())),
        ("process-timeout-diagnostics", lambda: assert_process_timeout(client.process_timeout_diagnostics())),
        ("youtube-error-classification", lambda: assert_youtube_error_classification(client)),
        ("groups", lambda: assert_groups(client.groups())),
        ("playlist-controls", lambda: assert_playlist_controls(client)),
        ("ranked-search", lambda: assert_ranked_search(client.search("Paradise"))),
        ("client-candidates", lambda: assert_client_candidates(client.candidates("Paradise", limit=3))),
        ("multi-word-search", lambda: assert_multi_word_search(client.search("Back In Black"))),
        ("smart-picker-refresh", lambda: assert_smart_picker(client.refresh_smart_picker())),
        ("playback-controls", lambda: assert_playback_controls(client)),
        ("volume-roundtrip", lambda: assert_volume_roundtrip(client)),
        ("invalid-youtube-import", lambda: assert_invalid_youtube(client)),
        ("youtube-import-activity", lambda: assert_import_activity(client.youtube_import_activity())),
        ("idle-stop", lambda: assert_ok(client.stop())),
        ("idle-now-playing", lambda: assert_idle(client.now_playing())),
        ("idle-playback-state", lambda: assert_idle_playback(client.playback_state())),
    ]

    for label, check in checks:
        try:
            check()
        except Exception as error:
            print(f"not ok: {label}: {error}", file=sys.stderr)
            return 1
        print(f"ok: {label}")
    return 0


def assert_ok(payload: dict[str, Any]) -> None:
    if payload.get("ok") is not True:
        raise AssertionError(payload)


def assert_unauthorized(base_url: str) -> None:
    request = urllib.request.Request(f"{base_url}/status", method="GET")
    try:
        urllib.request.urlopen(request, timeout=5)
    except urllib.error.HTTPError as error:
        body = json.loads(error.read().decode("utf-8"))
        if error.code != 401:
            raise AssertionError(f"expected 401, got {error.code}: {body}")
        if body.get("ok") is not False or body.get("error", {}).get("code") != "unauthorized":
            raise AssertionError(body)
        return
    raise AssertionError("protected status endpoint unexpectedly allowed tokenless request")


def assert_capabilities(payload: dict[str, Any]) -> None:
    assert_ok(payload)
    actions = {action.get("id") for action in payload.get("actions", [])}
    missing = sorted(REQUIRED_ACTIONS - actions)
    if missing:
        raise AssertionError(f"missing actions: {missing}")
    bridge = payload.get("bridge", {})
    if bridge.get("host") != "127.0.0.1" or bridge.get("requiresToken") is not True:
        raise AssertionError(f"unexpected bridge metadata: {bridge}")


def assert_status(payload: dict[str, Any]) -> None:
    assert_ok(payload)
    for key in ["app", "libraryPath", "songCount", "playing", "volume", "queue", "smartPicker", "youtubeTools", "youtubeImport", "bridge"]:
        if key not in payload:
            raise AssertionError(f"missing status key {key}: {payload}")
    if payload["app"] != "Music":
        raise AssertionError(f"unexpected app name: {payload['app']}")
    if int(payload["songCount"]) <= 0:
        raise AssertionError(f"songCount should be positive: {payload['songCount']}")
    if "librarySync" not in payload:
        raise AssertionError(f"status missing librarySync: {payload}")


def assert_library_sync(payload: dict[str, Any]) -> None:
    assert_ok(payload)
    if payload.get("autoRefreshActive") is not True:
        raise AssertionError(f"auto refresh should be active: {payload}")
    if int(payload.get("autoRefreshIntervalSeconds", 0)) <= 0:
        raise AssertionError(f"invalid auto refresh interval: {payload}")
    if int(payload.get("songCount", 0)) <= 0:
        raise AssertionError(f"songCount should be positive: {payload}")
    delta = payload.get("lastScanDelta")
    if not isinstance(delta, dict):
        raise AssertionError(f"missing scan delta: {payload}")


def assert_window_controls(payload: dict[str, Any]) -> None:
    assert_ok(payload)
    if int(payload.get("visibleWindowCount", 0)) <= 0:
        raise AssertionError(f"expected at least one visible Music window: {payload}")
    if "standardWindowButton" not in str(payload.get("mode", "")):
        raise AssertionError(f"unexpected window control mode: {payload}")
    native_buttons = payload.get("nativeButtons")
    if not isinstance(native_buttons, list) or len(native_buttons) < 3:
        raise AssertionError(f"native button diagnostics missing: {payload}")
    for button in native_buttons:
        if button.get("exists") is not True or button.get("visible") is not True or button.get("enabled") is not True:
            raise AssertionError(f"native button is not usable: {payload}")
    shape = payload.get("windowShape")
    if not isinstance(shape, dict) or shape.get("available") is not True:
        raise AssertionError(f"window shape diagnostics missing: {payload}")
    expected_radius = float(shape.get("expectedOuterCornerRadius", 0))
    if shape.get("outerCornerMode") != "customModerateRoundedShell":
        raise AssertionError(f"outer window corner must use the moderate custom rounded shell: {payload}")
    if expected_radius < 32 or expected_radius > 38:
        raise AssertionError(f"outer corner radius should be moderate, not tiny or oversized: {payload}")
    for key in ["frameCornerRadius", "contentCornerRadius"]:
        if abs(float(shape.get(key, 0)) - expected_radius) > 0.5:
            raise AssertionError(f"{key} does not match expected rounded window radius: {payload}")
    if shape.get("frameMasksToBounds") is not True or shape.get("contentMasksToBounds") is not True:
        raise AssertionError(f"custom frame/content masks must be enabled: {payload}")
    if shape.get("isOpaque") is not False or shape.get("backgroundIsClear") is not True:
        raise AssertionError(f"window must be clear/non-opaque outside the rounded app shell: {payload}")
    expected_x = float(shape.get("expectedTrafficLightX", -1))
    expected_y = float(shape.get("expectedTrafficLightY", -1))
    if expected_x < 18 or expected_x > 24 or expected_y < 4:
        raise AssertionError(f"traffic lights are not anchored inside the filled sidebar surface: {payload}")
    if not isinstance(payload.get("events"), list):
        raise AssertionError(f"window control events should be a list: {payload}")


def assert_process_timeout(payload: dict[str, Any]) -> None:
    assert_ok(payload)
    for key in ["passed", "processStopped", "timedOut", "cleanupSucceeded", "sharedLibraryUnchanged", "usedSharedLibrary"]:
        if key not in payload:
            raise AssertionError(f"process timeout payload missing {key}: {payload}")
    if payload.get("passed") is not True:
        raise AssertionError(f"process timeout diagnostic failed: {payload}")
    if payload.get("usedSharedLibrary") is not False:
        raise AssertionError(f"diagnostic should not use shared library: {payload}")


def assert_youtube_error_classification(client: MusicBridgeClient) -> None:
    cases = [
        (
            "ERROR: [youtube] abc: Private video. Sign in if you've been granted access.",
            False,
            "youtube_access_restricted",
            False,
        ),
        (
            "ERROR: [youtube] abc: Video unavailable. This video has been removed.",
            False,
            "youtube_video_unavailable",
            False,
        ),
        (
            "ERROR: This content uses DRM or protected content.",
            False,
            "youtube_protected_content",
            False,
        ),
        (
            "yt-dlp is still waiting on the network",
            True,
            "youtube_helper_timeout",
            True,
        ),
    ]
    for message, timed_out, expected_code, expected_retryable in cases:
        payload = client.youtube_error_classification(message, timed_out=timed_out)
        assert_ok(payload)
        if payload.get("code") != expected_code:
            raise AssertionError(f"expected {expected_code}, got {payload}")
        if payload.get("retryable") is not expected_retryable:
            raise AssertionError(f"unexpected retryable flag for {expected_code}: {payload}")
        if not payload.get("recoverySuggestion"):
            raise AssertionError(f"missing recovery suggestion for {expected_code}: {payload}")


def assert_groups(payload: dict[str, Any]) -> None:
    assert_ok(payload)
    names = {group.get("name") for group in payload.get("playlists", [])}
    if {"All Songs", "Your Pick"} - names:
        raise AssertionError(f"missing core groups: {names}")


def assert_playlist_controls(client: MusicBridgeClient) -> None:
    temp = "Codex Bridge Contract Temp"
    renamed = "Codex Bridge Contract Temp Renamed"
    for name in [temp, renamed]:
        try:
            client.playlist_delete(name)
        except Exception:
            pass

    try:
        created = client.playlist_create(temp)
        assert_ok(created)
        if created.get("playlist", {}).get("name") != temp:
            raise AssertionError(f"playlist create returned wrong payload: {created}")

        selected = client.playlist_select(temp)
        assert_ok(selected)
        if selected.get("playlist", {}).get("songCount") != 0:
            raise AssertionError(f"temporary playlist should be empty: {selected}")

        smart_songs = client.playlist_songs("Your Pick")
        assert_ok(smart_songs)
        if smart_songs.get("playlist", {}).get("name") != "Your Pick":
            raise AssertionError(f"Your Pick lookup failed: {smart_songs}")
        if not isinstance(smart_songs.get("songs"), list):
            raise AssertionError(f"playlist songs missing list: {smart_songs}")

        renamed_payload = client.playlist_rename(temp, renamed)
        assert_ok(renamed_payload)
        if renamed_payload.get("playlist", {}).get("name") != renamed:
            raise AssertionError(f"playlist rename failed: {renamed_payload}")

        missing_move = client.song_move("missing-song-id", renamed)
        if missing_move.get("ok") is not False or missing_move.get("error", {}).get("code") != "song_not_found":
            raise AssertionError(f"missing song move should fail cleanly: {missing_move}")
    finally:
        for name in [temp, renamed]:
            try:
                client.playlist_delete(name)
            except Exception:
                pass
        assert_ok(client.playlist_select("All Songs"))


def assert_ranked_search(payload: dict[str, Any]) -> None:
    assert_ok(payload)
    candidates = payload.get("candidates") or []
    if not candidates:
        raise AssertionError("expected ranked candidates")
    first = candidates[0]
    if "score" not in first or not first.get("matchedFields"):
        raise AssertionError(f"candidate missing ranking details: {first}")
    song = first.get("song") or {}
    for key in ["id", "title", "artist", "durationText", "stats"]:
        if key not in song:
            raise AssertionError(f"candidate song missing {key}: {song}")


def assert_client_candidates(candidates: list[dict[str, Any]]) -> None:
    if not candidates:
        raise AssertionError("expected client candidates")
    if len(candidates) > 3:
        raise AssertionError(f"client did not honor limit: {len(candidates)}")


def assert_multi_word_search(payload: dict[str, Any]) -> None:
    assert_ok(payload)
    titles = [song.get("title", "") for song in payload.get("songs", [])]
    if not any("Back In Black" in title for title in titles):
        raise AssertionError(f"multi-word search did not find expected song: {titles[:5]}")


def assert_smart_picker(payload: dict[str, Any]) -> None:
    assert_ok(payload)
    songs = payload.get("songs")
    if not isinstance(songs, list):
        raise AssertionError(f"smart picker payload missing songs list: {payload}")


def assert_playback_controls(client: MusicBridgeClient) -> None:
    original = client.playback_state()
    assert_ok(original)
    original_shuffle = bool(original.get("shuffle", False))
    original_repeat = str(original.get("repeatMode", 0))
    try:
        shuffle_payload = client.shuffle(not original_shuffle)
        assert_ok(shuffle_payload)
        if bool(shuffle_payload.get("shuffle")) == original_shuffle:
            raise AssertionError(f"shuffle did not change: {shuffle_payload}")

        repeat_payload = client.repeat("one")
        assert_ok(repeat_payload)
        if int(repeat_payload.get("repeatMode", -1)) != 2:
            raise AssertionError(f"repeat one failed: {repeat_payload}")

        seek_payload = client.seek(0)
        assert_ok(seek_payload)
        playback = seek_payload.get("playback") or {}
        for key in ["currentTime", "duration", "shuffle", "repeatMode", "queue"]:
            if key not in playback:
                raise AssertionError(f"seek playback payload missing {key}: {seek_payload}")
    finally:
        client.shuffle(original_shuffle)
        client.repeat(original_repeat)


def assert_volume_roundtrip(client: MusicBridgeClient) -> None:
    original = float(client.volume().get("volume", 0.9))
    try:
        muted = client.volume(0)
        assert_ok(muted)
        if float(muted.get("volume", -1)) != 0:
            raise AssertionError(f"volume did not mute: {muted}")
    finally:
        restored = client.volume(original)
        assert_ok(restored)
        restored_value = float(restored.get("volume", -1))
        if abs(restored_value - original) > 0.001:
            raise AssertionError(f"volume did not restore: {restored_value} vs {original}")


def assert_invalid_youtube(client: MusicBridgeClient) -> None:
    before = int(client.status().get("songCount", -1))
    payload = client.youtube_import("https://www.youtube.com/results?search_query=test", "Should Not Import")
    if payload.get("ok") is not False:
        raise AssertionError(f"invalid YouTube import unexpectedly succeeded: {payload}")
    error = payload.get("error", {})
    if error.get("code") != "not_youtube_video_url":
        raise AssertionError(f"invalid import should return typed URL error: {payload}")
    if error.get("retryable") is not False:
        raise AssertionError(f"invalid import should be non-retryable: {payload}")
    if not error.get("recoverySuggestion"):
        raise AssertionError(f"invalid import missing recovery suggestion: {payload}")
    message = error.get("message", "")
    if "specific YouTube video" not in message:
        raise AssertionError(f"unexpected invalid import error: {payload}")
    after = int(client.status().get("songCount", -2))
    if before != after:
        raise AssertionError(f"invalid import changed song count: {before} -> {after}")


def assert_import_activity(payload: dict[str, Any]) -> None:
    assert_ok(payload)
    for key in ["isImporting", "status", "currentURL", "lastFailureCode", "activity"]:
        if key not in payload:
            raise AssertionError(f"import activity missing {key}: {payload}")
    if not isinstance(payload.get("activity"), list):
        raise AssertionError(f"activity should be a list: {payload}")
    if payload["activity"]:
        entry = payload["activity"][0]
        for key in ["createdAt", "state", "title", "detail"]:
            if key not in entry:
                raise AssertionError(f"activity entry missing {key}: {entry}")


def assert_idle(payload: dict[str, Any]) -> None:
    assert_ok(payload)
    if payload.get("playing") is not False:
        raise AssertionError(f"expected stopped playback: {payload}")


def assert_idle_playback(payload: dict[str, Any]) -> None:
    assert_ok(payload)
    if payload.get("playing") is not False or payload.get("nowPlaying") is not None:
        raise AssertionError(f"expected idle playback state: {payload}")
    queue = payload.get("queue") or {}
    if queue.get("source") != "Idle" or queue.get("songIds") != [] or int(queue.get("count", -1)) != 0:
        raise AssertionError(f"expected idle queue after stop: {payload}")


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except MusicBridgeError as error:
        print(f"not ok: bridge setup: {error}", file=sys.stderr)
        raise SystemExit(1)
