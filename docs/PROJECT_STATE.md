# Project State

> **Size limit: <80 lines.** This is a digest, not an archive. Details go in session logs.

## Identity
- **Project:** QuickMotion
- **One-liner:** Turn videos into timelapses - drop, adjust speed, preview, export
- **Started:** 2025-01-25

## Current Position
- **Phase:** implementation
- **Focus:** Export functionality (next)
- **Status:** Preview refactor complete - AVPlayer.rate now used for preview
- **Last updated:** 2026-01-26

## Progress
```
[########............] 40% - Phase 3 of 5
```

| Phase | Status | Tasks |
|-------|--------|-------|
| 1. Skeleton | **done** | 4/4 |
| 2. Preview Engine | **done** | 4/4 |
| 3. Export | **next** | 0/3 |
| 4. Polish | pending | 0/5 |
| 5. Nice-to-haves | pending | 0/3 |

## Tech Stack
- **Platform:** macOS 14+, SwiftUI
- **Video:** AVFoundation (AVPlayer.rate for preview, AVMutableComposition for export)
- **Export:** AVAssetExportSession (HEVC/ProRes)
- **Distribution:** Notarized direct download, potential MAS

## Active Decisions
- 2025-01-25: **REVISED** Preview via AVPlayer.rate (tested smooth up to 50x on macOS 14+)
- 2025-01-25: Export via AVMutableComposition.scaleTimeRange
- 2025-01-25: Logarithmic speed slider (2x-100x, fine control at low end)
- ~~2025-01-25: 200ms debounce for preview regeneration~~ (removed - instant rate changes)
- ~~2025-01-25: TimelineView at 24fps~~ (replaced by native AVPlayerView)

## Blockers
None

## Key Files
- `QuickMotionPackage/Sources/QuickMotionFeature/Models/TimelapseProject.swift` - Core model
- `QuickMotionPackage/Sources/QuickMotionFeature/Views/ContentView.swift` - Main UI
- `QuickMotionPackage/Sources/QuickMotionFeature/Views/PreviewAreaView.swift` - Preview display (AVPlayer-based)
- `QuickMotionPackage/Sources/QuickMotionFeature/Views/VideoPlayerView.swift` - AVPlayerView wrapper
- `QuickMotionPackage/Sources/QuickMotionFeature/ViewModels/AppState.swift` - App state + AVPlayer

## Reference
- Similar app: GlueMotion (photos → timelapse)
- Docs: [AVPlayerView](https://developer.apple.com/documentation/avkit/avplayerview), [AVPlayer.rate](https://developer.apple.com/documentation/avfoundation/avplayer/1388846-rate)

---
*Updated by Claude. Source of truth for project position.*
