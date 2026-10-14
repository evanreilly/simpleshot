# SimpleShot

SimpleShot is a native macOS menu-bar screenshot utility written in Swift and SwiftUI.

## Installation

Requires **macOS 14 or later** and **Xcode 16 or later** (Swift 6). There is currently no notarized binary release; install by building from source. The build targets your Mac’s architecture.

1. Install and open Xcode to finish its setup. Select Xcode under **Xcode → Settings → Locations → Command Line Tools**.
2. Add your Apple account under **Xcode → Settings → Accounts → Manage Certificates**, and create an **Apple Development** certificate if needed.
3. Clone and build, replacing the example signing identity with your certificate’s exact name:

   ```sh
   git clone https://github.com/evanreilly/simpleshot.git
   cd simpleshot
   security find-identity -v -p codesigning
   SIGNING_IDENTITY='Apple Development: Your Name (CERTIFICATE ID)' ./Scripts/build-app.sh
   ```

4. Install and launch:

   ```sh
   mkdir -p "$HOME/Applications"
   ditto build/SimpleShot.app "$HOME/Applications/SimpleShot.app"
   open "$HOME/Applications/SimpleShot.app"
   ```

SimpleShot lives in the **menu bar**, not the Dock. Open **Settings…** from its menu to finish setup:

- Use **Request Screen Access**, then enable SimpleShot under **System Settings → Privacy & Security → Screen Recording** (or **Screen & System Audio Recording**, depending on macOS version). Quit and reopen if macOS requests it.
- Under **Keyboard → Keyboard Shortcuts → Screenshots**, disable Apple’s conflicting ⌘⇧3 and ⌘⇧4 shortcuts. SimpleShot does not change them automatically. Resolve any other app’s ⌘⇧2 conflict too, then click **Check Shortcuts** in SimpleShot Settings.
- Choose your screenshot folder. **Change Default Location** in the preview changes and remembers it.
- Allow Finder control under **Privacy & Security → Automation** when prompted to enable Finder list view and sorting. This is separate from Screen Recording. Screenshot shortcuts do not need Accessibility permission.

### Updating

Quit SimpleShot, run `git pull --ff-only`, rebuild with the **same signing certificate**, then repeat the install and launch commands. Keep the same app location and certificate to avoid unnecessary Screen Recording permission resets. See **Build an app bundle** below for signing details and a disposable ad-hoc build option.

### Shortcuts

| Shortcut | Action |
| --- | --- |
| ⌘⇧4 | Capture a region, save it, and copy it to the clipboard. |
| ⌘⇧3 | Reopen the last screenshot with its editable annotations. |
| ⌘⇧2 | Draw and adjust a precision capture frame; Enter confirms. |

## Current behavior

- Precision capture edges resize on a single axis: left/right use the horizontal resize cursor, top/bottom use the vertical resize cursor. Hover and dragging share a generous edge target; corners retain priority for two-axis resizing.
- **⌘⇧2** opens precision capture: draw a region, resize any of its four corners or drag elsewhere on that display to move it, then press Enter or click the attached Capture button. Once drawn, the cursor stays an open hand; clicking elsewhere cannot replace the frame. Press **⌘⇧2 again** to reset and draw a fresh region. Arrow keys nudge by one screen point (Shift: ten); Escape cancels. Like quick capture, the region stays on one display.
- **⌘⇧4** opens a crosshair region selector, saves the PNG, and copies it to the clipboard.
- **⌘⇧3** opens the last screenshot without taking a new capture. Closing and reopening the editor preserves annotations, including across app restarts. A new ⌘⇧4 capture becomes the latest screenshot.
- Clicking the editor's save path opens the screenshot folder in Finder in List View, sorted by Date Modified (newest first). Repeated clicks reuse SimpleShot’s own Finder window during the app session without redirecting your other windows. macOS may request Automation permission to control Finder; if denied, the folder still opens with an explanation of how to enable it. **Change Default Location** beside it opens the folder chooser and persists the choice. **Clear Annotations** removes strokes from the current screenshot.
- Successful captures play the installed macOS `Screen Capture.aif` sound. Reopening the editor is silent.
- The preview has Settings and mute buttons. Settings lists installed system alert sounds and system effects, with a Play Sound preview. Both sound selection and mute persist across restarts; muting also stops a currently playing sound.
- Region capture uses an outlined precision crosshair with a live selection-size readout. Escape cancels and restores the normal cursor.
- Previews retain the captured on-screen dimensions; larger captures scroll, and resizing the window never stretches the image. Retina captures retain native pixel resolution, with the original display size stored alongside annotations. Older saved sessions without display-size metadata use one point per image pixel.
- Markup includes freehand pen, lines, arrows, boxes, ellipses, and editable text. Hold Shift while drawing a box or ellipse for a square or circle.
- Choose **Select** and drag empty space to marquee-select annotations, then drag the selection to move them together. Group moves and deletes undo as one action. Selection outlines are hidden while drawing.
- **Ctrl-Z** undoes markup; **Cmd-Z** also works when not typing. **Delete** removes the selected annotation; during text entry it deletes characters.
- Text edits directly on the image. New text starts editing immediately; double-click existing text or choose its nearby **Edit** button. Drag the bottom-right handle to resize the text box; text wraps inside it, and its size persists. Font controls stay anchored above the box while resizing or changing font size; **Done** or Escape ends editing.
- New text boxes start with selected placeholder text “text,” replaced on typing. Text wraps to the box width and visibly overflows below its fixed height instead of being clipped. Inline controls support left, center, and right alignment, persisted with each text annotation.
- Tools are centered, with matching-height color and thickness controls on the left. Color popovers use an aligned, unlabeled layout; permanent instructional captions are omitted.
- All tools have icons and tooltips. **Highlighter** draws translucent strokes. One shared color/thickness control follows the active tool or selected object; selecting Highlighter loads its color and thicker stroke. The color popover includes swatches, a saturation/brightness gradient, a hue strip, and hex entry.
- Annotation edits automatically overwrite the screenshot PNG, including after restarting. The original image and editable objects stay in the session so Clear and Undo remain reversible. Changing the destination creates a new tracked PNG there and leaves the prior file intact. Older sessions without an export path create one tracked PNG on their first edit.
- Undo sits at the top left beside the save-location bar. Clear is right-aligned with the tools; Delete selected floats at the bottom center when using Select with a selection. The screenshot is top-aligned immediately below the toolbar without reserved blank rows.
- Settings → Markup defaults configures persistent default line/highlighter thickness and optional default colors. The initial line thickness is 6 (previously 5); explicitly saved defaults are retained. Slider changes are remembered separately for markup and highlighting throughout the running app session, including across tool switches and new screenshots. Restarting uses the saved defaults; changing a thickness default resets its session override.
- Last chosen markup and highlighter colors persist separately. Settings can override either with a default for new editors/tool selections, without recoloring existing objects.
- Drawing, moving, editing, deleting, undoing, and clearing annotations automatically refresh the clipboard. All object types persist when reopening the preview or restarting the app; older freehand sessions remain compatible.
- The save directory is visible, editable, created automatically, and persisted in `UserDefaults`.
- **Add to Finder** reveals the directory and explains how to drag it into Finder Favorites.

## Run from Xcode

1. Open `Package.swift` in Xcode 16 or later.
2. Select the `SimpleShot` scheme and run it.
3. Grant Screen & System Audio Recording permission when macOS asks.
4. In **System Settings → Keyboard → Keyboard Shortcuts → Screenshots**, disable Apple’s ⌘⇧3 and ⌘⇧4 shortcuts so SimpleShot can register them.
5. Return to SimpleShot Settings, click **Check Shortcuts**, and finish setup once all three show **Ready**. If ⌘⇧2 is reserved by another app or macOS, resolve that conflict too. Settings opens on first launch or when registration fails.

SimpleShot checks macOS system reservations with `CopySymbolicHotKeys` and registers shortcuts with `RegisterEventHotKey`, reporting conflicts and registration errors. It rechecks when activated. Shortcut handling needs no Accessibility permission and does not modify system preferences. Menu-bar capture commands remain available during setup.

## Build an app bundle

```sh
chmod +x Scripts/build-app.sh
SIGNING_IDENTITY='Apple Development: Your Name (TEAMID)' Scripts/build-app.sh
open build/SimpleShot.app
```

The packaging script requires a signing identity by default. Create an Apple Development certificate in Xcode Settings → Accounts → Manage Certificates and pass its name as `SIGNING_IDENTITY`. Use the same certificate for subsequent development updates. Use a Developer ID certificate and notarization for distribution.

For local development, `.signing-identity` may contain the certificate's SHA-1 fingerprint on one line. This file is ignored by Git and used when `SIGNING_IDENTITY` is unset. This pins subsequent builds to the same certificate without storing any private keys in the project.

Disposable builds can opt into ad-hoc signing with `ALLOW_ADHOC_SIGNING=1 Scripts/build-app.sh`. Their code-hash identity changes when the executable changes, invalidating existing Screen Recording approval. Do not use them for routine updates of an approved installation. Moving the existing ad-hoc installation to certificate signing requires one new approval; subsequent updates should retain the same designated requirement.

Settings checks access when opened and when returning from System Settings. A non-prompting CoreGraphics preflight checks authorization, followed by ScreenCaptureKit verification if authorized. **Request Screen Access** explicitly asks macOS for access; if previously denied, System Settings is opened so the user can enable it. This Settings preflight never blocks capture shortcuts. After an actual capture denial, shortcuts show Settings until verification succeeds.

## Platform notes

- Requires macOS 14 or newer because capture uses ScreenCaptureKit's still-image API.
- macOS has no supported public API for adding folders to Finder Favorites. SimpleShot reveals the selected folder so the user can drag it into the sidebar without modifying Finder's private database.

## Development and contributing

Open `Package.swift` in Xcode, or run:

```sh
swift build
swift test
```

Use the bundled app for normal permission testing. Switching between Xcode, command-line executables, and differently signed bundles can change the identity macOS authorizes.

Bug reports and pull requests are welcome. Include your macOS version, reproduction steps, and signing method. Keep changes focused and run `swift test` before submitting. Avoid attaching screenshots containing private information.

Screenshots are saved in your chosen folder. The latest editable session is stored locally under `~/Library/Application Support/SimpleShot/`; preferences use macOS UserDefaults. Capture and annotation processing happen locally. A new capture replaces the latest editable session, while earlier exported PNGs remain in your save folder.

## License

[MIT](LICENSE) © 2026 Evan Reilly.
