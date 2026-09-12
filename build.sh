#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="PaperlikeControl"
DEST="${1:-$ROOT/build/$APP_NAME.app}"
BIN="$DEST/Contents/MacOS"
RES="$DEST/Contents/Resources"

rm -rf "$DEST"
mkdir -p "$BIN" "$RES"

cp "$ROOT/Info.plist" "$DEST/Contents/Info.plist"
echo APPL > "$DEST/Contents/PkgInfo"
cp "$ROOT/Resources/black.png" "$ROOT/Resources/white.png" "$RES/"

swiftc -parse-as-library -O \
  "$ROOT/Sources/"*.swift \
  -o "$BIN/$APP_NAME" \
  -framework SwiftUI \
  -framework AppKit \
  -framework Carbon \
  -framework IOKit \
  -framework ApplicationServices \
  -framework CoreGraphics \
  -framework ServiceManagement \
  -target arm64-apple-macosx13.0

chmod +x "$BIN/$APP_NAME"
codesign --force --deep --sign - --entitlements "$ROOT/entitlements.plist" "$DEST"
echo "Built $DEST"
