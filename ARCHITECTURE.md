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
| `WebWallpaper.swift` | `WKWebView` backend, property bridge and opt-in environment feed |
| `ImageWallpaper.swift` | GIF and still-image backend |
| `Environment/EnvironmentMonitor.swift` | one shared 30 Hz source of pointer, day phase, audio presence, appearance, Reduce Motion and Low Power Mode |
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

### Ambient environment

A web pack opts in with `tangent.enableEnvironment()`. The bootstrap object
`window.tangent` is injected before the pack's own scripts and also carries
`version`, `playing`, `onEnvironment`, `onPlaying` and `setDayPhase`.
`WebWallpaper` registers one observer with `EnvironmentMonitor` and pushes the
snapshot through the same script-message bridge; the page receives it on
`tangent.onEnvironment` and can read the last value from `tangent.environment`.

`EnvironmentMonitor` owns a single 30 Hz timer and a 2-second audio poll, starts
them on the first observer and stops them on the last, so a static pack pays
nothing. Values are derived without a permission prompt: pointer from
`NSEvent.mouseLocation` converted into the view's own coordinates, day phase from
the local clock, audio presence from the default output device's
`DeviceIsRunningSomewhere` property (with a short hold so track changes do not
flicker), `dark` from `effectiveAppearance`, and Reduce Motion / Low Power Mode
from `NSWorkspace` and `ProcessInfo`.

The bridge throttles identical states and is only enabled for local pages. A
remote `url` pack never receives the feed, because that would leak the pointer
and the user's listening state to a network origin.

## Built-in wallpapers

`Resources/Wallpapers` holds the first-party packs. `PackLibrary` treats
`Bundle.main.resourceURL/Wallpapers` as an implicit root, so the packs appear in
the library with the user's own, and `ScreenSaverStager` copies them into the
saver snapshot like any other referenced pack.

All three are plain web packs, with no privileged API beyond the bridge:

- **Contour** builds its ridges from deterministic value noise and a ridged
  fractal, clips one contour group per ridge against the next one's silhouette,
  and repaints its palette as the day phase moves.
- **Membrane** traces two spheres with a shallow, pointer-driven deformation and
  shades a thin film with a three-wavelength interference term. It selects the
  backdrop by refraction and reflection, so the window it hangs in front of shows
  up on both surfaces, and it caps resolution when frames run long.
- **Dust** draws a cone of light into a half-resolution buffer — two nested
  gradient fills with a shared cross-section profile, faded along their length
  with `destination-in` — then places seeded motes by distance along and across
  that axis, so brightness follows the beam instead of the frame. The scene is
  rendered at a fixed 1920×1200 and stretched by CSS: the composition is soft by
  nature, its cost stays predictable, and a paused or throttled host never
  catches the canvas at a stale size.

`tangent.setDayPhase()` repaints a paused pack, which is what the thumbnail and
still-frame probes use; the thumbnails in the repository were generated from the
real packs with `--snapshot-wallpaper` and downscaled, never drawn separately.

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

## Screen Saver

Screen Saver mode is a real legacy `.saver` bundle, not a full-screen window
imitating one:

- `ScreenSaver/TangentScreenSaverView.swift` subclasses `ScreenSaverView`. It is
  compiled separately into `build/Tangent.saver/Contents/MacOS/TangentScreenSaver`
  with `-Xlinker -bundle`, so the executable is a Mach-O bundle rather than a
  dylib.
- The bundle's `Info.plist` sets `NSPrincipalClass = TangentScreenSaverView`.
  macOS instantiates one view per display inside its sandboxed
  `legacyScreenSaver` process.
- The saver links the same `WallpaperFactory`, `VideoWallpaper`, `ImageWallpaper`,
  `WebWallpaper` and `MPVWallpaper` classes as the app. There is no second
  renderer to drift out of sync.
- The app writes `~/Library/Application Support/Tangent/ScreenSaver/config.json`
  containing the whole `DisplayLayout` plus the path to the app's bundled
  libmpv. The plugin reads it, resolves the wallpaper for its own display ID and
  polls the file's modification date (throttled) so a live switch is reflected.
- Screen savers run sandboxed. macOS grants legacy savers a read-only
  filesystem exception, but TCC still protects Desktop, Documents, Downloads and
  iCloud Drive. `ScreenSaverStager` copies local media into
  `ScreenSaver/Media` and points the snapshot at those copies; when the app
  itself lives in a protected folder it stages the libmpv frameworks the same
  way. The plugin derives the real home from its own bundle path
  (`~/Library/Screen Savers/Tangent.saver`) instead of trusting the sandbox
  container's `NSHomeDirectory()`.
- `ScreenSaverService` owns the `~/Library/Screen Savers/Tangent.saver` copy and
  the one persisted on/off flag. Enabling copies the embedded saver and writes
  the config; disabling removes the copy. A failed install removes the partial
  bundle and leaves the switch off.
- Screen Saver playback is always muted. macOS owns the selected saver; Tangent
  installs and removes its bundle but does not change the user's choice in
  System Settings.

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
drafts and prereleases for stable builds, and picks an arm64 DMG, the only DMG,
or the release page. Nothing is downloaded, mounted, replaced or executed.

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

1. Compile the app for `arm64-apple-macos13.0`. Apple Silicon only: there is no
   `--universal` mode and no x86_64 slice.
2. Compile a second target, `Tangent.saver`, from the selected player and pack
   sources with `-emit-library -Xlinker -bundle` and the `ScreenSaver`
   framework, then sign it ad-hoc.
3. Assemble `Tangent.app` from `Resources/Info.plist`, the binary and the icon
   assets (`AppIcon.icns` for `CFBundleIconFile`, `BrandMark.png` for the About
   and popover mark).
4. Embed `Tangent.saver` in `Contents/Resources` so Screen Saver mode can install
   it without shipping source code or a compiler.
5. Bundle the libmpv closure unless `TANGENT_BUNDLE_LIBMPV=0`.
6. Ad-hoc sign inside out and verify.

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

`--test` runs 360 assertions with no test framework: JSON parsing, metadata and
property parsing, entry resolution, library scanning, type support, bridge
payloads, property copies, display layouts, gallery query/filter/cycling,
shortcut validation/persistence, GitHub release/update policy, diagnostics
privacy, the desktop-icon state machine, Screen Saver config/storage and
install/remove behaviour, the environment monitor and its pointer geometry, and
the arm64-only build.

Runtime checks that cannot run in-process are exposed as CLI flags:

| Flag | Purpose |
|---|---|
| `--probe-bridge <folder>` | loads a page and reports the property payload it received |
| `--snapshot-wallpaper <folder> <out.png> [js]` | renders a web pack at 3200×2000, optionally after a script such as `tangent.setDayPhase(0.745)` |
| `--probe-web-frames <folder>` | loads a web pack in the desktop-level host and reports frames, visibility and the environment state it received |
| `--probe-environment` | prints the ambient snapshot: pointer, day phase, audio presence, appearance, Reduce Motion and Low Power Mode |
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
2. Remote/HLS `videostream` playback.
3. Level or beat audio feed for audio-reactive packs (ScreenCaptureKit or a
   CoreAudio tap); the environment feed so far reports presence only.
4. Per-display property copies.
5. Developer ID signing and notarization.
6. Optional screen-saver configuration sheet and per-display saver overrides.
