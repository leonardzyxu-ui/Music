#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTROL="$PROJECT_DIR/script/jarvis-music-control"
CONFIRM="${1:-}"

library_path="$("$CONTROL" status | python3 -c 'import json,sys; print(json.load(sys.stdin)["libraryPath"])')"

matches=()
while IFS= read -r match; do
  matches+=("$match")
done < <(find "$library_path" -maxdepth 1 -type f \( -name 'Codex Import Smoke Test*.mp3' -o -name 'Codex Progress Probe*.mp3' \) -print)

if [[ "${#matches[@]}" -eq 0 ]]; then
  echo "No Codex smoke/progress test imports found."
  exit 0
fi

printf 'Smoke-test imports in %s:\n' "$library_path"
printf '  %s\n' "${matches[@]}"

if [[ "$CONFIRM" != "--yes" ]]; then
  echo
  echo "Dry run only. Re-run with --yes to delete these test files and refresh the library."
  exit 0
fi

rm -- "${matches[@]}"
"$CONTROL" refresh-library >/dev/null
echo "Deleted ${#matches[@]} smoke-test import(s) and refreshed the library."
