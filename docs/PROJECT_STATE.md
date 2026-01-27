# Project State

> **Size limit: <80 lines.** This is a digest, not an archive. Details go in session logs.

## Identity
- **Project:** QuickMotion
- **One-liner:** Turn videos into timelapses - drop, adjust speed, preview, export
- **Started:** 2025-01-25

## Current Position
- **Phase:** implementation
- **Focus:** Phase 4 Polish - format testing, final polish
- **Status:** Window position persistence, error handling complete
- **Last updated:** 2026-01-27

## Progress
```
[################....] 80% - Phase 4 of 5
```

| Phase | Status | Tasks |
|-------|--------|-------|
| 1. Skeleton | **done** | 4/4 |
| 2. Preview Engine | **done** | 4/4 |
| 3. Export | **done** | 4/4 |
| 4. Polish | **in progress** | 4/5 |
| 5. Nice-to-haves | pending | 0/3 |

## Tech Stack
- **Platform:** macOS 14+, SwiftUI
- **Video:** AVFoundation (AVPlayer.rate for preview, AVMutableComposition for export)
- **Export:** AVAssetExportSession (HEVC/ProRes)
- **Distribution:** Notarized direct download, potential MAS

## Active Decisions
- 2026-01-27: Window positions persist via NSWindow.setFrameAutosaveName
- 2026-01-27: Pre-flight disk space check with 10% buffer + friendly error messages
- 2026-01-26: NSSavePanel required for export (sandbox only grants read on drop)
- 2026-01-26: Audio uses `.varispeed` algorithm (fast chipmunk effect vs slow spectral)
- 2026-01-26: Export as standalone NSWindow (not sheet) - proper sizing, floating
- 2026-01-26: Export runs independently - user can work on next file while exporting
- 2026-01-26: Quality presets: Fast (HEVC/.mp4), Quality (ProRes/.mov), Match Original
- 2026-01-26: Loop toggle button (on by default)
- 2026-01-26: J/K/L keyboard shortcuts with three speed modes (Linear/Multiplicative/Presets)
- 2026-01-26: No auto-play on video load
- 2025-01-25: **REVISED** Preview via AVPlayer.rate (tested smooth up to 50x on macOS 14+)
- 2025-01-25: Export via AVMutableComposition.scaleTimeRange
- 2025-01-25: Logarithmic speed slider (2x-100x, fine control at low end)
- ~~2025-01-25: 200ms debounce for preview regeneration~~ (removed - instant rate changes)
- ~~2025-01-25: TimelineView at 24fps~~ (replaced by native AVPlayerView)

## Blockers
None

## Key Files
- `Models/TimelapseProject.swift` - Core project model
- `Models/ExportSettings.swift` - Export configuration (quality, resolution, fps)
- `ViewModels/AppState.swift` - App state + AVPlayer
- `ViewModels/ExportSession.swift` - Export state machine + AVAssetExportSession
- `Views/ContentView.swift` - Main UI
- `Views/Export/ExportWindow.swift` - Export window container
- `Views/Export/ExportWindowController.swift` - NSWindow management

## Reference
- Similar app: GlueMotion (photos → timelapse)
- Docs: [AVPlayerView](https://developer.apple.com/documentation/avkit/avplayerview), [AVPlayer.rate](https://developer.apple.com/documentation/avfoundation/avplayer/1388846-rate)

---
*Updated by Claude. Source of truth for project position.*
