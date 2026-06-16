#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Music"
PRODUCT="LeoMusic"
LEGACY_PRODUCT="JarvisMusic"
CONFIG="debug"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/dist/$APP_NAME.app"
VERIFY=0
LOGS=0
DEBUG=0
TELEMETRY=0

for arg in "$@"; do
  case "$arg" in
    --verify) VERIFY=1 ;;
    --logs) LOGS=1 ;;
    --debug) DEBUG=1 ;;
    --telemetry) TELEMETRY=1 ;;
    run) ;;
    *) echo "usage: $0 [run|--verify|--logs|--debug|--telemetry]" >&2; exit 2 ;;
  esac
done

cd "$ROOT"

quit_running_app() {
  osascript -e 'tell application id "com.leoxu.Music" to quit' >/dev/null 2>&1 || true
  for _ in {1..20}; do
    if ! pgrep -x "$PRODUCT" >/dev/null 2>&1 && ! pgrep -x "$LEGACY_PRODUCT" >/dev/null 2>&1; then
      return
    fi
    sleep 0.2
  done
  pkill -x "$PRODUCT" >/dev/null 2>&1 || true
  pkill -x "$LEGACY_PRODUCT" >/dev/null 2>&1 || true
  sleep 0.6
}

quit_running_app

swift build -c "$CONFIG"
BUILD_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$PRODUCT"
if [[ ! -x "$BUILD_BINARY" ]]; then BUILD_BINARY="$BUILD_DIR/$LEGACY_PRODUCT"; fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD_BINARY" "$APP/Contents/MacOS/$PRODUCT"
cp "Sources/JarvisMusic/Resources/AppLogo.png" "$APP/Contents/Resources/AppLogo.png"

ICONSET="$ROOT/dist/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "Sources/JarvisMusic/Resources/AppLogo.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z "$((size * 2))" "$((size * 2))" "Sources/JarvisMusic/Resources/AppLogo.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" >/dev/null 2>&1 || true
rm -rf "$ICONSET"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$PRODUCT</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>com.leoxu.Music</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

if [[ "$DEBUG" == "1" ]]; then
  lldb -- "$APP/Contents/MacOS/$PRODUCT"
  exit $?
fi

/usr/bin/open "$APP"

if [[ "$VERIFY" == "1" ]]; then
  for _ in {1..30}; do
    if pgrep -x "$PRODUCT" >/dev/null 2>&1; then
      echo "$APP_NAME launched ($PRODUCT)."
      break
    fi
    sleep 0.2
  done
  pgrep -x "$PRODUCT" >/dev/null
fi

if [[ "$LOGS" == "1" ]]; then
  /usr/bin/log stream --info --style compact --predicate "process == \"$PRODUCT\""
fi

if [[ "$TELEMETRY" == "1" ]]; then
  /usr/bin/log stream --info --style compact --predicate "subsystem == \"com.leoxu.Music\""
fi
