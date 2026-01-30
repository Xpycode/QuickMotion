# Execution Plan: Frame Decimation Export

## Goal
Replace slow AVAssetExportSession (processes ALL frames) with AVAssetReader/AVAssetWriter pipeline that decimates frames based on speed multiplier. Expected 10x speedup for timelapse exports.

## Context
- **Problem**: 93-minute 6K video at 10x speed takes ~47 minutes to export (12% CPU)
- **Root cause**: `scaleTimeRange()` processes every frame, just changes timestamps
- **Solution**: Keep every Nth frame (N = speed multiplier), write only those

## Tasks

### Wave 1 (Foundational - parallel, no dependencies)
- [x] **Task 1.1**: Create `FrameDecimationExporter.swift` protocol + implementation ✅
  - Location: `QuickMotion/Services/FrameDecimationExporter.swift`

- [x] **Task 1.2**: Add `useFrameDecimation` to ExportSettings ✅
  - Location: `QuickMotion/Models/ExportSettings.swift`

### Wave 2 (Integration - depends on Wave 1)
- [x] **Task 2.1**: Integrate FrameDecimationExporter into ExportSession ✅
  - Location: `QuickMotion/ViewModels/ExportSession.swift`

### Wave 3 (Verification)
- [x] **Task 3.1**: Build and verify compilation ✅
  - Build succeeded

## Commits
```
45f5a64 feat: implement frame decimation export for ~10x faster timelapse exports
```

## Status: COMPLETE ✅

All tasks completed. Ready for user testing with 6K source video.
