# Decisions Log

This file tracks the WHY behind technical and design decisions.

---

## Decisions

### 2025-01-25 - Preview Engine: AVAssetImageGenerator

**Context:** Need to show preview of timelapse effect at various speeds (2x to 100x).

**Options Considered:**
1. **AVPlayer with rate** - Simple, but limited to 2x smooth playback; beyond shows keyframes only
2. **AVAssetImageGenerator** - Extract frames at calculated intervals, animate as image sequence
3. **CADisplayLink + AVPlayerItemVideoOutput** - More complex, real-time frame access

**Decision:** AVAssetImageGenerator (Option 2)

**Rationale:**
- AVPlayer rate >2x shows only keyframes, not smooth ([Apple Developer Forums](https://github.com/feedback-assistant/reports/issues/229))
- Image generator lets us sample at any interval regardless of playback rate
- Simpler lifecycle - generate frames, display, regenerate on change
- Can use lower resolution (480p) for preview performance

**Consequences:**
- Manage frame generation lifecycle (cancel on speed change, debounce 200ms)
- Memory: regenerate rather than cache all frames
- Preview is "simulated" but adequate for timelapse preview

---

### 2025-01-25 - Export: AVMutableComposition.scaleTimeRange

**Context:** Need to compress video timeline for final timelapse output.

**Options Considered:**
1. **AVMutableComposition + scaleTimeRange** - Apple's time manipulation API
2. **AVAssetWriter frame-by-frame** - Full control, but complex
3. **VideoToolbox** - Low-level, overkill for this use case

**Decision:** AVMutableComposition.scaleTimeRange (Option 1)

**Rationale:**
- Apple's recommended approach for time manipulation
- Works smoothly beyond 2x (unlike AVPlayer playback)
- Integrates with AVAssetExportSession for codec selection
- Audio track easily excluded

**Consequences:**
- Create composition → add video track → scale time range → export
- Export presets map to AVAssetExportPreset options

---

### 2025-01-25 - Speed Slider: Logarithmic Scale (2x-100x)

**Context:** Need speed control from subtle (2x) to extreme (100x), with fine control where it matters most.

**Options Considered:**
1. **Linear scale** - Simple, but 2x-10x becomes tiny portion of slider
2. **Logarithmic scale** - Fine control at low end, coarse at high end
3. **Preset buttons** - Limited flexibility

**Decision:** Logarithmic scale (Option 2)

**Rationale:**
- Most useful range is 2x-20x; logarithmic gives this ~60% of slider
- Formula: `speed = 2 * pow(50, sliderValue)` where sliderValue is 0...1
- At 0.0 → 2x, at 0.5 → ~14x, at 1.0 → 100x

**Consequences:**
- Display computed speed value next to slider
- Consider snap points at powers of 2 (2x, 4x, 8x, 16x, 32x, 64x)

---

### 2025-01-25 - Distribution: Hardened Runtime + Notarization

**Context:** Want to share app via GitHub, potentially Mac App Store later.

**Options Considered:**
1. **Unsigned** - Easy but macOS blocks it
2. **Notarized only** - Works for direct download
3. **Sandboxed + Notarized** - Required for MAS, works for direct too

**Decision:** Hardened runtime with notarization; sandbox later for MAS

**Rationale:**
- Notarization required for any distribution
- Hardened runtime compatible with future MAS path
- Sandbox adds complexity (security-scoped bookmarks) - defer until MAS

**Consequences:**
- Sign with Developer ID for distribution
- If MAS later: add sandbox, file access entitlements

---

### 2025-01-25 - Preview Engine: REVISED → AVPlayer Rate (Replacing AVAssetImageGenerator)

**Context:** Testing revealed AVPlayer rate limits were fixed in macOS 13/iOS 16. Smooth playback now works up to at least 50x.

**New Information:**
- Tested AVPlayer with rates 1x through 100x on macOS 14
- Smooth playback confirmed up to 50x (possibly higher)
- Apple fixed the 2x limit ([FB9343129](https://github.com/feedback-assistant/reports/issues/229))

**Revised Decision:** Use AVPlayer with `rate` property instead of frame extraction

**Rationale:**
- Preview duration now matches output duration (5:43 at 25x → 14s preview)
- Instant speed changes (no extraction delay, no debouncing)
- No frame storage (memory efficient)
- Native video rendering quality
- Dramatically simpler implementation
- AVPlayerView provides JKL keyboard shortcuts for free

**Trade-offs:**
- Above 50x may show keyframes only (acceptable edge case)
- Less control over exact frame selection (not needed for preview)

**Consequences:**
- Delete PreviewEngine or repurpose for thumbnails only
- Remove Debouncer (no longer needed)
- PreviewAreaView uses AVPlayerView via NSViewRepresentable
- Speed slider directly sets player.rate

**Status:** Planned for next session. See PLAN.md.

---
*Add decisions as they are made. Future-you will thank present-you.*
