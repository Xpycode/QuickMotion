# Plan: Keyboard Speed Controls

## Goal
Add J/K/L keyboard shortcuts for speed control with three selectable modes, and disable auto-play on video load.

---

## Tasks

### Wave 1: Foundation (parallel) ✅

- [x] **Task 1.1**: Disable auto-play on video load
  - File: `AppState.swift`
  - Remove `newPlayer.rate = desiredRate` at end of `loadVideo()`
  - Set `isPlaying = false` initially
  - User must press K or play button to start

- [x] **Task 1.2**: Create SpeedMode enum and logic
  - File: `AppState.swift` (or new `Models/SpeedMode.swift`)
  - Enum: `linear`, `multiplicative`, `presets`
  - Add `speedMode: SpeedMode` property to AppState
  - Add methods: `increaseSpeed(big: Bool)`, `decreaseSpeed(big: Bool)`
  - Implement logic for each mode:
    - Linear: +1 / +10 (or -1 / -10)
    - Multiplicative: ×1.5 / ×2 (or ÷1.5 / ÷2)
    - Presets: [2, 4, 8, 16, 32, 64, 100] jump to next/prev
  - Clamp to 2x min, 100x max

### Wave 2: Keyboard & UI (depends on Wave 1) ✅

- [x] **Task 2.1**: Add J/K/L keyboard handling
  - File: `ContentView.swift` (or dedicated KeyboardHandler)
  - J = `appState.decreaseSpeed(big: event.modifierFlags.contains(.shift))`
  - K = toggle play/pause
  - L = `appState.increaseSpeed(big: event.modifierFlags.contains(.shift))`
  - Use `.onKeyPress` (macOS 14+) or `NSEvent.addLocalMonitorForEvents`

- [x] **Task 2.2**: Add speed mode segmented control
  - File: `SpeedSliderView.swift`
  - Small `Picker` with `.segmented` style below slider
  - Labels: "±1" / "×1.5" / "Presets" (short labels)
  - Binds to `appState.speedMode`

- [x] **Task 2.3**: Add context menu on slider
  - File: `SpeedSliderView.swift`
  - `.contextMenu` on the Slider
  - Same three options as segmented control
  - Checkmark on current selection

### Wave 3: Polish ✅

- [x] **Task 3.1**: Visual feedback on keyboard speed change
  - Brief flash or animation when J/L pressed
  - Optional: show "+1x" or "×1.5" briefly near speed display

- [x] **Task 3.2**: Log reverse playback idea
  - Add to `docs/ideas.md`: "Reverse playback/export at negative speeds"

### Wave 4: Verification ✅

- [x] **Task 4.1**: Test all scenarios
  - Video loads paused
  - K toggles play/pause
  - J decreases speed, stops at 2x
  - L increases speed, stops at 100x
  - Shift+J/L uses big increment
  - Mode switch changes increment behavior
  - Slider stays in sync with keyboard changes
  - Context menu works

---

## Speed Mode Logic

### Linear
```swift
func increaseSpeed(big: Bool) {
    let increment = big ? 10.0 : 1.0
    let newSpeed = min(100, speedMultiplier + increment)
    sliderValue = sliderFromSpeed(newSpeed)
}
```

### Multiplicative
```swift
func increaseSpeed(big: Bool) {
    let factor = big ? 2.0 : 1.5
    let newSpeed = min(100, speedMultiplier * factor)
    sliderValue = sliderFromSpeed(newSpeed)
}
```

### Presets
```swift
let presets = [2.0, 4.0, 8.0, 16.0, 32.0, 64.0, 100.0]

func increaseSpeed(big: Bool) {
    let skip = big ? 2 : 1
    if let currentIndex = presets.firstIndex(where: { $0 >= speedMultiplier }) {
        let newIndex = min(presets.count - 1, currentIndex + skip)
        sliderValue = sliderFromSpeed(presets[newIndex])
    }
}
```

---

## Files Changed

| File | Action |
|------|--------|
| `ViewModels/AppState.swift` | Modify - add SpeedMode, keyboard methods, disable auto-play |
| `Views/SpeedSliderView.swift` | Modify - add segmented control, context menu |
| `ContentView.swift` | Modify - add keyboard handling |
| `docs/ideas.md` | Modify - log reverse playback |

---

*Plan created: 2026-01-26*
