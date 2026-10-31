# Architecture

Tangent is a single AppKit process. It owns one desktop-level window and one
player per display, reads wallpaper packs from disk in place, and exposes a
menu-bar UI: a status-item popover plus the library, properties, Settings and
About windows.

```
                 ┌──────────────┐
 status item ──► │  AppDelegate │ ──► Popover / Library / Properties / Settings
                 └──────┬───────┘
                        │
                 ┌──────▼────────┐        ┌───────────────┐
                 │WallpaperEngine│◄──────►│ DisplayLayout │
                 └──────┬────────┘        └───────────────┘
        per display     │
        ┌───────────────┼────────────────┐
        ▼               ▼                ▼
 WallpaperWindow   WallpaperWindow  WallpaperWindow
        │               │                │
        ▼               ▼                ▼
   Video/MPV/Web/Image/… players (one per display)
```

## Desktop embedding

macOS provides no supported way to parent a window behind the desktop icons.
Instead the WindowServer exposes levels:

| Level | Constant |
|---|---|
| `-2147483623` | `kCGDesktopWindowLevel` (static desktop picture) |
| `-2147483622` | Tangent's wallpaper window (`desktopWindow + 1`) |
| `-2147483603` | `kCGDesktopIconWindowLevel` (icons) |

`WallpaperWindow` is a borderless, non-activating, click-through `NSWindow`:

- `level = CGWindowLevelForKey(.desktopWindow) + 1`
- `ignoresMouseEvents = true`
- `collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle,
  .fullScreenAuxiliary]`
- `hasShadow = false`, `isOpaque = false`, transparent background

Because the window lives below the icons and the WindowServer owns the desktop
lifecycle, there are no shell hooks, no `SetParent`, and no recovery path for a
crashing window manager.

## Components

| File | Responsibility |
|---|---|
| `main.swift` | CLI parsing, probes, snapshots, entry point |
| `AppDelegate.swift` | status item, menus, apply/apply-next, window wiring |
| `WallpaperEngine.swift` | creates one window+player per display; pause reasons; property broadcast |
| `WallpaperWindow.swift` | desktop-level click-through window |
| `DisplayLayout.swift` | default config plus per-display pins/disable, keyed by `CGDirectDisplayID` |
| `Wallpaper.swift` | `WallpaperConfig`, `Wallpaper` protocol, `WallpaperFactory` |
| `VideoRouting.swift` | container/codec inspection, backend choice, fallback |
| `VideoWallpaper.swift` | AVFoundation `AVPlayerLayer` backend |
| `MPVWallpaper.swift` | libmpv + OpenGL backend |
| `WebWallpaper.swift` | `WKWebView` backend and property bridge |
| `ImageWallpaper.swift` | GIF and still-image backend |
| `Packs/PackFormat.swift` | the only declaration of format filenames and listener names |
| `Packs/PackInfo.swift` | metadata parsing, entry/thumbnail/preview resolution |
| `Packs/PackProperties.swift` | eight control types, defaults, interaction values |
| `Packs/PackLibrary.swift` | library roots and entries, scanning, deduplication |
| `Packs/PropertyStore.swift` | per-pack customised copy of the control file |
| `Packs/ThumbnailProvider.swift` | cached thumbnails, video frame extraction |
| `Packs/JSONValue.swift` | loosely-typed JSON tree |
| `Packs/WallpaperType.swift` | type names, support status, user-facing reasons |
| `Playback/PlaybackMonitor.swift` | fullscreen / battery / lock detection |
| `Hotkeys/HotkeyManager.swift` | Carbon hot keys, bindings, validation, persistence |
| `Services/GitHubConfig.swift` | official repository URLs, bug-form template, validated HTTPS opening |
| `Services/ReleaseModel.swift` | GitHub release decoders, semver, asset selection, update policy |
| `Services/UpdateChecker.swift` | conditional release request, 24-hour schedule, cached state machine |
| `Services/FeedbackManager.swift` | sysctl diagnostics, privacy summary, issue URL and clipboard flows |
| `Services/DesktopIcons.swift` | Finder `CreateDesktop` preference, relaunch and injectable command store |
| `UI/LibraryWindowController.swift` | library window: sidebar, gallery, inspector, section pages, window shortcuts |
| `UI/LibraryModel.swift` | library entries, favorites, hidden packs, queries |
| `UI/LibraryPages.swift` | Displays, Automation (rules, shortcuts, desktop icons) and About pages |
| `UI/WallpaperCardView.swift` | 16:10 gallery card, hover lift, video preview, context menu |
| `UI/WallpaperInspectorView.swift` | inspector: preview, details and actions |
| `UI/MenuBarPopoverController.swift` | fixed 340 pt status-item popover: preview, actions, displays, pause/mute/desktop-icon switches, footer |
| `UI/AppModel.swift` | `AppSnapshot` / `AppActions` interface between UI and shell |
| `UI/Theme.swift` | colors, type scale, spacing, radii and animation tokens |
| `UI/Components.swift` | themed surfaces, buttons, badges, labels, the official brand mark and shared views |
| `UI/AboutContent.swift` | shared About copy and controls |
| `UI/AboutFeedback.swift` | shared About & Feedback page, update/help/community cards, bug-report privacy preview |
| `UI/KoFiSupport.swift` | Ko-fi-branded support button and the in-app `WKWebView` tip window |
| `UI/AboutWindowController.swift` | standalone About window |
| `UI/GalleryModel.swift` | search, filters, cycling |
| `UI/ControlPanelController.swift` | property editor |
| `UI/SettingsWindowController.swift` | four panes and shortcut recorder |

## Playback routing

`VideoRouting` inspects each file before a player is created:

1. **Container by extension.** `mp4`, `mov`, `m4v`, `mpg`, `mpeg` are candidates
   for AVFoundation. `webm`, `mkv`, `avi`, `ogv`, `flv` go straight to libmpv.
2. **Codec by FourCC.** VP9, VP8 and AV1 inside MP4/MOV also go to libmpv, as do
   other codecs AVFoundation cannot decode.
3. **Fallback.** If AVFoundation fails to open or play a candidate, the engine
   retries the same file once with libmpv.

AVFoundation is preferred where it works: hardware decode, lower CPU, correct
HDR handling. libmpv covers the rest and is also the fallback for damaged
containers.

### libmpv loading and bundling

libmpv is never linked. `MPVAPI` resolves it at runtime, in this order:

1. `TANGENT_LIBMPV` — exclusive override, used for testing and custom builds
2. `Tangent.app/Contents/Frameworks/libmpv.2.dylib`
3. `/opt/homebrew/opt/mpv/lib/libmpv.2.dylib` and the usual Homebrew prefixes

`Scripts/bundle-libmpv.py` copies the dylib closure (50 libraries, ~61 MB),
rewrites every install name to `@rpath`, adds `@loader_path` so siblings resolve
inside the bundle, strips absolute Homebrew rpaths, signs each library from the
inside out, and copies license files into `Contents/Resources/Licenses`.

All libmpv calls run on the main thread except `mpv_wait_event`, which blocks on
a dedicated queue and hands frames to the OpenGL view.

## Pack format

A pack is a directory. `PackInfo` reads the metadata file and resolves:

- `FileName` relative to the folder, or absolute when `IsAbsolutePath` is set
  (also accepted when the value itself is absolute or `http(s)`)
- `Thumbnail` / `Preview` with the same rule
- `index.html` as the entry point for web packs without a `FileName`

A bare video, GIF, image or HTML file can also be opened directly; it is wrapped
as a synthetic pack with `IsAbsolutePath` semantics, so every downstream
component sees one shape. Its identity (`Pack.id`) is the file path, not the
containing folder, so several files in one folder remain distinct entries.

`PackProperties` parses the optional control file into eight control types and
produces the values pushed on load:

| Type | Value pushed | Notes |
|---|---|---|
| `slider` | number | min/max/step from the file |
| `textbox` | string | |
| `dropdown` | number | selected index |
| `checkbox` | bool | |
| `color` | string | `#RGB` / `#RRGGBB` / `#RRGGBBAA` |
| `folderDropdown` | string or `null` | `null` when the file is absent |
| `button` | nothing on load | sends `true` on click |
| `label` | nothing | display only |

Edits never touch the pack. `PropertyStore` copies the control file into
`~/Library/Application Support/Tangent/Properties/<pack>-<hash>/`, edits that
copy, and deletes it on reset. Key order in the file is not preserved by the
parser; controls are presented sorted by name for a stable UI.

## Web bridge

`WebWallpaper` injects a listener call after navigation:

```js
(function () {
  var n = "speed", v = 1.5;
  if (typeof window.tangentPropertyListener === 'function') {
    window.tangentPropertyListener(n, v);
  } else if (typeof window.<legacy name> === 'function') {
    window.<legacy name>(n, v);
  }
})();
```

The modern name is preferred; the historical name is kept so existing packs keep
working. The same call is used for live edits from the control panel, so there is
no separate update path.

## Persistence

All state lives in `UserDefaults` under the `tangent.` prefix:

| Key | Contents |
|---|---|
| `tangent.activeWallpaper` | `DisplayLayout` (default config, pins, disabled displays) |
| `tangent.library.roots` | folders scanned for packs |
| `tangent.library.entries` | individually added packs or bare files |
| `tangent.playbackPolicy` | fullscreen / battery / lock toggles |
| `tangent.hotkeys.enabled` | global shortcuts on/off |
| `tangent.hotkeys.bindings` | only customised bindings |
| `tangent.mpv.*` | nothing persisted; present only in diagnostics |

`WallpaperStore.load()` accepts both the current layout shape and the older
single-wallpaper blob, so an upgrade never drops the active wallpaper.

The desktop-icon switch is the one setting Tangent does not own: it reads and
writes Finder's `com.apple.finder` `CreateDesktop` key, so Finder remains the
source of truth. A missing key is treated as Finder's default, visible icons.
After a write, Tangent asks Finder to relaunch so the desktop redraws. Both the
popover and the Automation page read the same `DesktopIcons.State`; the service
accepts an injectable store so tests never change the real preference.

## Desktop icons

`DesktopIcons` is deliberately independent of the wallpaper engine:

- `refresh()` reads `defaults read com.apple.finder CreateDesktop`. Exit 1
  (missing key) means visible; an unambiguous boolean is mapped to
  `visible`/`hidden`.
- `setHidden(_:)` runs the write and `/usr/bin/killall Finder` on a background
  queue, sets a busy flag first, then re-reads the preference and publishes the
  result on the main queue.
- A write failure never restarts Finder. A relaunch failure is reported without
  pretending the preference failed.
- `AppDelegate` mirrors the state into `AppSnapshot` and refreshes the popover
  and the open library page when it changes; there is no second stored flag to
  drift out of sync.

## Updates and diagnostics

`GitHubRepo` is the only place the official project appears: owner
`anuragdevcode`, repository `Tangent`, the latest-release API, Discussions,
releases and the bug-report template. `ExternalLink` refuses non-HTTPS URLs
before opening anything.

`UpdateChecker` makes one conditional `URLSession` request (Accept
`application/vnd.github+json`, API version `2022-11-28`, ETag) and stores the
last release plus check date. It throttles ordinary launches to 24 hours,
bypasses the interval only for an explicit check, and never runs two requests at
once. `ReleaseModel` compares semantic versions (including prereleases), ignores
drafts and prereleases for stable builds, and picks a universal DMG, an
architecture-matching DMG, the only DMG, or the release page in that order.
Nothing is downloaded, mounted, replaced or executed.

`FeedbackManager` builds the diagnostic summary from the bundle version,
`ProcessInfo`/`sysctl` fields and running architecture. It excludes serial
numbers, Apple IDs, usernames, home paths, IP addresses, installed apps and
files. The issue URL carries only the template and title because GitHub issue
forms ignore prefilled bodies; the summary is copied to the clipboard after a
privacy preview.

## Shortcuts

`HotkeyManager` uses Carbon `RegisterEventHotKey` rather than `NSEvent` monitors,
because global hot keys work while another app is frontmost and require no
Accessibility or Input Monitoring permission.

- Four actions, each with a stable numeric identifier.
- Defaults are Control-Option combinations; users can rebind them.
- Custom bindings are validated (Control or Option required, no modifier-only
  keys, no Escape, no duplicate of another action's current or default binding)
  and sanitized on load if the stored data is corrupt.
- Registration is per action: one failure leaves the others working and is
  reported in Settings and the Hotkeys menu.

## Build

`build.sh` compiles every Swift file with `swiftc` directly — no Xcode project,
no SwiftPM, no SwiftUI macros:

1. Detect architecture (`arm64` or `--universal`).
2. Compile with `-O`, `-target <arch>-apple-macos13.0`, AppKit/WebKit/AVFoundation/
   CoreGraphics/Carbon/IOKit, and the libmpv header path.
3. Assemble `Tangent.app` from `Resources/Info.plist`, the binary and the icon
   assets (`AppIcon.icns` for `CFBundleIconFile`, `BrandMark.png` for the About
   and popover mark).
4. Bundle the libmpv closure unless `TANGENT_BUNDLE_LIBMPV=0`.
5. Ad-hoc sign inside out and verify.

`MPV_PREFIX` overrides the build-time mpv prefix. `TANGENT_LIBMPV` overrides the
runtime library and is exclusive — it is never combined with the bundled copy.

## Key decisions

- **AppKit only.** SwiftUI `@State`/macro support is unavailable with Command
  Line Tools, so every window is hand-built.
- **Per-display windows.** One window and player per `NSScreen` gives clone and
  independent modes without fighting Spaces; true spanning is not offered.
- **Packs referenced in place.** No import step, no copying, no shadow library.
  Removing an entry never deletes user files.
- **AVFoundation first, libmpv second.** Hardware decode where possible, broad
  codec coverage where needed, automatic fallback when AVFoundation rejects a
  file.
- **Carbon hot keys.** No extra permissions and no event taps.
- **Explicit apply.** Gallery selection never changes the wallpaper by itself.
- **One property copy per pack.** Simpler than per-display copies; documented as
  a limitation.
- **A fixed-width popover.** `NSPopover` sizes itself from its content, so the
  content view pins a required 340 pt width, the preview image gives up its
  intrinsic size first, and the height is measured from the content stack.
  Artwork and long display names therefore never resize the surface.
- **Format constants in one file.** `PackFormat` is the only place on-disk and
  page-level format names appear.

## Verification

`--test` runs 301 assertions with no test framework: JSON parsing, metadata and
property parsing, entry resolution, library scanning, type support, bridge
payloads, property copies, display layouts, gallery query/filter/cycling,
shortcut validation/persistence, GitHub release/update policy, diagnostics
privacy, and the desktop-icon state machine.

Runtime checks that cannot run in-process are exposed as CLI flags:

| Flag | Purpose |
|---|---|
| `--probe-bridge <folder>` | loads a page and reports the property payload it received |
| `--probe-mpv <file>` | decodes through libmpv and reports codec, size, frames, errors |
| `--probe-kofi` | opens the real support window in a fresh session and reports title, login state and page text |
| `--report-frames <seconds>` | counts frames rendered by the desktop-level window |
| `--probe-advance <seconds>` | runs one Next Wallpaper step and reports each display's title before and after |
| `--hotkey-status` | registers all bindings and reports status without saving |
| `--snapshot-library` / `--snapshot-properties` / `--snapshot-settings` / `--snapshot-popover` | in-process PNG capture, no Screen Recording permission |
| `--selftest` | architecture, screens, window levels, library path |

## Roadmap

1. Build libmpv/ffmpeg against the macOS 13 SDK to remove the 27.0 floor from
   bundled libraries.
2. Add an `x86_64` libmpv closure for Intel machines.
3. Remote/HLS `videostream` playback.
4. Host audio feed for audio-reactive packs (ScreenCaptureKit or CoreAudio tap).
5. Per-display property copies.
6. Developer ID signing and notarization.
