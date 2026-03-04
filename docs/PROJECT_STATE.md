# Project State

> **Size limit: <80 lines.** This is a digest, not an archive. Details go in session logs.

## Identity
- **Project:** QuickMotion
- **One-liner:** Turn videos into timelapses - drop, adjust speed, preview, export
- **Started:** 2025-01-25

## Current Position
- **Phase:** shipped
- **Focus:** Done — v1.0.3 released
- **Status:** Notarized, on GitHub with DMG + Sparkle auto-updates working, MIT licensed
- **Last updated:** 2026-03-04

## Progress
```
[####################] 95% - Shipped v1.0.3
```

| Phase | Status | Tasks |
|-------|--------|-------|
| 1. Skeleton | **done** | 4/4 |
| 2. Preview Engine | **done** | 4/4 |
| 3. Export | **done** | 4/4 |
| 4. Polish | **done** | 5/5 |
| 5. Nice-to-haves | pending | 0/3 |

## Tech Stack
- **Platform:** macOS 14+, SwiftUI
- **Video:** AVFoundation (AVPlayer.rate for preview)
- **Export:** PassthroughExporter (keyframes) when defaults kept at speed >2x; AVAssetExportSession (re-encode) when user picks ProRes/resolution/audio
- **Distribution:** Notarized direct download (GitHub releases), MIT license

## Active Decisions
- 2026-03-04: Sparkle SUFeedURL requires real Info.plist — INFOPLIST_KEY_ prefix only works for Apple keys
- 2026-03-04: Export controls always enabled — passthrough only when user keeps defaults (Fast HEVC + Match Source + no audio)
- 2026-03-04: Font rule: `.monospacedDigit()` for numeric displays, `.monospaced` for code only
- 2026-03-04: Duration format with explicit units ("58m 31s", "35s") everywhere
- 2026-03-04: MIT license, copyright Luces Umbrarum
- 2026-01-31: Keyboard shortcuts ⌘O (Open), ⌘E (Export) via NotificationCenter
- 2026-01-31: Project reorganized with numbered folders (01_Project, 02_Design, etc.)
- 2026-01-31: Hardened Runtime enabled for notarization
- 2026-01-27: Window positions persist via NSWindow.setFrameAutosaveName
- 2026-01-27: Pre-flight disk space check with 10% buffer + friendly error messages
- 2026-01-26: NSSavePanel required for export (sandbox only grants read on drop)
- 2026-01-26: Audio uses `.varispeed` algorithm (fast chipmunk effect vs slow spectral)
- 2026-01-31: Export window normal level (removed .floating - was above all apps)
- 2026-01-31: Multiple concurrent export windows (UUID-tracked, cascaded positioning)
- 2026-01-31: Force .mov extension for passthrough exports (speed > 2x) - sandbox permission fix
- 2026-01-30: Passthrough export for speed >2x (keyframes only, I/O bound, no FFmpeg)
- 2026-01-26: Quality presets: Fast (HEVC/.mp4), Quality (ProRes/.mov)
- 2026-01-26: Loop toggle button (on by default)
- 2026-01-26: J/K/L keyboard shortcuts with three speed modes (Linear/Multiplicative/Presets)
- 2026-01-26: No auto-play on video load
- 2025-01-25: **REVISED** Preview via AVPlayer.rate (tested smooth up to 50x on macOS 14+)
- ~~2025-01-25: Export via AVMutableComposition.scaleTimeRange~~ (replaced by passthrough for speed >2x)
- 2025-01-25: Logarithmic speed slider (2x-100x, fine control at low end)
- ~~2025-01-25: 200ms debounce for preview regeneration~~ (removed - instant rate changes)
- ~~2025-01-25: TimelineView at 24fps~~ (replaced by native AVPlayerView)

## Blockers
- None. Shipped.
- Note: `xcrun notarytool store-credentials notarytool` not yet set up for CLI notarization

## Key Files
All source in `01_Project/QuickMotionPackage/Sources/QuickMotionFeature/`:
- `Models/TimelapseProject.swift` - Core project model
- `Models/ExportSettings.swift` - Export configuration (quality, resolution, fps)
- `Services/PassthroughExporter.swift` - Fast export via keyframe passthrough
- `ViewModels/AppState.swift` - App state (delegates to AVPlayerService)
- `ViewModels/ExportSession.swift` - Export state machine
- `Views/ContentView.swift` - Main UI + keyboard shortcuts

## Reference
- Similar app: GlueMotion (photos → timelapse)
- Docs: [AVPlayerView](https://developer.apple.com/documentation/avkit/avplayerview), [AVPlayer.rate](https://developer.apple.com/documentation/avfoundation/avplayer/1388846-rate)

---
*Updated by Claude. Source of truth for project position.*
