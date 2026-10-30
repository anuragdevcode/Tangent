# Changelog

All notable changes to Tangent are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
semantic versioning once it reaches 1.0.

## [0.4.1] — 2026-10-29

### Added

- AppKit-native library window: a source-list sidebar (All Wallpapers,
  Favorites, Video, Web, Images, Displays, Automation, About), an adaptive 16:10
  gallery with hover previews and a current-desktop badge, and a collapsible
  300 pt inspector.
- Menu bar popover with the active wallpaper, play/pause, per-display pills,
  quick switches for playback rules and mute, and Preferences, support and Quit.
- In-window Displays, Automation and About pages. The inspector steps aside on
  pages that do not describe one wallpaper and returns where it was afterwards.
- Card context menu: set for this screen, set for all screens, duplicate, show in
  Finder and remove from library. Removal only hides the pack; the file on disk
  is never touched, and **Restore** brings it back from Settings.
- Favorites and a hidden-pack store, so removed wallpapers can be brought back
  from Settings.
- `⌘1`/`⌘2` navigation, Space live preview, `⌘,` Settings and `⌘W` close in the
  library window.
- Click-to-record shortcut rebinding in **Settings ▸ Shortcuts**, with per-action
  defaults, **Reset All Shortcuts**, and inline validation messages.
- `KeyBinding` model with Control/Option requirement, modifier-only and Escape
  rejection, and duplicate detection against both current and default bindings.
- Persisted custom bindings (`tangent.hotkeys.bindings`) with sanitization of
  corrupt or conflicting stored values on launch.
- `--hotkey-status` reports current bindings, defaults and customised actions.
- `--snapshot-popover` renders the menu bar popover to a PNG for layout checks.
- In-app Ko-fi support: a `WKWebView` window hosts the real
  `ko-fi.com/anuragcodes` page, with a spinner, an offline retry state and
  **Open in Browser**. Ko-fi's JavaScript button and iframe embeds are not used
  because they only open the profile page or render blank outside ko-fi.com.
- `--probe-kofi` opens that window in a fresh session and reports the page
  title, login state and visible text.
- Menu-bar shortcut labels reflect live bindings and mark customised actions.

### Changed

- Support moved in-app: the About actions, support card and popover heart open
  the project's Ko-fi page in a native window instead of a Buy Me a Coffee tab.
  The button carries Ko-fi's brand colour rather than the app accent.
- The menu bar popover is one compact 340 pt column: a hero preview, a single
  action row, one display row and the pause/mute switches. The type badge, the
  display-count line and the wallpaper title repeated inside a display row are
  gone, and the footer sits closer to the quick switches.
- Inspector actions share a 28 pt height and a consistent 8 pt stack, with
  clearer separation before the details table. Packs without an author no longer
  repeat their type under the title.
- The gallery, inspector, Settings and About windows share one theme: solid
  canvas and pane fills, 1 pt inner borders, continuous radii, SF Symbols and
  spring hover motion. Window-wide vibrancy is gone; only the sidebar samples
  the window, so wallpapers can no longer tint the interface.
- The Settings window grows to `620×560`; the library window is `1140×760` with
  a `900×660` minimum.
- Displays, Automation and About manage their own copy; the inspector is
  restored when returning to the library.
- Recording cancels when the window resigns key or the pane changes.
- A binding that saves but fails to register reports the conflict explicitly.

### Fixed

- A capsule view with a very large continuous corner radius no longer paints a
  window-sized smear of its tint.
- The inspector's **Paused** badge only appears for the wallpaper that is
  actually running.
- Section pages no longer resize the window when the inspector collapses.
- The sidebar search placeholder no longer disappears when a page takes focus.
- The automation status card says **No wallpaper set** instead of reporting a
  pause reason when nothing is applied.
- The inspector's **Preview** pill keeps its `92×26` frame when it flips to
  **Pause**; the label no longer changes the control's width.
- The menu bar popover no longer widens to 512 pt when a thumbnail loads or a
  display name contains `(Main)`.
- Status capsules keep their intrinsic width in the Settings playback card and
  the Automation page instead of stretching across the row.
- The library opens with the gallery focused, so the search field no longer
  shows a stray caret at launch.
- The compatibility suite scans a scratch root instead of the user's real
  library, so a locally installed wallpaper can no longer change its counts.

## [0.4.0] — 2026-10-27

### Added

- Searchable, filterable gallery with a details bar and explicit apply
  (double-click, Return, or **Apply**).
- Gallery search across title, author, summary, tags and folder name; type
  filters (All / Video / Web / GIF & Image / Unsupported).
- Selection preservation across search, filter changes and rescans.
- Next/previous wallpaper cycling that skips unsupported packs.
- Global shortcuts via Carbon: pause/resume, next wallpaper, open library, stop.
- Four-pane Settings window (General, Playback, Shortcuts, About).

### Changed

- The former library window became the gallery.
- Settings uses a segmented header instead of `NSTabView`, which rendered as a
  blank strip in offscreen snapshots.

## [0.3.0] — 2026-10-27

### Added

- libmpv backend for VP9, VP8, AV1, WebM, Matroska, AVI, OGV and FLV.
- Codec-aware routing: H.264/HEVC to AVFoundation, everything else to libmpv,
  with a single automatic AVFoundation → libmpv retry.
- Runtime libmpv loading with an explicit `TANGENT_LIBMPV` override.
- libmpv/ffmpeg bundling script: 50 dylibs, install-name rewriting, inside-out
  signing, license collection.
- `--probe-mpv` and `--report-frames` diagnostics.

## [0.2.0] — 2026-10-27

### Added

- Wallpaper-pack support: metadata and control-file parsing, six playable types,
  explicit reasons for unsupported types.
- Library scanning with in-place references and individually added entries.
- Per-display layouts keyed by display ID.
- Playback rules: pause on fullscreen app, battery power or screen lock.
- Live control panel for all eight control types.
- Thumbnail generation, including video frame extraction.
- `--test` compatibility suite, `--probe-bridge` and snapshot flags.

## [0.1.0] — 2026-10-27

### Added

- Desktop-level click-through window behind the icons.
- MP4/H.264 video, web, GIF and image wallpapers.
- Menu-bar shell with open, pause, resume and stop.
- Saved wallpaper restored on launch.
- `--set`, `--library` and `--selftest` CLI entry points.
