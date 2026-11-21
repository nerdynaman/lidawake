#!/bin/sh
set -eu
cd "$(dirname "$0")"
app=build/LidAwake.app
mkdir -p "$app/Contents/MacOS"
# Embed the exact helper that the administrator authorizes at setup.
{ echo 'let sessionScript = #"""'; cat session.sh; echo '"""#'; } > build/Session.swift
/usr/bin/xcrun swiftc -O -target arm64-apple-macos26.0 -module-cache-path "${TMPDIR:-/tmp}/lidawake-swift-cache" main.swift Permission.swift build/Session.swift -o "$app/Contents/MacOS/LidAwake"
/bin/cp Info.plist "$app/Contents/Info.plist"
/usr/bin/codesign --force --sign - --options runtime "$app"
/usr/bin/codesign --verify --strict "$app"
