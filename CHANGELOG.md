# Changelog

All notable changes to Tangent are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
semantic versioning once it reaches 1.0.

## [0.4.1] — 2026-10-28

### Added

- Click-to-record shortcut rebinding in **Settings ▸ Shortcuts**, with per-action
  defaults, **Reset All Shortcuts**, and inline validation messages.
- `KeyBinding` model with Control/Option requirement, modifier-only and Escape
  rejection, and duplicate detection against both current and default bindings.
- Persisted custom bindings (`tangent.hotkeys.bindings`) with sanitization of
  corrupt or conflicting stored values on launch.
- `--hotkey-status` reports current bindings, defaults and customised actions.
- Menu-bar shortcut labels reflect live bindings and mark customised actions.

### Changed

- Settings window grows to `600×470` to fit the recorder controls.
- Recording cancels when the window resigns key or the pane changes.
- A binding that saves but fails to register reports the conflict explicitly.

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
