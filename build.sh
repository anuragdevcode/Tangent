#!/bin/bash
#
# Builds Tangent.app for Apple Silicon.
#   ./build.sh              -> arm64 only (M1/M2/M3/M4/M5...)
#   ./build.sh --universal  -> arm64 + x86_64 fat binary
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/Tangent.app"
BIN="$APP/Contents/MacOS/Tangent"
MIN_MACOS="13.0"
MPV_PREFIX="${MPV_PREFIX:-/opt/homebrew/opt/mpv}"
BUNDLE_LIBMPV="${TANGENT_BUNDLE_LIBMPV:-1}"
BRIDGING_HEADER="$ROOT/Resources/Tangent-Bridging-Header.h"
SOURCES=()
while IFS= read -r file; do SOURCES+=("$file"); done < <(find "$ROOT/Sources" -name "*.swift" | sort)

if [[ ! -f "$MPV_PREFIX/include/mpv/client.h" ]]; then
	echo "error: libmpv headers not found at $MPV_PREFIX" >&2
	echo "       install with: brew install mpv" >&2
	exit 1
fi

FRAMEWORKS=(
	-framework AppKit
	-framework AVFoundation
	-framework WebKit
	-framework QuartzCore
	-framework UniformTypeIdentifiers
	-framework IOKit
	-framework OpenGL
	-framework Carbon
)

compile() { # $1 = target arch, $2 = output path
	swiftc -O -swift-version 5 \
		-target "$1-apple-macos${MIN_MACOS}" \
		-I"$MPV_PREFIX/include" \
		-import-objc-header "$BRIDGING_HEADER" \
		"${FRAMEWORKS[@]}" \
		-o "$2" \
		"${SOURCES[@]}"
}

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if [[ "${1:-}" == "--universal" ]]; then
	TMP="$(mktemp -d)"
	trap 'rm -rf "$TMP"' EXIT
	compile arm64 "$TMP/arm64"
	compile x86_64 "$TMP/x86_64"
	lipo -create "$TMP/arm64" "$TMP/x86_64" -output "$BIN"
else
	compile arm64 "$BIN"
fi

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# Embed libmpv and its dylib closure so the app does not need Homebrew at
# runtime. Set TANGENT_BUNDLE_LIBMPV=0 to keep the build lean while iterating.
if [[ "$BUNDLE_LIBMPV" != "0" ]]; then
	python3 "$ROOT/Scripts/bundle-libmpv.py" \
		--app "$APP" \
		--prefix "$MPV_PREFIX" \
		--quiet

	MPV_ARCHS="$(lipo -archs "$APP/Contents/Frameworks/libmpv.2.dylib" 2>/dev/null || echo unknown)"
	if [[ "${1:-}" == "--universal" && "$MPV_ARCHS" != *"x86_64"* ]]; then
		echo "note: bundled libmpv is $MPV_ARCHS only; the x86_64 slice can play H.264/HEVC but not VP9/AV1" >&2
	fi
fi

# Ad-hoc signature: enough to run locally. Replace with a Developer ID for
# distribution (Screen Recording is NOT needed by this design).
codesign --force --sign - "$APP" >/dev/null

echo "Built: $APP"
file "$BIN"
