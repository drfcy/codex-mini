#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
DEST="${1:-.build/Codex Mini.app}"
xcrun swift Scripts/make-icons.swift "$(pwd)/Resources"
mkdir -p "$DEST/Contents/MacOS" "$DEST/Contents/Resources"
xcrun swiftc -O -swift-version 6 -target arm64-apple-macosx14.0 \
  Sources/Usage.swift Sources/main.swift -o "$DEST/Contents/MacOS/CodexMini" \
  -framework AppKit -framework ServiceManagement
cp Resources/MenuIcon.png Resources/AppIcon.icns "$DEST/Contents/Resources/"
if [ -f "$DEST/Contents/Resources/ChatGPT.png" ]; then
  rm "$DEST/Contents/Resources/ChatGPT.png"
fi
cp THIRD_PARTY_NOTICES.txt "$DEST/Contents/Resources/THIRD_PARTY_NOTICES.txt"
cp Info.plist "$DEST/Contents/Info.plist"
/usr/bin/xattr -cr "$DEST"
# File Provider can retain FinderInfo on the root bundle after recursive cleanup.
/usr/bin/xattr -d com.apple.FinderInfo "$DEST" 2>/dev/null || true
/usr/bin/codesign --force --sign - "$DEST"
echo "已生成：$DEST"
