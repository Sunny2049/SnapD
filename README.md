# SnapD — a tiny macOS screenshot tool

A native Swift menu-bar screenshot app for macOS 14+ (Apple Silicon).
No third-party dependencies — just AppKit, Carbon, Vision and friends.

Press **Option + D**, drag a region, done. Captures are auto-saved to the
Desktop and auto-copied to the clipboard, and a small floating toolbar under
the capture lets you annotate before the editor quietly closes itself.

## Features

- **Region / fullscreen / window capture**, plus **scrolling long capture**
  (auto-scrolls and stitches frames by row matching)
- **Floating annotation toolbar** that hangs below the capture, wider than
  the image if needed: pen, straight line, rectangle, arrow, text, undo
- **Smear brush** — drag a thick black stroke over anything you want to hide
- **OCR** — extract text from the capture with the on-device Vision
  framework (Simplified Chinese + English), nothing leaves your Mac
- **Pin to desktop** — float a capture (or any image on the clipboard) above
  everything, like a sticky note
- **Customizable global hotkeys** — record your own combos in Settings,
  with conflict detection
- Editor auto-closes after 5 idle seconds; any interaction keeps it open

## Default hotkeys

| Hotkey | Action |
|---|---|
| Option + D | Region capture |
| Option + Shift + D | Fullscreen capture |
| Option + W | Front-window capture |
| Option + L | Scrolling long capture |
| Option + P | Pin clipboard image |

All of them can be changed: menu bar icon → Hotkey Settings…

## Build & install

You need a Mac with Xcode / Swift toolchain installed.

```bash
./build_app.sh
cp -R SnapD.app /Applications/
open /Applications/SnapD.app
```

On first launch, grant **Screen Recording** when macOS asks
(System Settings → Privacy & Security → Screen Recording → SnapD),
then quit and relaunch SnapD once. Without that permission captures come
out as bare wallpaper — macOS hides other windows from unapproved apps.

The build is ad-hoc / self-signed (no Apple Developer ID, no notarization),
so the first open on another Mac needs right-click → Open.

> Tip: rebuilds change an ad-hoc signature, and macOS ties the Screen
> Recording grant to the signature — so after rebuilding you may have to
> grant it again. `build_app.sh` avoids this if you create a self-signed
> code-signing identity named `SnapD Signing`; see the comments in the
> script.

An `AppIcon.icns` placed next to `build_app.sh` is picked up automatically
if present.

## License

MIT — see [LICENSE](LICENSE).
