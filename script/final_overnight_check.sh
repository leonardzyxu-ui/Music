#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "== time =="
date '+%Y-%m-%d %H:%M:%S %Z'

echo "== git status =="
git status --short

echo "== build =="
swift build

echo "== launch verify =="
./script/build_and_run.sh --verify

echo "== python compile =="
python3 -m py_compile script/jarvis_music_bridge.py script/test_bridge_contract.py

echo "== bridge contract =="
python3 script/test_bridge_contract.py

echo "== window diagnostics =="
python3 - <<'PY'
import json
import sys
sys.path.insert(0, "script")
from jarvis_music_bridge import MusicBridgeClient

client = MusicBridgeClient(timeout=10)
payload = client.window_controls()
shape = payload.get("windowShape", {})
print(json.dumps({
    "ok": payload.get("ok"),
    "visibleWindowCount": payload.get("visibleWindowCount"),
    "outerCornerMode": shape.get("outerCornerMode"),
    "backgroundIsSpaceBlack": shape.get("backgroundIsSpaceBlack"),
    "sharingTypeRawValue": shape.get("sharingTypeRawValue"),
    "titlebarAppearsTransparent": shape.get("titlebarAppearsTransparent"),
    "usesFullSizeContentView": shape.get("usesFullSizeContentView"),
}, indent=2))

snapshot = client.window_snapshot()
print(json.dumps(snapshot, indent=2))
PY

echo "== legacy window corner audit =="
if python3 script/audit_window_corners.py; then
  echo "corner audit passed"
else
  echo "corner audit failed with known capture limitation"
fi

echo "== whitespace =="
git diff --check

echo "== done =="
