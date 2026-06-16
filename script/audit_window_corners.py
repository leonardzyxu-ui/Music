#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import sys
import time
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SCREENSHOT = ROOT / "screenshots" / "window-corner-audit.png"
CROP = ROOT / "screenshots" / "window-corner-audit-crop.png"
MIN_RETINA_CORNER_PIXELS = 50
MAX_RETINA_CORNER_PIXELS = 84


def find_music_window_id() -> str:
    subprocess.run(
        ["osascript", "-e", 'tell application id "com.leoxu.Music" to activate'],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    time.sleep(0.8)

    script = r'''
import CoreGraphics
import Foundation

let opts = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
let windows = CGWindowListCopyWindowInfo(opts, CGWindowID(0)) as? [[String: Any]] ?? []
for window in windows {
    let owner = window[kCGWindowOwnerName as String] as? String ?? ""
    let name = window[kCGWindowName as String] as? String ?? ""
    if owner == "Music" && name == "Music" {
        print(window[kCGWindowNumber as String] ?? "")
        exit(0)
    }
}
exit(1)
'''
    for _ in range(10):
        result = subprocess.run(
            ["swift", "-e", script],
            cwd=ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        window_id = result.stdout.strip()
        if result.returncode == 0 and window_id:
            return window_id
        time.sleep(0.4)
    raise RuntimeError("Could not find a visible Music window to audit.")


def capture_window(window_id: str) -> None:
    SCREENSHOT.parent.mkdir(parents=True, exist_ok=True)
    for _ in range(4):
        result = subprocess.run(
            ["screencapture", "-x", "-o", "-l", window_id, str(SCREENSHOT)],
            cwd=ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode == 0 and SCREENSHOT.exists():
            return
        time.sleep(0.5)
    raise RuntimeError((result.stderr or result.stdout or "screencapture failed").strip())


def first_alpha_on_row(image: Image.Image, row: int) -> int | None:
    pixels = image.load()
    for x in range(image.width):
        if pixels[x, row][3] > 10:
            return x
    return None


def first_alpha_on_column(image: Image.Image, column: int) -> int | None:
    pixels = image.load()
    for y in range(image.height):
        if pixels[column, y][3] > 10:
            return y
    return None


def audit() -> dict[str, object]:
    window_id = find_music_window_id()
    capture_window(window_id)

    image = Image.open(SCREENSHOT).convert("RGBA")
    image.crop((0, 0, min(620, image.width), min(360, image.height))).save(CROP)

    top_row_start = first_alpha_on_row(image, 0)
    left_column_start = first_alpha_on_column(image, 0)
    passed = (
        top_row_start is not None
        and left_column_start is not None
        and top_row_start >= MIN_RETINA_CORNER_PIXELS
        and left_column_start >= MIN_RETINA_CORNER_PIXELS
        and top_row_start <= MAX_RETINA_CORNER_PIXELS
        and left_column_start <= MAX_RETINA_CORNER_PIXELS
    )

    return {
        "ok": passed,
        "windowID": window_id,
        "screenshot": str(SCREENSHOT),
        "crop": str(CROP),
        "topRowFirstVisiblePixel": top_row_start,
        "leftColumnFirstVisiblePixel": left_column_start,
        "minimumRetinaCornerPixels": MIN_RETINA_CORNER_PIXELS,
        "maximumRetinaCornerPixels": MAX_RETINA_CORNER_PIXELS,
    }


def main() -> int:
    try:
        payload = audit()
    except Exception as exc:
        print(json.dumps({"ok": False, "error": str(exc)}, indent=2), file=sys.stderr)
        return 1
    print(json.dumps(payload, indent=2))
    return 0 if payload["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
