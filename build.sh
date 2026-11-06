#!/bin/bash
#
# Builds Tangent.app for Apple Silicon.
#   ./build.sh -> arm64 only (M1/M2/M3/M4/M5...)
#
# Also builds Tangent.saver and embeds it in the app, so Screen Saver mode can
# install it without shipping source code or a compiler to users.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/Tangent.app"
BIN="$APP/Contents/MacOS/Tangent"
SAVER="$ROOT/build/Tangent.saver"
SAVER_BIN="$SAVER/Contents/MacOS/TangentScreenSaver"
MIN_MACOS="13.0"
TARGET="arm64-apple-macos${MIN_MACOS}"
MPV_PREFIX="${MPV_PREFIX:-/opt/homebrew/opt/mpv}"
BUNDLE_LIBMPV="${TANGENT_BUNDLE_LIBMPV:-1}"
BRIDGING_HEADER="$ROOT/Resources/Tangent-Bridging-Header.h"
SOURCES=()
while IFS= read -r file; do SOURCES+=("$file"); done < <(find "$ROOT/Sources/Tangent" -name "*.swift" | sort)

# The saver deliberately links only the players and pack plumbing it needs.
SAVER_SOURCES=(
	"$ROOT/Sources/Tangent/DisplayLayout.swift"
	"$ROOT/Sources/Tangent/Wallpaper.swift"
	"$ROOT/Sources/Tangent/VideoWallpaper.swift"
	"$ROOT/Sources/Tangent/VideoRouting.swift"
	"$ROOT/Sources/Tangent/ImageWallpaper.swift"
	"$ROOT/Sources/Tangent/WebWallpaper.swift"
	"$ROOT/Sources/Tangent/MPVWallpaper.swift"
	"$ROOT/Sources/Tangent/MPVAPI.swift"
	"$ROOT/Sources/Tangent/Packs/JSONValue.swift"
	"$ROOT/Sources/Tangent/Packs/PackFormat.swift"
	"$ROOT/Sources/Tangent/Packs/PackInfo.swift"
	"$ROOT/Sources/Tangent/Packs/PackProperties.swift"
	"$ROOT/Sources/Tangent/Packs/PropertyStore.swift"
	"$ROOT/Sources/Tangent/Packs/WallpaperType.swift"
	"$ROOT/Sources/Tangent/ScreenSaver/ScreenSaverConfiguration.swift"
	"$ROOT/ScreenSaver/TangentScreenSaverView.swift"
)

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

SAVER_FRAMEWORKS=(
	-framework AppKit
	-framework AVFoundation
	-framework WebKit
	-framework QuartzCore
	-framework IOKit
	-framework OpenGL
	-framework ScreenSaver
)

compile() { # $1 = output path
	swiftc -O -swift-version 5 \
		-target "$TARGET" \
		-I"$MPV_PREFIX/include" \
		-import-objc-header "$BRIDGING_HEADER" \
		"${FRAMEWORKS[@]}" \
		-o "$1" \
		"${SOURCES[@]}"
}

build_saver() {
	rm -rf "$SAVER"
	mkdir -p "$SAVER/Contents/MacOS" "$SAVER/Contents/Resources"

	swiftc -O -swift-version 5 -emit-library -Xlinker -bundle \
		-target "$TARGET" \
		-I"$MPV_PREFIX/include" \
		-import-objc-header "$BRIDGING_HEADER" \
		"${SAVER_FRAMEWORKS[@]}" \
		-o "$SAVER_BIN" \
		"${SAVER_SOURCES[@]}"

	cp "$ROOT/Resources/TangentSaver-Info.plist" "$SAVER/Contents/Info.plist"
	# A thumbnail keeps Tangent recognisable in System Settings. The brand mark
	# is square, so pad it rather than stretch it.
	if [[ -f "$ROOT/Resources/BrandMark.png" ]]; then
		sips -s format png "$ROOT/Resources/BrandMark.png" \
			--resampleHeightWidth 116 116 \
			--out "$SAVER/Contents/Resources/thumbnail.png" >/dev/null 2>&1 || true
	fi

	codesign --force --sign - "$SAVER" >/dev/null
}

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

compile "$BIN"
build_saver
cp -R "$SAVER" "$APP/Contents/Resources/Tangent.saver"

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/Resources/BrandMark.png" "$APP/Contents/Resources/BrandMark.png"

# Embed libmpv and its dylib closure so the app does not need Homebrew at
# runtime. Set TANGENT_BUNDLE_LIBMPV=0 to keep the build lean while iterating.
if [[ "$BUNDLE_LIBMPV" != "0" ]]; then
	python3 "$ROOT/Scripts/bundle-libmpv.py" \
		--app "$APP" \
		--prefix "$MPV_PREFIX" \
		--quiet
fi

# Ad-hoc signature: enough to run locally. Replace with a Developer ID for
# distribution (Screen Recording is NOT needed by this design).
codesign --force --sign - "$APP" >/dev/null

echo "Built: $APP"
file "$BIN"
