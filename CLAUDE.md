# QuickMotion

A minimal macOS app for turning videos into timelapses. Drop a video in, adjust speed, preview the result, export. One job done well.

## Tech Stack
- **Platform:** macOS 14+
- **UI:** SwiftUI
- **Video Processing:** AVFoundation
  - Preview: AVAssetImageGenerator (frame extraction)
  - Export: AVMutableComposition + scaleTimeRange
  - Output: AVAssetExportSession (HEVC/ProRes)
- **State:** ObservableObject pattern
- **Distribution:** Notarized, potential Mac App Store

## Architecture

### Core Model
`TimelapseProject` - holds source AVAsset, speed multiplier (2x-100x), in/out points, export settings. Codable for future project save/restore.

### Preview Engine
1. Calculate frame times based on speed: source 30fps at 10x = sample every 10th frame
2. AVAssetImageGenerator extracts frames at reduced resolution (480p)
3. Animate through frames at 15-24fps for preview
4. Debounce regeneration (200ms after slider stops)

### Export Engine
1. Create AVMutableComposition with video track only (drop audio)
2. Use scaleTimeRange to compress timeline by speed factor
3. Export via AVAssetExportSession with selected preset

### State Flow
```
Preview: idle → generating → ready → stale (on settings change)
Export: idle → exporting (with progress) → done/failed
```

## Key Decisions
- **AVAssetImageGenerator over AVPlayer** - AVPlayer rate limited to 2x smooth playback
- **Logarithmic speed slider** - Fine control at useful 2x-20x range
- **No sandbox initially** - Simpler; add for MAS later

## Folder Structure
```
QuickMotion/
├── 01_Project/          ← Xcode project, source code
├── 02_Design/           ← Icon source files
├── 03_Screenshots/      ← App Store screenshots
├── 04_Exports/          ← Built DMGs (gitignored)
├── docs/                ← Directions documentation
└── scripts/             ← Build/utility scripts
```

## Project Documentation
Full docs in `/docs` - see `PROJECT_STATE.md` for current status.

## Building
```bash
# Open in Xcode
open 01_Project/QuickMotion.xcworkspace

# Or build from command line
xcodebuild -workspace 01_Project/QuickMotion.xcworkspace -scheme QuickMotion -configuration Debug build
```
