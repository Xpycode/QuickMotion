# QuickMotion Fixing Plan

**Date:** 2026-01-29
**Based on:** Three independent code reviews (Gemini Pro, Claude Opus, Codex)
**Verified:** 2026-01-29 via semantic code analysis (Serena MCP)

---

## Priority Legend

| Priority | Meaning |
|----------|---------|
| 🔴 Critical | Bugs that can cause crashes or data corruption |
| 🟠 High | Functional issues that mislead users or break features |
| 🟡 Medium | Code quality issues that increase maintenance burden |
| 🟢 Low | Nice-to-haves and polish items |

---

## Wave 1: Critical Bugs 🔴

### 1.1 AVPlayer Observer Lifecycle Leak
**Source:** Claude Opus (Critical)
**Status:** ✅ VERIFIED via code analysis
**Location:** `AppState.swift:148-185` (loadVideo), `325-340` (observers), `362-406` (trim boundaries)

**Problem:** When loading a new video, existing observers are not removed from the *old* player before creating a new one. Specifically at line 166, `self.player = newPlayer` replaces the old player without cleanup. This causes:
- Memory leaks (old player retained by observer)
- Multiple observers firing simultaneously
- Potential crash when removing observer from wrong player

**Fix:**
```swift
// In loadVideo(), BEFORE creating new player (insert at line 164):
private func cleanupCurrentPlayer() {
    guard let oldPlayer = player else { return }
    removeTimeObserver()
    removeEndObserver()     // <-- Plan was missing this!
    removeOutPointObserver()
    player = nil
}
```

**Note:** Original plan missed `removeEndObserver()`. The `endObserver` (lines 344-358) also needs cleanup.

**Files to modify:**
- `QuickMotionPackage/Sources/QuickMotionFeature/ViewModels/AppState.swift`

**Acceptance criteria:**
- [ ] Loading multiple videos in sequence doesn't accumulate observers
- [ ] No crashes when rapidly switching videos
- [ ] Memory usage stable after loading 10+ videos sequentially

---

## Wave 2: High Priority Fixes 🟠

### 2.1 Export Resolution/Frame Rate Settings Not Applied
**Source:** Claude Opus (High)
**Status:** ⚠️ PARTIALLY VERIFIED - Resolution works for HEVC, Frame Rate never works
**Location:** `ExportSettings.swift:89-114` (avExportPreset), `ExportSession.swift:200-287` (prepareExport)

**Problem (Clarified):**
- **Resolution:** WORKS for HEVC quality (uses `AVAssetExportPresetHEVC1920x1080`, etc.)
- **Resolution:** IGNORED for ProRes quality (always uses `AVAssetExportPresetAppleProRes422LPCM`)
- **Frame Rate:** NEVER applied - no `AVMutableVideoComposition` with `frameDuration` exists

The UI at `ExportSettingsView.swift:208-232` shows both controls, misleading users.

**Fix Options:**
1. **Full implementation:** Add `AVMutableVideoComposition` for ProRes resolution and all frame rate control
2. **Partial fix:** Hide frame rate picker, add "Resolution only works with HEVC" tooltip
3. **Remove misleading UI:** Hide both until properly implemented

**Recommended:** Option 2 for v1.0 (honest about limitations), Option 1 for v1.1

**Files to modify:**
- `QuickMotionPackage/Sources/QuickMotionFeature/Views/Export/ExportSettingsView.swift` - Hide frameRate picker, add resolution caveat
- `QuickMotionPackage/Sources/QuickMotionFeature/Models/ExportSettings.swift` - Add `// TODO: v1.1 - AVMutableVideoComposition for ProRes resolution + frame rate`

**Acceptance criteria:**
- [ ] Frame rate picker hidden (not functional)
- [ ] Resolution shows caveat for ProRes quality
- [ ] Or: Both settings fully implemented with AVMutableVideoComposition

---

### 2.2 "Match Original" Quality Label is Misleading
**Source:** Claude Opus (High)
**Status:** ✅ VERIFIED - Always transcodes to HEVC
**Location:** `ExportSettings.swift:92-102` (avExportPreset), `116-124` (outputFileType), `ExportSettingsView.swift:155-165`

**Problem (Confirmed):** "Match Original" (line 13) implies passthrough, but code at lines 93-102 shows it uses HEVC presets:
```swift
case .fast, .matchOriginal:  // <-- Match Original uses HEVC!
    switch resolution {
    case .match: return AVAssetExportPresetHEVCHighestQuality
```
A ProRes source becomes HEVC unexpectedly. File size estimation at line 167-169 even treats it as passthrough (0.9 factor), compounding the confusion.

**Fix Options:**
1. **True passthrough:** Use `AVAssetExportPresetPassthrough` and preserve source container (complex with time scaling)
2. **Rename:** Change to "Optimized (HEVC)" to be honest
3. **Remove option:** Simplify to just "Fast (HEVC)" and "Quality (ProRes)"

**Recommended:** Option 2 or 3 for v1.0

**Files to modify:**
- `QuickMotionPackage/Sources/QuickMotionFeature/Models/ExportSettings.swift` - Rename/remove matchOriginal
- `QuickMotionPackage/Sources/QuickMotionFeature/Views/Export/ExportSettingsView.swift` - Update label/description

**Acceptance criteria:**
- [ ] Quality option names accurately describe output format
- [ ] No user confusion about codec changes

---

### 2.3 Trim Time Range Validation
**Source:** Claude Opus (Medium, upgrading to High for data safety)
**Status:** ✅ VERIFIED - No validation exists
**Location:** `ExportSession.swift:222-229` (prepareExport time range calculation)

**Problem (Confirmed):** Lines 223-225 calculate time range without validation:
```swift
let effectiveStart = inPoint ?? 0
let effectiveEnd = outPoint ?? fullDuration.seconds
let trimmedDuration = effectiveEnd - effectiveStart  // Can be negative!
```
If `outPoint <= inPoint`, composition can fail silently or produce corrupt output.

**Fix:**
```swift
// Insert after line 225, before building CMTimeRange:
guard effectiveEnd > effectiveStart else {
    throw ExportError.invalidTimeRange("Out point must be after in point")
}
guard trimmedDuration > 0.1 else {
    throw ExportError.invalidTimeRange("Selected duration too short (minimum 0.1s)")
}
```

Also add to `ExportError` enum (line 473):
```swift
case invalidTimeRange(String)
```

**Files to modify:**
- `QuickMotionPackage/Sources/QuickMotionFeature/ViewModels/ExportSession.swift`

**Acceptance criteria:**
- [ ] Clear error message if trim range invalid
- [ ] Cannot export 0-length or negative-length video

---

## Wave 3: Medium Priority (Architecture) 🟡

### 3.1 Extract VideoPlayerService from AppState
**Source:** Gemini Pro + Claude Opus (both identified)
**Location:** `AppState.swift` (entire file)

**Problem:** AppState is becoming a "God Object" mixing:
- AVPlayer lifecycle management
- Speed calculations
- Trim logic
- UI state
- Error handling

**Fix:** Create protocol-based service:
```
QuickMotionFeature/
  Services/
    VideoPlayerService.swift      (protocol)
    AVPlayerService.swift         (implementation)
    MockPlayerService.swift       (for tests)
```

**Benefits:**
- AppState becomes testable without real video files
- Clear separation of concerns
- Easier to swap player implementation if needed

**Files to create:**
- `Services/VideoPlayerService.swift`
- `Services/AVPlayerService.swift`

**Files to modify:**
- `ViewModels/AppState.swift` - Inject service dependency

**Acceptance criteria:**
- [ ] AppState under 300 lines
- [ ] Player logic isolated in service
- [ ] Can write unit tests for AppState with mock player

---

### 3.2 Unify Drop Handlers
**Source:** Claude Opus (Medium)
**Status:** ✅ VERIFIED - Different UTType sets used
**Location:** `ContentView.swift:38-41, 220-232`, `Views/DropZoneView.swift:46-68`

**Problem (Detailed):**
```
ContentView (loaded state):    .movie, .video + "public.movie" identifier
DropZoneView (empty state):    .movie, .video, .mpeg4Movie, .quickTimeMovie
```
Different UTType sets mean some formats (like explicit .quickTimeMovie) may work in DropZoneView but fail in ContentView's global drop handler.

**Fix:** Create shared `VideoDropHandler` utility:
```swift
struct VideoDropHandler {
    /// Supported video types for drop operations
    static let supportedTypes: [UTType] = [.movie, .video, .mpeg4Movie, .quickTimeMovie]

    static func loadURL(from providers: [NSItemProvider]) async -> URL? {
        // Unified logic - try each type identifier
    }
}
```

**Files to create:**
- `QuickMotionPackage/Sources/QuickMotionFeature/Utilities/VideoDropHandler.swift`

**Files to modify:**
- `QuickMotionPackage/Sources/QuickMotionFeature/ContentView.swift` - Use shared handler
- `QuickMotionPackage/Sources/QuickMotionFeature/Views/DropZoneView.swift` - Use shared handler

**Acceptance criteria:**
- [ ] All video types (mov, mp4, m4v, etc.) droppable in both states
- [ ] Single source of truth for drop handling
- [ ] Consistent UTType set across codebase

---

### 3.3 Typed Error Handling
**Source:** Gemini Pro
**Location:** Throughout codebase

**Problem:** Errors are generic strings. No structured error recovery.

**Fix:**
```swift
enum QuickMotionError: LocalizedError {
    case videoLoadFailed(URL, underlying: Error?)
    case exportFailed(reason: String)
    case invalidTimeRange(String)
    case unsupportedFormat(String)

    var errorDescription: String? { ... }
    var recoverySuggestion: String? { ... }
}
```

**Files to create:**
- `Models/QuickMotionError.swift`

**Files to modify:**
- `ViewModels/AppState.swift`
- `ViewModels/ExportSession.swift`

**Acceptance criteria:**
- [ ] All thrown errors are typed
- [ ] Error alerts include recovery suggestions

---

## Wave 4: Testing 🟡

### 4.1 Core Logic Unit Tests
**Source:** Gemini Pro + Claude Opus (both identified)
**Location:** `QuickMotionFeatureTests/`

**Problem:** Only placeholder test exists. Complex logic untested.

**Tests to add:**
1. Speed mapping (`speedFromSlider`/`sliderFromSpeed`) - roundtrip accuracy
2. Trim boundary validation
3. Export settings mapping (quality → preset)
4. File size estimation accuracy
5. Time formatting

**Files to create/modify:**
- `Tests/QuickMotionFeatureTests/SpeedCalculatorTests.swift`
- `Tests/QuickMotionFeatureTests/ExportSettingsTests.swift`
- `Tests/QuickMotionFeatureTests/TrimValidationTests.swift`

**Acceptance criteria:**
- [ ] Speed mapping tests pass
- [ ] Export settings have 80%+ coverage
- [ ] Edge cases documented via test cases

---

## Wave 5: Low Priority Polish 🟢

### 5.1 ~~Remove Redundant Main Queue Hop~~ (NOT A BUG)
**Source:** Claude Opus (Low)
**Location:** `AppState.swift:327-331`
**Status:** ❌ FALSE POSITIVE - The wrapper is REQUIRED

**Analysis:** While the observer runs on `.main` queue, `AppState` is marked `@MainActor`. In Swift concurrency, main queue ≠ MainActor isolation. The `Task { @MainActor }` wrapper is necessary to properly access `self?.currentTime` from the closure. Removing it would cause concurrency warnings or potential data races.

**Action:** Remove from plan - this is correct code.

---

### 5.2 Add CHANGELOG.md
**Source:** Codex (Low)

**Fix:** Create standard changelog following Keep a Changelog format.

---

### 5.3 Add Logging Framework
**Source:** Codex (Low)

**Fix:** Add `os.log` or `Logger` for structured logging. Low priority for v1.0.

---

### 5.4 Split ExportSession.swift
**Source:** Codex (Low) - File over 500 lines

**Fix:** Extract composition building into separate file if it grows further.

---

## Implementation Order

| Wave | Items | Est. Scope | Verified |
|------|-------|-----------|----------|
| 1 | AVPlayer observer fix | 1 file, ~20 lines (add cleanup method + call it) | ✅ |
| 2 | Export UI/validation fixes | 3 files, ~40 lines | ✅ |
| 3 | Architecture refactor | 4-5 new files, significant | - |
| 4 | Tests | 3 test files | - |
| 5 | Polish | Minor changes (5.1 removed - not a bug) | ⚠️ |

**Recommended approach:**
- **v1.0 release:** Waves 1-2 (critical bugs + misleading UI) - ALL VERIFIED
- **v1.1 release:** Waves 3-4 (architecture + tests)
- **Ongoing:** Wave 5 as time permits (minus 5.1 which is correct code)

---

## Verification Summary (MCP Analysis)

| Issue | Verified? | Notes |
|-------|-----------|-------|
| 1.1 AVPlayer observer leak | ✅ Yes | Missing `removeEndObserver()` in original fix |
| 2.1 Resolution/Frame Rate | ⚠️ Partial | Resolution works for HEVC only; Frame rate never works |
| 2.2 Match Original misleading | ✅ Yes | Uses HEVC, not passthrough |
| 2.3 Trim validation | ✅ Yes | No bounds checking |
| 3.2 Drop handlers | ✅ Yes | Different UTType sets confirmed |

---

## Cross-Reference: Issue Sources

| Issue | Gemini | Opus | Codex | MCP Verified |
|-------|--------|------|-------|--------------|
| AVPlayer observer leak | - | ✅ Critical | - | ✅ |
| Export settings not applied | - | ✅ High | - | ⚠️ Partial |
| Match Original misleading | - | ✅ High | - | ✅ |
| Trim validation | - | ✅ Medium | - | ✅ |
| AppState God Object | ✅ | ✅ (implied) | - | - |
| Drop handler inconsistency | - | ✅ Medium | - | ✅ |
| Typed errors | ✅ | - | - | - |
| Test coverage | ✅ | ✅ | - | - |
| Force unwraps | - | - | ✅ Low | - |
| try? usage | - | - | ✅ Low | - |
| File length | - | - | ✅ Low | - |
| No CHANGELOG | - | - | ✅ Low | - |
| No logging | - | - | ✅ Low | - |
| Main queue hop | - | ✅ Low | - | - |

---

*Plan created from reviews by: Gemini Pro, Claude Opus, Codex*
*Verified 2026-01-29 via Serena MCP semantic code analysis*
