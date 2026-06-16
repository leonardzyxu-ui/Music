#!/usr/bin/env python3
"""Small importable client for the local Music bridge.

Jarvis can import MusicBridgeClient from this file instead of shelling out or
hand-rolling endpoint details. The Music app must be open for protected actions.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import threading
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, Callable


DEFAULT_BASE_URL = "http://127.0.0.1:47879"
DEFAULT_TOKEN_FILE = "~/Library/Application Support/Music/control-token.txt"


def _install_local_proxy_bypass() -> None:
    existing = os.environ.get("no_proxy") or os.environ.get("NO_PROXY") or ""
    entries = [item.strip() for item in existing.split(",") if item.strip()]
    required = ["127.0.0.1", "localhost", "::1"]
    merged = entries + [item for item in required if item not in entries]
    value = ",".join(merged)
    os.environ["no_proxy"] = value
    os.environ["NO_PROXY"] = value


_install_local_proxy_bypass()


class MusicBridgeError(RuntimeError):
    def __init__(self, message: str, *, status: int | None = None, code: str = "bridge_error") -> None:
        super().__init__(message)
        self.status = status
        self.code = code

    def as_payload(self) -> dict[str, Any]:
        return {
            "ok": False,
            "error": {
                "code": self.code,
                "message": str(self),
                "status": self.status,
            },
        }


class MusicBridgeClient:
    def __init__(
        self,
        base_url: str | None = None,
        token_file: str | os.PathLike[str] | None = None,
        timeout: float = 360.0,
    ) -> None:
        self.base_url = (base_url or os.environ.get("JARVIS_MUSIC_URL") or DEFAULT_BASE_URL).rstrip("/")
        token_path = token_file or os.environ.get("JARVIS_MUSIC_TOKEN_FILE") or DEFAULT_TOKEN_FILE
        self.token_file = Path(token_path).expanduser()
        self.timeout = timeout

    def health(self) -> dict[str, Any]:
        return self._request("GET", "/health", auth=False)

    def capabilities(self) -> dict[str, Any]:
        return self._request("GET", "/capabilities")

    def status(self) -> dict[str, Any]:
        return self._request("GET", "/status")

    def songs(self, query: str | None = None) -> dict[str, Any]:
        return self._request("GET", "/songs", query={"q": query} if query else None)

    def search(self, query: str) -> dict[str, Any]:
        return self._request("GET", "/search", query={"q": query})

    def groups(self) -> dict[str, Any]:
        return self._request("GET", "/groups")

    def playlist_songs(self, name: str | None = None, playlist_id: str | None = None) -> dict[str, Any]:
        return self._request("GET", "/playlist/songs", query=self._playlist_query(name, playlist_id))

    def playlist_select(self, name: str | None = None, playlist_id: str | None = None) -> dict[str, Any]:
        return self._request("POST", "/playlist/select", query=self._playlist_query(name, playlist_id))

    def playlist_play(self, name: str | None = None, playlist_id: str | None = None) -> dict[str, Any]:
        return self._request("POST", "/playlist/play", query=self._playlist_query(name, playlist_id))

    def playlist_create(self, name: str) -> dict[str, Any]:
        return self._request("POST", "/playlist/create", query={"name": name})

    def playlist_rename(self, old_name: str, new_name: str) -> dict[str, Any]:
        return self._request("POST", "/playlist/rename", query={"oldName": old_name, "newName": new_name})

    def playlist_delete(self, name: str | None = None, playlist_id: str | None = None) -> dict[str, Any]:
        return self._request("POST", "/playlist/delete", query=self._playlist_query(name, playlist_id))

    def song_move(self, song_id: str, playlist: str) -> dict[str, Any]:
        return self._request("POST", "/song/move", query={"id": song_id, "group": playlist})

    def now_playing(self) -> dict[str, Any]:
        return self._request("GET", "/now-playing")

    def playback_state(self) -> dict[str, Any]:
        return self._request("GET", "/playback-state")

    def volume(self, level: float | None = None) -> dict[str, Any]:
        if level is None:
            return self._request("GET", "/volume")
        return self._request("POST", "/volume", query={"level": str(level)})

    def seek(self, seconds: float) -> dict[str, Any]:
        return self._request("POST", "/seek", query={"seconds": str(seconds)})

    def shuffle(self, enabled: bool) -> dict[str, Any]:
        return self._request("POST", "/shuffle", query={"enabled": "true" if enabled else "false"})

    def repeat(self, mode: str | int) -> dict[str, Any]:
        return self._request("POST", "/repeat", query={"mode": str(mode)})

    def window_controls(self) -> dict[str, Any]:
        return self._request("GET", "/diagnostics/window-controls")

    def window_control_action(self, action: str) -> dict[str, Any]:
        return self._request("POST", "/diagnostics/window-control-action", query={"action": action})

    def process_timeout_diagnostics(self) -> dict[str, Any]:
        return self._request("POST", "/diagnostics/process-timeout")

    def youtube_error_classification(self, message: str, timed_out: bool = False) -> dict[str, Any]:
        return self._request(
            "POST",
            "/diagnostics/youtube-helper-error",
            query={"message": message, "timedOut": "true" if timed_out else "false"},
        )

    def play(self, query: str | None = None, song_id: str | None = None) -> dict[str, Any]:
        if song_id:
            return self._request("POST", "/play", query={"id": song_id})
        if query:
            return self._request("POST", "/play", query={"query": query})
        raise MusicBridgeError("Provide either query or song_id to play.", code="missing_play_target")

    def pause(self) -> dict[str, Any]:
        return self._request("POST", "/pause")

    def resume(self) -> dict[str, Any]:
        return self._request("POST", "/resume")

    def stop(self) -> dict[str, Any]:
        return self._request("POST", "/stop")

    def next(self) -> dict[str, Any]:
        return self._request("POST", "/next")

    def previous(self) -> dict[str, Any]:
        return self._request("POST", "/previous")

    def refresh_library(self) -> dict[str, Any]:
        return self._request("POST", "/refresh-library")

    def library_sync(self) -> dict[str, Any]:
        return self._request("GET", "/diagnostics/library-sync")

    def source_metadata(self, song_id: str) -> dict[str, Any]:
        return self._request("GET", "/diagnostics/source-metadata", query={"id": song_id})

    def refresh_smart_picker(self) -> dict[str, Any]:
        return self._request("POST", "/refresh-smart-picker")

    def youtube_open(self, value: str | None = None) -> dict[str, Any]:
        value = value or "https://www.youtube.com"
        key = "url" if value.startswith(("http://", "https://")) else "search"
        return self._request("POST", "/youtube/open", query={key: value})

    def youtube_search(self, query: str, limit: int | None = None) -> dict[str, Any]:
        params: dict[str, str] = {"q": query}
        if limit is not None:
            params["limit"] = str(limit)
        return self._request("GET", "/youtube/search", query=params)

    def youtube_import_activity(self) -> dict[str, Any]:
        return self._request("GET", "/youtube/import-activity")

    def youtube_import(self, url: str, title: str | None = None) -> dict[str, Any]:
        params = {"url": url}
        if title:
            params["title"] = title
        return self._request("POST", "/youtube/import", query=params)

    def youtube_import_with_progress(
        self,
        url: str,
        title: str | None = None,
        *,
        poll_interval: float = 1.0,
        on_progress: Callable[[dict[str, Any]], None] | None = None,
    ) -> dict[str, Any]:
        result: dict[str, Any] = {}
        error: dict[str, BaseException] = {}
        snapshots: list[dict[str, Any]] = []

        def run_import() -> None:
            try:
                result["payload"] = self.youtube_import(url, title)
            except BaseException as exc:  # propagate after progress polling finishes
                error["exception"] = exc

        worker = threading.Thread(target=run_import, name="music-youtube-import", daemon=True)
        worker.start()
        safe_interval = max(0.25, poll_interval)

        while worker.is_alive():
            snapshot = self.youtube_import_activity()
            snapshots.append(snapshot)
            if on_progress:
                on_progress(snapshot)
            worker.join(timeout=safe_interval)

        if "exception" in error:
            raise error["exception"]

        final_activity = self.youtube_import_activity()
        snapshots.append(final_activity)
        if on_progress:
            on_progress(final_activity)
        return {
            "ok": result.get("payload", {}).get("ok", False),
            "import": result.get("payload", {}),
            "activity": final_activity,
            "progressSnapshots": snapshots[-120:],
        }

    def open_original(self, song_id: str) -> dict[str, Any]:
        return self._request("POST", "/song/open-original", query={"id": song_id})

    def candidates(self, query: str, limit: int = 5) -> list[dict[str, Any]]:
        payload = self.search(query)
        candidates = payload.get("candidates") or []
        return candidates[:limit]

    def _request(
        self,
        method: str,
        path: str,
        *,
        query: dict[str, Any] | None = None,
        body: dict[str, Any] | None = None,
        auth: bool = True,
    ) -> dict[str, Any]:
        url = self._url(path, query)
        data = None
        headers = {"Accept": "application/json"}
        if auth:
            headers["Authorization"] = f"Bearer {self._token()}"
        if body is not None:
            data = json.dumps(body).encode("utf-8")
            headers["Content-Type"] = "application/json"
        request = urllib.request.Request(url, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(request, timeout=self.timeout) as response:
                return self._decode_response(response.read())
        except urllib.error.HTTPError as error:
            payload = self._decode_response(error.read(), fallback=None)
            if isinstance(payload, dict):
                return payload
            raise MusicBridgeError(
                f"Music bridge returned HTTP {error.code}.",
                status=error.code,
                code="http_error",
            ) from error
        except urllib.error.URLError as error:
            raise MusicBridgeError(
                f"Music bridge is not reachable at {self.base_url}. Open the Music app first.",
                code="bridge_unreachable",
            ) from error

    def _token(self) -> str:
        try:
            token = self.token_file.read_text(encoding="utf-8").strip()
        except FileNotFoundError as error:
            raise MusicBridgeError(
                f"Music bridge token file was not found at {self.token_file}. Open Music once first.",
                code="missing_token",
            ) from error
        if not token:
            raise MusicBridgeError(f"Music bridge token file is empty at {self.token_file}.", code="empty_token")
        return token

    def _url(self, path: str, query: dict[str, Any] | None) -> str:
        url = f"{self.base_url}{path}"
        if not query:
            return url
        filtered = {key: value for key, value in query.items() if value is not None}
        return f"{url}?{urllib.parse.urlencode(filtered)}"

    @staticmethod
    def _playlist_query(name: str | None = None, playlist_id: str | None = None) -> dict[str, str]:
        if playlist_id:
            return {"id": playlist_id}
        if name:
            return {"name": name}
        raise MusicBridgeError("Provide playlist name or playlist_id.", code="missing_playlist")

    @staticmethod
    def _decode_response(data: bytes, fallback: Any = ...) -> dict[str, Any]:
        try:
            payload = json.loads(data.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            if fallback is ...:
                raise MusicBridgeError("Music bridge returned invalid JSON.", code="invalid_json")
            return fallback
        if not isinstance(payload, dict):
            raise MusicBridgeError("Music bridge returned JSON that was not an object.", code="invalid_json_shape")
        return payload


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Call the local Music bridge as JSON.")
    parser.add_argument("--base-url", default=None)
    parser.add_argument("--token-file", default=None)
    parser.add_argument("--timeout", type=float, default=360.0)

    subparsers = parser.add_subparsers(dest="command", required=True)
    for name in ["health", "capabilities", "status", "songs", "groups", "now-playing", "playback-state", "library-sync", "window-controls", "process-timeout-diagnostics", "youtube-import-activity", "pause", "resume", "stop", "next", "previous", "refresh-library", "refresh-smart-picker"]:
        subparsers.add_parser(name)

    search = subparsers.add_parser("search")
    search.add_argument("query")

    candidates = subparsers.add_parser("candidates")
    candidates.add_argument("query")
    candidates.add_argument("--limit", type=int, default=5)

    play = subparsers.add_parser("play")
    play.add_argument("query")

    play_id = subparsers.add_parser("play-id")
    play_id.add_argument("song_id")

    source_metadata = subparsers.add_parser("source-metadata")
    source_metadata.add_argument("song_id")

    playlist_songs = subparsers.add_parser("playlist-songs")
    playlist_songs.add_argument("name")

    playlist_select = subparsers.add_parser("playlist-select")
    playlist_select.add_argument("name")

    playlist_play = subparsers.add_parser("playlist-play")
    playlist_play.add_argument("name")

    playlist_create = subparsers.add_parser("playlist-create")
    playlist_create.add_argument("name")

    playlist_rename = subparsers.add_parser("playlist-rename")
    playlist_rename.add_argument("old_name")
    playlist_rename.add_argument("new_name")

    playlist_delete = subparsers.add_parser("playlist-delete")
    playlist_delete.add_argument("name")

    song_move = subparsers.add_parser("song-move")
    song_move.add_argument("song_id")
    song_move.add_argument("playlist")

    volume = subparsers.add_parser("volume")
    volume.add_argument("level", type=float, nargs="?")

    seek = subparsers.add_parser("seek")
    seek.add_argument("seconds", type=float)

    shuffle = subparsers.add_parser("shuffle")
    shuffle.add_argument("enabled", choices=["true", "false", "on", "off", "1", "0"])

    repeat = subparsers.add_parser("repeat")
    repeat.add_argument("mode", choices=["off", "all", "one", "0", "1", "2"])

    window_action = subparsers.add_parser("window-control-action")
    window_action.add_argument("action", choices=["close", "minimize", "zoom"])

    youtube_open = subparsers.add_parser("youtube-open")
    youtube_open.add_argument("value", nargs="?", default=None)

    youtube_search = subparsers.add_parser("youtube-search")
    youtube_search.add_argument("query")
    youtube_search.add_argument("--limit", type=int, default=None)

    youtube_error = subparsers.add_parser("youtube-error-classification")
    youtube_error.add_argument("message")
    youtube_error.add_argument("--timed-out", action="store_true")

    youtube_import = subparsers.add_parser("youtube-import")
    youtube_import.add_argument("url")
    youtube_import.add_argument("title", nargs="?", default=None)

    youtube_import_watch = subparsers.add_parser("youtube-import-watch")
    youtube_import_watch.add_argument("url")
    youtube_import_watch.add_argument("title", nargs="?", default=None)
    youtube_import_watch.add_argument("--poll-interval", type=float, default=1.0)

    open_original = subparsers.add_parser("open-original")
    open_original.add_argument("song_id")

    args = parser.parse_args(argv)
    client = MusicBridgeClient(args.base_url, args.token_file, timeout=args.timeout)

    try:
        payload = dispatch(client, args)
    except MusicBridgeError as error:
        payload = error.as_payload()
        print(json.dumps(payload, indent=2, ensure_ascii=False))
        return 1

    print(json.dumps(payload, indent=2, ensure_ascii=False))
    return 0 if payload.get("ok") is not False else 1


def dispatch(client: MusicBridgeClient, args: argparse.Namespace) -> dict[str, Any]:
    command = args.command.replace("-", "_")
    if command == "now_playing":
        return client.now_playing()
    if command == "play_id":
        return client.play(song_id=args.song_id)
    if command == "playlist_songs":
        return client.playlist_songs(args.name)
    if command == "playlist_select":
        return client.playlist_select(args.name)
    if command == "playlist_play":
        return client.playlist_play(args.name)
    if command == "playlist_create":
        return client.playlist_create(args.name)
    if command == "playlist_rename":
        return client.playlist_rename(args.old_name, args.new_name)
    if command == "playlist_delete":
        return client.playlist_delete(args.name)
    if command == "song_move":
        return client.song_move(args.song_id, args.playlist)
    if command == "volume":
        return client.volume(args.level)
    if command == "seek":
        return client.seek(args.seconds)
    if command == "shuffle":
        return client.shuffle(args.enabled in {"true", "on", "1"})
    if command == "repeat":
        return client.repeat(args.mode)
    if command == "window_controls":
        return client.window_controls()
    if command == "window_control_action":
        return client.window_control_action(args.action)
    if command == "library_sync":
        return client.library_sync()
    if command == "source_metadata":
        return client.source_metadata(args.song_id)
    if command == "youtube_open":
        return client.youtube_open(args.value)
    if command == "youtube_search":
        return client.youtube_search(args.query, limit=args.limit)
    if command == "youtube_error_classification":
        return client.youtube_error_classification(args.message, timed_out=args.timed_out)
    if command == "youtube_import":
        return client.youtube_import(args.url, title=args.title)
    if command == "youtube_import_watch":
        last_seen: tuple[int | None, str | None] = (None, None)

        def show_progress(snapshot: dict[str, Any]) -> None:
            nonlocal last_seen
            percent = snapshot.get("progressPercent")
            status = snapshot.get("status")
            current = (percent, status)
            if current == last_seen:
                return
            last_seen = current
            print(f"youtube import: {percent}% - {status}", file=sys.stderr, flush=True)

        return client.youtube_import_with_progress(
            args.url,
            title=args.title,
            poll_interval=args.poll_interval,
            on_progress=show_progress,
        )
    if command == "open_original":
        return client.open_original(args.song_id)
    if command == "refresh_library":
        return client.refresh_library()
    if command == "refresh_smart_picker":
        return client.refresh_smart_picker()
    if command == "candidates":
        return {"ok": True, "query": args.query, "candidates": client.candidates(args.query, limit=args.limit)}
    if command == "play":
        return client.play(query=args.query)
    if command == "search":
        return client.search(args.query)
    method = getattr(client, command)
    return method()


if __name__ == "__main__":
    sys.exit(main())
