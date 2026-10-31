# Tangent

A native wallpaper engine for macOS on Apple Silicon. Tangent renders animated
video, web, GIF and image wallpapers in a click-through window behind the
desktop icons, and keeps a library of wallpaper packs with per-display
assignments, playback rules and live controls.

- No Dock icon, no focus stealing, no desktop modification.
- Hardware-decoded H.264/HEVC through AVFoundation, plus VP9, AV1 and Matroska
  through a bundled libmpv.
- Reads the widely used v1 wallpaper-pack format, including its control surface.
- Global shortcuts, a menu bar popover, a library window with an inspector and a
  four-pane Settings window, all built with AppKit only.
- A desktop-icon switch in the popover and Automation page, so the wallpaper can
  take the whole desktop without touching any files.

## Requirements

- Apple Silicon Mac (M1 or newer); the build targets `arm64` with a minimum of
  macOS 13.0
- Command Line Tools (`swiftc`); full Xcode is not required
- Homebrew `mpv` (`brew install mpv`) — **build-time only**. Its headers are
  needed to compile, and `build.sh` copies libmpv plus its 50-library dependency
  closure (about 61 MB) into `Tangent.app/Contents/Frameworks`. The built app
  does not need Homebrew at runtime for VP9/WebM, AV1 or Matroska.

## Build

```bash
./build.sh              # arm64 native
./build.sh --universal  # arm64 + x86_64
```

Output: `build/Tangent.app` (~63 MB, of which ~61 MB is the bundled libmpv
closure and codecs).

`TANGENT_BUNDLE_LIBMPV=0 ./build.sh` skips bundling for a quick ~2 MB build that
uses Homebrew's libmpv at runtime.

## Run

```bash
open build/Tangent.app
```

A menu bar icon appears. Clicking it opens a compact popover with the current
wallpaper, play/pause, the per-display state and the quick toggles for pause,
mute and desktop icons. From the menu:

- **Library…** (⌘L) — the library window: browse by section, search, favorite,
  inspect and apply wallpapers
- **Open Wallpaper…** (⌘O) — open a pack folder, a video, a GIF, an image or an
  `.html` file
- **Next Wallpaper** — advance the screen's wallpaper through the library's
  playable packs; a display pinned with **Set for This Screen** advances its own
  assignment
- **Wallpaper Properties…** (⌘P) — adjust the active pack's controls live
- **Displays ▸** — per-display assignment
- **Playback Rules ▸** — pause on fullscreen apps, battery or screen lock
- **Hotkeys ▸** — turn global shortcuts on or off and see which registered;
  rebind them in Settings
- **Help & Community ▸** — **Check for Updates…**, **Report an Issue…**,
  **Community & Discussions** and **Star Tangent on GitHub**
- **Settings…** (⌘,) — General, Playback, Shortcuts and About & Feedback panes
- **Pause / Resume / Stop**

The layout is saved and restored on the next launch.

## Library

The library scans folders for wallpaper packs — a folder containing the pack's
metadata file. Add packs individually, or point the library at a folder of
packs. **Add Wallpaper…** accepts several files at once and the gallery accepts
drops, so videos, images, GIFs, web pages and pack folders can all go in
together. Bare files are tracked by their own path, which means two videos in
one folder stay two wallpapers. Folders are **referenced in place**: nothing is
copied into the app, so a wallpaper you edit stays edited, and removing it from
the library does not delete your files.

Default library folder: `~/Library/Application Support/Tangent/Library`

The gallery has a sidebar, an adaptive card grid and a collapsible inspector.
The sidebar groups **All Wallpapers**, **Favorites**, **Video**, **Web** and
**Images**, and carries the search field (title, author, summary, tags and folder
name), the **Displays**, **Automation** and **About Tangent** pages, and a footer
with Settings. The grid fits 16:10 cards to the window width with even gutters;
hovering lifts a card and starts a muted preview, and wallpapers currently on
the desktop carry a glow badge. Double-click, press Return, or use the card's
context menu to apply.
**Space** toggles the inspector's live preview, **⌘1** returns to the library,
**⌘2** opens Displays and **⌘,** opens Settings.

Selecting a card fills the inspector: a preview with **Preview**, favorite, type,
title and author, a pause badge when the engine is paused, and the details
(type, size, version, location) plus the actions. Displays, Automation and About
do not describe one wallpaper, so the inspector steps aside there and returns
where it was when you go back. The toolbar button or the inspector's close
button collapses it.

Applying is explicit, so browsing cannot replace the desktop by accident.
Search, section and rescan keep the current selection while it is still visible.
Cards show the pack thumbnail, or a frame extracted from the video for packs
that ship without one. Unsupported packs stay visible, dimmed, with the reason
shown instead of failing silently at apply time.

Removing a wallpaper is a library operation, never a file operation: **Remove
from Library** hides the pack and **Settings ▸ General ▸ Hidden Wallpapers ▸
Restore** brings it back. The card menu also offers **Set for This Screen**,
**Set for All Screens**, **Duplicate** and **Show in Finder**.

## Wallpaper types

| Type | Backend |
|---|---|
| `video` | AVFoundation (`AVPlayerLayer`) for H.264/HEVC; libmpv (OpenGL) for VP9/WebM/AV1/Matroska |
| `web`, `webaudio`, `url` | `WKWebView` |
| `gif` | `NSImageView` (native frame timing) |
| `picture` | `NSImageView` |

Unsupported, with an explicit reason in the UI: `app`, `unity`, `unityaudio` and
`godot` (they run a foreign application and reparent its window into the
desktop), `bizhawk` (emulator integration is Windows-only) and `videostream`
(remote/HLS playback is not wired up yet). Unknown types from a newer pack
format are preserved and marked unsupported rather than crashing.

## Pack format

Tangent reads the v1 wallpaper-pack format. Packs are plain directories, and the
app parses their metadata with the format's own field names:

- `Title`, `Author`, `Desc`, `License`, `Contact`, `Tags`, `Thumbnail`,
  `Preview`, `AppVersion`, `Version` and `Id` are read as metadata.
- `FileName` is resolved relative to the pack folder, unless `IsAbsolutePath` is
  true (or the value is an absolute path / `http(s)` URL).
- A `web` or `webaudio` pack with no `FileName` falls back to `index.html`.
- All twelve type names are recognised, plus an `unknown` fallback.

The concrete on-disk filenames are declared in one place,
[`Sources/Tangent/Packs/PackFormat.swift`](Sources/Tangent/Packs/PackFormat.swift),
so the rest of the codebase never hard-codes them.

The optional control file drives live settings. On page load, each control's
default value is delivered to the page as:

```js
window.tangentPropertyListener(name, value)
```

Packs that implement the older listener name are also supported. All eight
control types work: `slider` (number), `textbox` (string), `dropdown` (index
number), `checkbox` (bool), `color` (string) and `folderDropdown` (file name, or
`null` when the file is absent), plus `button` and `label`, which are
user-interaction only and never pushed on load.

**Wallpaper Properties…** opens an editor for those controls. Changes are pushed
immediately (`button` sends `true`, a `label` sends nothing, a `folderDropdown`
sends the file name or `null`). Values are stored in a *copy* of the control file
under `~/Library/Application Support/Tangent/Properties/<pack>-<hash>/`, never in
the pack itself. **Reset to Defaults** deletes the copy and re-pushes the pack's
own values.

## Displays

Every connected display gets its own desktop-level window and player.
**Displays ▸** assigns per screen:

- **Use Default Wallpaper** — follow the globally applied wallpaper
- **Pin Current Wallpaper Here** — keep this display on its own wallpaper when
  the default changes
- **Turn Off This Display** — leave this screen bare
- **Reset Per-Display Layout** — back to one wallpaper everywhere

Assignments are keyed by `CGDirectDisplayID`, so they survive restarts and
reconnects.

## Playback rules

Applied to every player, with independent reason tracking (a manual pause is not
undone when a fullscreen app closes):

- pause when an app covers the main display (detected via
  `CGWindowListCopyWindowInfo`)
- pause on battery power (`IOPSGetProvidingPowerSourceType`)
- pause when the screen locks or sleeps (`com.apple.screenIsLocked`,
  `NSWorkspace` sleep notifications)

## Global shortcuts

Off by default. Turn them on from **Hotkeys ▸ Enable Global Shortcuts** or
Settings ▸ Shortcuts; the choice persists across launches.

| Shortcut | Action |
|---|---|
| `⌃⌥Space` | Pause / resume |
| `⌃⌥→` | Next wallpaper |
| `⌃⌥L` | Open the library |
| `⌃⌥.` | Stop the wallpaper |

Rebind from **Settings ▸ Shortcuts**: click a shortcut and press the new
combination. Escape cancels, Delete restores that action's default, and **Reset
All Shortcuts** restores everything. A shortcut must include Control or Option
and cannot duplicate another action's current or default combination;
modifier-only combinations and Escape are rejected. Bindings persist in
`UserDefaults`; when shortcuts are enabled they re-register immediately.

Shortcuts work while another app is frontmost. They use Carbon's
`RegisterEventHotKey`, so no Accessibility or Input Monitoring permission is
required. Registration is per shortcut: if another app already owns one
combination, the rest still work and Settings names the unavailable action.

## Settings

**Settings…** (⌘,) has four panes:

- **General** — wallpaper count, library folder, and shortcuts to open the
  gallery, add a wallpaper, or reveal the library in Finder
- **Playback** — the three pause rules above
- **Shortcuts** — enable/disable global shortcuts, click-to-record rebinding
  with conflict checks, reset-all, and registration status
- **About & Feedback** — live version/build, macOS and hardware information,
  update status, help routes and community links, plus the in-app Ko-fi tip
  window

## Desktop icons

The popover has a **Hide Desktop Icons** switch, and the same switch appears in
the library under **Automation ▸ Shortcuts**. Turning it on hides every item
Finder draws on the desktop so the wallpaper can fill the screen; turning it off
brings the icons back.

macOS has no public desktop-icon API, so Tangent changes Finder's own
`com.apple.finder` → `CreateDesktop` preference and asks Finder to relaunch. The
relaunch is brief, and Finder windows and open files are not touched. The switch
reflects the preference Finder actually has, not a separate saved flag, and is
re-read whenever the popover or Automation page opens. If the preference cannot
be read or written, the row stays in place and explains the failure instead of
showing a false state.

## Updates, diagnostics and community

Tangent talks to one repository only: the official
[`anuragdevcode/Tangent`](https://github.com/anuragdevcode/Tangent). The owner,
name, release API, issue form, Discussions and repository URLs live in
`Services/GitHubConfig.swift`.

**Updates.** On an ordinary launch the app makes one conditional request to
`https://api.github.com/repos/anuragdevcode/Tangent/releases/latest`, at most
once every 24 hours. The last successful release and its `ETag` are cached, so a
`304 Not Modified` can reuse them without another download. **Check for
Updates…** bypasses the interval but never runs two requests at once. States are
shown in place — Idle, Checking, Up to Date, Update Available, Offline, Rate
Limited, Failed — never as an alert.

Version tags are compared as semantic versions, with or without a leading `v`,
including prerelease identifiers; build metadata is ignored for ordering.
Drafts and prereleases are never advertised to a stable build. When a newer
stable release exists, Tangent chooses a download in this order: a universal
`.dmg`, a `.dmg` matching the current architecture, the only `.dmg` in the
release, or the GitHub release page. It only opens that official URL; it never
downloads, mounts, replaces or executes anything.

**Diagnostics.** **Report an Issue…** shows a privacy preview first. The summary
contains only the Tangent version and build, the macOS version, `hw.model`, the
running architecture and Rosetta status when available. It never includes a
serial number, Apple ID, username, home path, IP address, installed-app list or
any file, and nothing is transmitted automatically. Because GitHub issue forms
ignore prefilled `body` parameters, the link carries only the template and
title; the summary is copied to the clipboard for the form's Diagnostics field.
**Copy Diagnostics** is available separately without leaving the app.

The form itself lives in
[`.github/ISSUE_TEMPLATE/bug_report.yml`](.github/ISSUE_TEMPLATE/bug_report.yml).
**Community & Discussions** opens the repository's Discussions page for
wallpaper sharing, feature suggestions and general feedback.

## Scripted use

```bash
BIN=./build/Tangent.app/Contents/MacOS/Tangent

# Apply a wallpaper pack or bare file
$BIN --set ~/Wallpapers/aurora

# Apply it to display 2 only, without touching the saved layout
$BIN --set ~/Wallpapers/aurora --display 2 --ephemeral

# Open the library window at launch
$BIN --library

# Compatibility test suite (parsers, bridge payloads, library, gallery, hotkeys,
# layouts, releases, diagnostics and desktop icons)
$BIN --test

# Prove all four shortcuts register; does not change the saved preference
$BIN --hotkey-status

# Prove control defaults reach a live page
$BIN --probe-bridge Tests/Fixtures/library/landing-web

# Decode and render VP9/WebM/AV1 through libmpv; prints codec, size and frame count
$BIN --probe-mpv Tests/Fixtures/media/vp9.webm

# Open the real support window in a fresh session and report its page state;
# an optional path also writes a snapshot of the rendered page
$BIN --probe-kofi /tmp/kofi.png

# Point at a specific libmpv build (also useful to test the "missing" path)
TANGENT_LIBMPV=/opt/homebrew/opt/mpv/lib/libmpv.2.dylib $BIN --probe-mpv loop.webm

# Apply a VP9 wallpaper, then print frames rendered by the desktop-level window
$BIN --set Tests/Fixtures/media/vp9.webm --ephemeral --report-frames 4

# Press Next Wallpaper once against the live layout and report every display's
# wallpaper before and after, then quit (never saves)
$BIN --ephemeral --probe-advance 2

# Render the library window / control panel / Settings to PNGs (no Screen Recording permission)
$BIN --snapshot-library /tmp/library.png
$BIN --snapshot-library /tmp/gallery.png --gallery-search aurora --gallery-select 0
$BIN --set ~/Wallpapers/aurora --snapshot-properties /tmp/properties.png
$BIN --snapshot-settings /tmp/settings.png --settings-pane 2   # 0 General … 3 About & Feedback
$BIN --snapshot-popover /tmp/popover.png

# Headless machine/display report
$BIN --selftest
```

`--selftest` prints architecture, macOS version, screens, desktop/icon window
levels, supported types and the library path as JSON.

## How it works

macOS has no desktop-parent window, and no `SetParent`. Instead the WindowServer
exposes window levels:

```
-2147483623  kCGDesktopWindowLevel      static desktop picture
-2147483622  ← Tangent's wallpaper window
-2147483603  kCGDesktopIconWindowLevel  desktop icons
```

`WallpaperWindow` is a borderless, click-through, non-activating `NSWindow` at
`desktopWindow + 1`, with
`collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]`
so it persists across Spaces and Mission Control while never taking focus. The
WindowServer owns the desktop lifecycle, so there are no shell hooks or crash
recovery to manage.

See [`ARCHITECTURE.md`](ARCHITECTURE.md) for the component map, playback routing
and libmpv bundling details.

## Project layout

```
Sources/Tangent/
  main.swift                 entry point and CLI flags
  AppDelegate.swift          menu bar shell, library/display/settings menus, hotkey actions
  WallpaperEngine.swift      desktop core: one window + player per display
  WallpaperWindow.swift      desktop-level NSWindow
  DisplayLayout.swift        per-display assignments + display identity
  Wallpaper.swift            Wallpaper protocol, factory, config
  VideoWallpaper.swift       AVFoundation backend (H.264/HEVC)
  MPVWallpaper.swift         libmpv + OpenGL backend (VP9/WebM/AV1)
  VideoRouting.swift         picks AVFoundation or libmpv per file
  WebWallpaper.swift         WKWebView backend + property bridge
  ImageWallpaper.swift       GIF / picture backend
  WallpaperStore.swift       layout persistence (with v1 migration)
  Playback/PlaybackMonitor.swift  fullscreen / battery / lock rules
  Hotkeys/HotkeyManager.swift     Carbon global shortcuts, rebinding, dispatch
  Services/GitHubConfig.swift    official repository URLs and safe link opening
  Services/ReleaseModel.swift    release models, semver, asset selection, update policy
  Services/UpdateChecker.swift   conditional release lookup, cache, 24h schedule, states
  Services/FeedbackManager.swift sysctl diagnostics, privacy summary, issue URL
  Services/DesktopIcons.swift    Finder desktop-icon preference and relaunch
  Packs/                     pack format, metadata/property parsing, library
                             scanning, thumbnails, JSON tree, property store
  UI/                        AppKit library (sidebar, gallery, inspector), menu bar
                             popover, Settings, About & Feedback, in-app Ko-fi
                             support, control panel, theme and shared components
  Diagnostics/SelfTests.swift     301-check compatibility and service suite
Tests/Fixtures/              pack and media fixtures used by the tests
Resources/Info.plist
.github/ISSUE_TEMPLATE/      bug-report issue form and contact links
Scripts/bundle-libmpv.py     copies and rewrites the libmpv dylib closure
build.sh
```

## Verification

Built and observed on an M2 running macOS 27.0.1:

| Check | Result |
|---|---|
| Mach-O architecture (REA `inspect_macho`) | `arm64`, single slice, min macOS 13.0, SDK 27.0 |
| Third-party dylibs | none linked; `libmpv` is loaded at runtime with `dlopen` only when a VP9/WebM/AV1 file needs it |
| Bundled library closure | 50 dylibs, 61 MB in `Contents/Frameworks`; every install name rewritten to `@rpath`, all references resolve inside the bundle |
| Bundle signature | `codesign --verify --deep --strict` passes with ad-hoc signatures |
| Compatibility suite (`--test`) | `PASS — 301 checks` |
| Next Wallpaper (`--probe-advance`) | through the real button/hotkey path: a pinned display advanced in place (`celestial-veil…` → `LiveWallpaper`) while the default stayed `logo-mark`; an unpinned display advanced the default (`logo-mark` → `celestial-veil…`); the run never wrote the layout |
| Version | `0.5.0` (build `6`) |
| Binary | `sha256 69a991b34837743ea6c8043ac86ed2f8ef6a9ea93e0bacda3de0fb869fb98501`, arm64 |
| Property bridge (`--probe-bridge`) | page receives `speed=1.5`, `mode=1`, `flip=true`, `tint="#112233"`, `image="present.jpg"`, `missingImage=null`; `button`/`label` omitted |
| Wallpaper window layer | `-2147483622`, full screen, `alpha 1` |
| Library window | one `1140×760` window at layer `0` (minimum `900×660`), plus the wallpaper window |
| Library additions | two videos in one folder stay two entries with distinct ids; adding a folder discovers the videos inside; 5 assertions |
| App icon | `AppIcon.icns` uses the official mark full-bleed (1024 px, all sizes) and `CFBundleIconFile` names it; About and the popover use the same mark from `BrandMark.png` |
| Menu bar popover (`--snapshot-popover`) | a stable `340×559` surface across runs: hero preview, one action row, one display row and the pause/mute/desktop-icon switches; width stays `340` with a 512 pt thumbnail and a `(Main)` display name |
| Desktop icons (`--test`) | 23 assertions cover switch target/action wiring, read failure, write failure, busy/finish transitions, Finder-relaunch sequencing, hide/show round-tripping and refresh recovery; the real `defaults write/read com.apple.finder CreateDesktop` round-trip was checked and the original missing key restored |
| Library sections (`--library-section 1/5/6/7`) | Favorites, Displays, Automation and About & Feedback render at the same window size; the inspector steps aside and the sidebar keeps its search placeholder |
| Automation desktop icons (`--snapshot-library --library-section 6`) | the **Shortcuts** card shows Global Shortcuts and Hide Desktop Icons in the same row style with the Finder-restart explanation; the busy-state disabling is covered by the service tests |
| About & Feedback surfaces (`--snapshot-settings --settings-pane 3`, `--snapshot-library --library-section 7`) | identity, version/build, live update card, help and community cards render together in Settings and the library; the standalone About window uses the same page |
| Update/diagnostics suite (`--test`) | semver with prereleases, drafts, asset selection, HTTP 304/403/404/429/500, offline errors, a mocked `URLSession` request, 24-hour scheduling, diagnostic fields/fallbacks/Rosetta, privacy exclusions and issue-URL encoding |
| GitHub endpoint (`curl`) | `releases/latest` resolves to `v0.5.0` and serves `Tangent-0.5.0-arm64.dmg`; the landing page's download CTAs use that exact asset URL |
| Gallery selection (`--gallery-select 0`) | inspector shows the preview, type badge, title/author, details (type, size, version, location) and actions; **Set for This Screen** stays disabled for unplayable packs |
| Inspector preview pill | keeps its `92×26` frame while the title flips **Preview** ↔ **Pause**, so the control never resizes mid-click |
| Status capsules | keep their intrinsic width in the Settings playback card and the Automation page instead of stretching to fill the row |
| Gallery empty state (`--gallery-search zzzz`) | "No Wallpapers Match" over an empty grid, with a **Clear Search** action |
| Gallery/hotkey unit tests | 50 assertions: search across title/author/summary/tags/folder, five filters, combined search+filter, wrapping next/previous cycling that skips unsupported packs, shortcut uniqueness/dispatch, rebinding validation, persistence and reset |
| Global shortcuts (`--hotkey-status`) | all 4 default bindings register (handler status 0) while the saved preference stays off |
| Ko-fi support window (`--probe-kofi`) | a fresh session loads `https://ko-fi.com/anuragcodes` in the real 460×752 window: title `Buy Anurag Singh a Coffee`, visitor view (not logged in), page text present |
| Custom binding registration | a throwaway suite rebinds Open Library to `⌃⌥⇧K`; all 4 actions register, 0 failures |
| Settings panes (`--snapshot-settings --settings-pane 0..3`) | General, Playback, Shortcuts (recorder buttons + reset) and About all render in dark mode |
| Control panel (`--snapshot-properties`) | all 9 fixture controls rendered; slider/checkbox/dropdown/file/colour values correct |
| Customised properties | edited copy drives the page (`speed=3.5`, `caption="Customised"`); original pack file unchanged |
| libmpv VP9/WebM (`--probe-mpv`) | codec `Google VP9`, 640×360, 11 frames rendered, render error 0 |
| libmpv VP9-in-MP4 | codec `Google VP9`, 640×360, 13 frames rendered, render error 0 |
| libmpv AV1-in-MP4 | codec `Alliance for Open Media AV1`, 640×360, 10 frames rendered, render error 0 |
| Desktop VP9 wallpaper | window at layer `-2147483622`, 6.6% CPU while playing |
| Desktop VP9 frames (`--report-frames`) | 123 frames in 4 s (~30 fps), codec `Google VP9`, render error 0 |
| Desktop AV1 frames | 125 frames in 4 s, codec `Alliance for Open Media AV1`, render error 0 |
| VP9 1080p | 1920×1080, 10 frames rendered, ~20% CPU on M2 |
| Video routing | H.264→AVFoundation; WebM, VP9-in-MP4, AV1-in-MP4→libmpv (8 assertions) |
| Bundled libmpv | `--probe-mpv` reports `library` = `Tangent.app/Contents/Frameworks/libmpv.2.dylib` |
| Homebrew-independent | with `/opt/homebrew/opt/mpv/lib/libmpv.2.dylib` moved away: VP9 probe 11 frames, AV1 desktop 91 frames, H.264 wallpaper still at layer `-2147483622` |
| libmpv missing | `TANGENT_LIBMPV` override to a missing path reports the install hint and fails; the app still runs H.264/HEVC |
| Universal build | `x86_64 arm64` executable; bundled libmpv is `arm64` only, with a build-time warning |
| Unsupported pack | exits `3` with the Windows-reparenting reason |
| Display layout | default/pin/disable/reset, `UserDefaults` round-trip, v1 migration |

## Known limitations

- **Bundled libmpv keeps the bottle's OS floor.** The app binary is min macOS
  13.0 and launches there, but the bundled libmpv and ffmpeg dylibs declare
  **macOS 27.0**. On macOS 13–26 they are refused by dyld, so H.264/HEVC still
  plays while VP9/AV1 needs a libmpv built with an older deployment target
  (`TANGENT_LIBMPV=/path/to/libmpv.2.dylib`). Removing the floor requires
  rebuilding mpv/ffmpeg from source against the older SDK.
- **The `x86_64` slice has no libmpv.** `--universal` bundles the arm64 Homebrew
  dylibs, so under Rosetta the app can play H.264/HEVC but not VP9/AV1.
- **No spanning.** Displays are separate Spaces-backed screens; one wallpaper
  cannot stretch across two monitors. Per-display wallpapers are supported
  instead.
- **No host audio feed.** Web wallpapers that draw their own animation work, but
  system-audio-reactive packs expect an audio stream that is not wired up yet.
  That needs ScreenCaptureKit audio (macOS 13+) or a CoreAudio process tap.
- **No system-information feed** for packs that request hardware stats.
- **Control values are per pack, not per display.** A pack shown on two displays
  shares one set of values.
- **Global shortcuts require Control or Option.** Shift-only and Command-only
  combinations are rejected so a global binding cannot shadow ordinary menu
  shortcuts. Shortcuts are off by default.
- **No screensaver** and no visual metadata editor.
- Video wallpapers are muted by default.
- Ad-hoc signed. Distributing to other machines needs Developer ID +
  notarization.

## License

GPL-3.0. See [`LICENSE`](LICENSE). Bundled third-party libraries and their
licenses are listed in `Tangent.app/Contents/Resources/Licenses`.
