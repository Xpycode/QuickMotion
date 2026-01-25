# Plan: Replace Frame Extraction with AVPlayer Rate-Based Preview

## Goal
Replace the current frame extraction preview system with AVPlayer-based playback using the `rate` property for speed control. This simplifies the preview dramatically and makes preview duration match actual output duration.

## Research Summary

### AVPlayer Rate Capabilities (macOS 14+)
- **Tested**: AVPlayer accepts and plays smoothly at rates up to 50x
- **Fixed in macOS 13/iOS 16**: The old 2x smooth playback limit was removed
- **API**: Simply set `player.rate = speedMultiplier` for instant speed changes
- **Sources**:
  - [Apple FB9343129 fix confirmation](https://github.com/feedback-assistant/reports/issues/229)
  - [AVPlayer rate documentation](https://developer.apple.com/documentation/avfoundation/avplayer/1388846-rate)

### SwiftUI Integration
- Use `NSViewRepresentable` to wrap `AVPlayerView` for macOS
- Observe playback state via `addPeriodicTimeObserver` for current time
- Seeking via `player.seek(to: CMTime, toleranceBefore: .zero, toleranceAfter: .zero)`
- **Note**: macOS 26 adds `AVPlayer.isObservationEnabled` for direct SwiftUI observation, but we target macOS 14+, so use KVO/time observers

### Sources
- [AVPlayerView documentation](https://developer.apple.com/documentation/avkit/avplayerview)
- [Observing playback state in SwiftUI](https://developer.apple.com/documentation/avfoundation/observing-playback-state-in-swiftui)
- [Cindori: Building a Custom Video Player](https://cindori.com/developer/building-video-player-swiftui-avkit)

---

## Current Architecture (to be replaced)

```
Video Load → PreviewEngine extracts 60 frames → Store in AppState.previewFrames
Speed Change → Debounce 200ms → Re-extract frames → Update previewFrames
Preview Display → TimelineView animates through frames at 24fps
Scrubbing → Change currentFrameIndex
```

**Problems**:
- Preview always ~2.5s (60 frames / 24fps) regardless of speed
- Frame extraction takes time, requires progress UI
- Memory usage for storing 60 NSImages
- Debouncing adds latency on speed changes

---

## New Architecture

```
Video Load → Create AVPlayer with asset → Display in AVPlayerView
Speed Change → Set player.rate = speedMultiplier (instant)
Preview Display → AVPlayerView renders video at specified rate
Scrubbing → player.seek(to: time)
```

**Benefits**:
- Preview duration matches output duration (5:43 at 25x → 14s preview)
- Instant speed changes (no extraction delay)
- No frame storage (memory efficient)
- Native video rendering quality
- JKL keyboard shortcuts for free via AVPlayerView

---

## Tasks

### Wave 1: Create AVPlayer Infrastructure (parallel)

- [x] **Task 1.1**: Create `VideoPlayerView` (NSViewRepresentable wrapper)
  - File: `QuickMotionPackage/Sources/QuickMotionFeature/Views/VideoPlayerView.swift`
  - Wrap `AVPlayerView` for SwiftUI
  - Set `controlsStyle = .none` (we have custom controls)
  - Pass AVPlayer from parent
  - Handle `isReadyForDisplay`

- [x] **Task 1.2**: Update `AppState` to use AVPlayer
  - File: `QuickMotionPackage/Sources/QuickMotionFeature/ViewModels/AppState.swift`
  - Replace `previewFrames: [NSImage]` with `player: AVPlayer?`
  - Replace `previewState` enum: `idle | loading | ready | error`
  - Add `currentTime: Double` and `duration: Double` for scrubber
  - Add time observer for playback progress
  - Speed slider → directly sets `player.rate`
  - Remove debouncer (no longer needed)

### Wave 2: Update Preview UI (depends on Wave 1)

- [x] **Task 2.1**: Rewrite `PreviewAreaView` to use `VideoPlayerView`
  - File: `QuickMotionPackage/Sources/QuickMotionFeature/Views/PreviewAreaView.swift`
  - Replace frame animation with `VideoPlayerView`
  - Update scrubber to use time-based seeking
  - Show current time / total duration instead of frame count
  - Keep play/pause button (calls `player.play()` / `player.pause()`)

- [x] **Task 2.2**: Update speed slider behavior
  - File: `QuickMotionPackage/Sources/QuickMotionFeature/Views/SpeedSliderView.swift` (if separate) or `ContentView.swift`
  - Slider changes → `appState.player?.rate = newSpeed` (when playing)
  - Store desired rate so it persists across pause/play
  - Consider max rate cap at 50x based on testing (or let user go to 100x, accepting potential keyframe-only above 50x)

### Wave 3: Cleanup (depends on Wave 2)

- [x] **Task 3.1**: Remove or repurpose `PreviewEngine`
  - File: `QuickMotionPackage/Sources/QuickMotionFeature/Services/PreviewEngine.swift`
  - Option A: Delete entirely ✓
  - Option B: Keep for thumbnail generation only (first frame for video info display)
  - Remove `Debouncer.swift` if no longer used elsewhere ✓

- [x] **Task 3.2**: Update preview state hint for high speeds
  - If speed > 50x, show subtle indicator: "Preview may skip frames above 50x"
  - Only show when actually above threshold

### Wave 4: Verification

- [x] **Task 4.1**: Test all scenarios
  - Load video → preview plays at current speed
  - Change speed while playing → rate updates instantly
  - Change speed while paused → rate applies on next play
  - Scrub timeline → seeks to correct position
  - Play/pause toggle works
  - Clear project → player released
  - Load new video → previous player released, new one created

---

## Implementation Notes

### VideoPlayerView (NSViewRepresentable)

```swift
import AVKit
import SwiftUI

struct VideoPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.showsFullScreenToggleButton = false
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}
```

### AppState Changes (Key Parts)

```swift
// Replace
public var previewFrames: [NSImage] = []
public var currentFrameIndex: Int = 0

// With
public var player: AVPlayer?
public var currentTime: Double = 0
public var duration: Double = 0
private var timeObserver: Any?

// Speed change (no debounce needed)
public var sliderValue: Double = 0.5 {
    didSet {
        project?.speedMultiplier = speedFromSlider(sliderValue)
        if isPlaying {
            player?.rate = Float(speedMultiplier)
        }
    }
}

// Load video
public func loadVideo(from url: URL) async {
    let asset = AVURLAsset(url: url)
    let playerItem = AVPlayerItem(asset: asset)
    player = AVPlayer(playerItem: playerItem)
    setupTimeObserver()
    // ... load metadata
}

// Time observer
private func setupTimeObserver() {
    let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
    timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
        self?.currentTime = time.seconds
    }
}
```

### Scrubber (Time-Based)

```swift
Slider(
    value: Binding(
        get: { appState.currentTime },
        set: { newTime in
            let cmTime = CMTime(seconds: newTime, preferredTimescale: 600)
            appState.player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        }
    ),
    in: 0...appState.duration
)
```

---

## Edge Cases

1. **Speed > 50x**: May show keyframes only. Accept or cap at 50x.
2. **Very short videos at low speed**: Long preview, fine.
3. **Very long videos at high speed**: Short preview, exactly what we want.
4. **Seeking while playing**: Should continue playing from new position at current rate.
5. **End of video**: Loop or stop? Current behavior: let it stop, user can replay.

---

## Decisions Needed

1. **Cap speed at 50x or allow 100x?**
   - Recommendation: Allow 100x, show hint above 50x that preview may skip frames

2. **Loop preview automatically?**
   - Recommendation: No loop, matches export behavior. User can click play again.

3. **Show time or frame count in scrubber?**
   - Recommendation: Show time (matches output), e.g., "0:05 / 0:14"

---

## Files Changed

| File | Action |
|------|--------|
| `Views/VideoPlayerView.swift` | **Create** - NSViewRepresentable wrapper |
| `ViewModels/AppState.swift` | **Modify** - Replace frames with AVPlayer |
| `Views/PreviewAreaView.swift` | **Modify** - Use VideoPlayerView |
| `Services/PreviewEngine.swift` | **Delete or simplify** |
| `Utilities/Debouncer.swift` | **Potentially delete** |
| `docs/PROJECT_STATE.md` | **Update** - Note architectural change |
| `docs/decisions.md` | **Update** - Log AVPlayer decision |

---

*Plan created: 2025-01-25*
*Ready for next session to implement*
