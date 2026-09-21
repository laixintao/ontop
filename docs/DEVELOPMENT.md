# Development

[简体中文](DEVELOPMENT.zh-CN.md) · [Back to OnTop](../README.md)

## Requirements

- A Mac with macOS 14 or newer.
- Swift 6 and the macOS 15.2+ SDK: Xcode 16.2+ or compatible Apple Command Line Tools.
- Python 3.9+ for repository metadata, documentation checks, and release automation.
- A graphical login session for native window/rendering tests. The test suite does not request screen-recording, Accessibility, or Input Monitoring permission.

Install Command Line Tools with `xcode-select --install` if needed. When using full Xcode, complete its license/setup first. No paid Apple Developer account or third-party runtime package is required.

## Build and run

```bash
./scripts/build.sh Debug
open build/Debug/OnTop.app
```

The default build is `Release` for the host architecture. An optional second argument accepts `universal`, `arm64`, or `x86_64`; architecture-specific output lives in `build/Release-<architecture>/`. You can also open `OnTop.xcodeproj` and run the **OnTop → My Mac** scheme.

Quit a running development app before replacing its bundle. A new launch needs a fresh window selection; layout and opacity persist, sharing authorization does not.

## Architecture

| File | Responsibility |
| --- | --- |
| [`AppDelegate.swift`](../OnTop/AppDelegate.swift) | Menu bar with per-window actions, app lifecycle, source-app activation notifications |
| [`PinManager.swift`](../OnTop/PinManager.swift) | Shared picker ownership, per-stream routing, independent capture/preview pairs, deduplication, shutdown |
| [`CaptureController.swift`](../OnTop/CaptureController.swift) | One serialized stream lifecycle, generation guards, throttling, resize updates |
| [`PreviewPanelController.swift`](../OnTop/PreviewPanelController.swift) | Click-through picture, independent interactive controls, hover, geometry, opacity, preferences |
| [`FrameRenderer.swift`](../OnTop/FrameRenderer.swift) | Content-rect interpretation, bounded GPU crop pool, native sample-buffer display |

The picture window always ignores mouse events. Controls are independent nonactivating panels, so making them visible never turns the picture into an input blocker. Hover reads the pointer location at 20 Hz only while the preview is visible; it needs no global event tap.

Dragging temporarily makes the toolbar the parent of the picture and resize panel, then passes the grip's original mouse-down event to `NSWindow.performDrag(with:)`. WindowServer moves the group without per-event frame synchronization in OnTop. The existing pointer timer detects release because native dragging may consume `mouseUp`. Completion detaches the panels, applies pending source geometry, constrains the drop to the display, and saves the position. Hiding, stopping, resetting, or replacing the source also ends the group.

The toolbar sits above the picture and the resize handle sits to its right. Layout reserves screen space for both even when they are hidden, so hovering never moves or shrinks the picture. Hover corridors bridge the gaps without intercepting clicks. Temporary hiding is independent of source-app activation: it hides all preview panels and stops pointer polling, while capture continues. Only an explicit restore or source change clears it.

Each selection creates a separate capture/preview pair. Picker callbacks carrying a stream update only that pair; nil-stream selections add a reference. On macOS 15.2+, window IDs prevent duplicate references. Per-slot layout/opacity persist independently; new slots start tiled. Overlapping previews resolve hover through AppKit's own window-number list. Using a source app hides only its previews. One stream failing or stopping never deactivates the others' shared picker.

Capture uses a maximum of 15 fps and three queued frames. Ordinary frames remain zero-copy; frames with padding take the Core Image crop path. Cropping follows ScreenCaptureKit metadata, not pixel color. `contentRect` is measured in surface points; `scaleFactor` converts it to pixels. `contentScale` has already been applied and must not shrink it a second time.

## Checks

```bash
make check
./scripts/test.sh
./scripts/ci.sh
```

The complete CI command validates project files, builds the app, runs the native suite in English and Chinese, builds a universal app, and verifies ZIP/DMG round trips, signatures, architectures, resources, license, and checksums.

The native suite covers pixel crop orientation at 1×/2×/3×, black documents, malformed/empty frames, bounded crop allocations, actual WindowServer hit testing, native button events, nonactivating behavior, hover, opacity persistence, movement/resizing, 30 hide/restore cycles, video layer dimensions, reset, and teardown. Visual evidence is saved in `build/qa/`.

Native-drag tests intercept only the system drag entry point; they exercise AppKit's real parent/child movement, grouped hit testing, release without `mouseUp`, independent previews, source resizing, display placement, and interrupted gestures. They do not inject global mouse input or measure visible pointer-to-window latency. Verify smoothness with a real drag as part of manual acceptance.

Release tests use temporary local Git repositories and a fake `gh`. They exercise version bumps, annotated tags, atomic pushes, custom notes, dirty trees, remote conflicts, push failure/retry, draft recovery, and protection of published assets. They make no GitHub requests and do not alter the real repository.

For script and workflow lint:

```bash
brew install shellcheck actionlint
shellcheck scripts/*.sh
actionlint
```

GitHub CI runs this on Apple Silicon and Intel runners. Warnings are build errors, including complete Swift concurrency checking. Failed jobs still upload any available visual evidence.

## Manual acceptance

Automated tests use synthetic frames. The real sharing picker and other apps still need a short hands-on check:

- Choose a browser page or PDF. Read static text, scroll the original, and verify live updates.
- Add a second window using **Add Window…**, including through macOS's sharing menu. Check independent content, move/resize/opacity, source switching, cancel/replace, and stopping just one preview. Repeat with two windows from the same app.
- Work through the preview: click, scroll, and select text underneath it. Hover controls should remain usable without taking keyboard focus.
- Drag the grip rapidly within one screen, then to each screen edge and across displays. Compare responsiveness with a normal macOS window. Release outside the preview, then immediately resize or hide/restore it; check for jumps, stuck controls, or lost position. Controls must stay outside the picture and remain visible while crossing the gaps.
- Hide one preview, switch apps, and verify it stays hidden while other previews continue. Restore it from its menu or **Show All Previews**; position, size, and opacity should be preserved.
- Return to the source app, switch away repeatedly, and resize the original. Confirm no accumulating borders, scale drift, or duplicate previews.
- Change opacity, move, resize, relaunch, and recover with **Reset Preview Size**.
- Cancel a source change. Stop while hidden or while a stream is starting. Reselect afterward.
- Close/minimize the source, stop sharing via macOS, and switch Spaces, native fullscreen, and Retina/non-Retina displays.

## Localization and visuals

Update both `OnTop/Resources/en.lproj/Localizable.strings` and `OnTop/Resources/zh-Hans.lproj/Localizable.strings`. Keep both READMEs in sync for user-visible changes.

The README scene is a code-drawn illustration using sample content. Its controls are snapshots of the actual app. Regenerate the illustration with `python3 scripts/make-showcase.py`; refresh control PNGs from `build/qa/` after running tests. Do not use private documents for repository assets.

Regenerate the app icon with `xcrun swift scripts/MakeIcon.swift` from the repository root. Generated app builds, installers, and test output are ignored by Git.
