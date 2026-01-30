# Feature Backlog

> MVP reached as of 2026-01-27. This documents post-MVP enhancements.

## MVP Gaps (Ship Blockers)

| Feature | Why Needed | Status |
|---------|-----------|--------|
| ~~Sparkle Updates~~ | Users need automatic updates for direct distribution | ✅ Done |
| ~~About Window~~ | Version info, credits, legal | ✅ Done |

---

## Feature Assessment

### Legend
- **Difficulty:** Trivial (<1d) / Easy (1-2d) / Medium (3-5d) / Hard (1-2w) / Complex (2w+)
- **Value:** ★★★ High / ★★ Medium / ★ Low
- **ROI:** Value vs effort ratio

---

## Tier 1: High Value, Achievable

### Recent Projects + Auto-restore
- **Difficulty:** Easy
- **Value:** ★★★
- **Why:** Essential for repeat users. NSDocumentController or UserDefaults + Codable project state.
- **Effort:** Store last 10 projects as JSON, restore on launch or via File menu.

### Reveal in Finder / Open in QuickTime
- **Difficulty:** Trivial
- **Value:** ★★★
- **Why:** Expected macOS behavior. Users currently have no way to find their export.
- **Effort:** `NSWorkspace.shared.selectFile()` and `.open()`

### Background Export + Notification
- **Difficulty:** Easy (already partially done)
- **Value:** ★★★
- **Why:** Export already runs independently. Add `UNUserNotificationCenter` on completion.
- **Effort:** 20 lines of notification code.

### Export Presets (YouTube 4K, Instagram, ProRes)
- **Difficulty:** Easy
- **Value:** ★★★
- **Why:** Users don't want to think about settings. Common use cases pre-configured.
- **Effort:** Extend ExportSettings with preset enum, add picker to export window.

### Mini Inspector Panel
- **Difficulty:** Easy
- **Value:** ★★
- **Why:** Shows input/output duration, estimated file size, ETA. Reduces uncertainty.
- **Effort:** Calculate from asset duration / speed. Simple sidebar or footer view.

### Undo/Redo for Trim + Speed
- **Difficulty:** Medium
- **Value:** ★★★
- **Why:** Users expect Cmd+Z to work. Currently no way to revert changes.
- **Effort:** UndoManager integration, register changes as undoable actions.

---

## Tier 2: Medium Value, Medium Effort

### Frame-accurate Stepping (←/→)
- **Difficulty:** Easy
- **Value:** ★★
- **Why:** Precise trim control for professional use.
- **Effort:** `AVPlayer.step(byCount:)` on arrow key press.

### Batch Import + Export Queue
- **Difficulty:** Medium
- **Value:** ★★
- **Why:** Power users want to process multiple clips unattended.
- **Effort:** Array of TimelapseProject, sequential processing, queue UI.

### First-run Guide / Onboarding
- **Difficulty:** Easy
- **Value:** ★★
- **Why:** J/K/L, I/O shortcuts aren't discoverable without tutorial.
- **Effort:** Simple overlay or modal with key hints. Show once via UserDefaults.

### Music/Audio Track Import
- **Difficulty:** Medium
- **Value:** ★★
- **Why:** Timelapses often need music. Currently export strips audio.
- **Effort:** AVMutableComposition audio track, file picker, trim to video length.

### Quick Share (macOS Share Menu)
- **Difficulty:** Easy
- **Value:** ★★
- **Why:** Native sharing to Messages, AirDrop, Mail.
- **Effort:** `NSSharingServicePicker` with exported file URL.

### Thumbnail/Poster Frame Export
- **Difficulty:** Trivial
- **Value:** ★
- **Why:** Nice-to-have for social media thumbnails.
- **Effort:** `AVAssetImageGenerator` for single frame, save as JPEG.

---

## Tier 3: Medium Value, High Effort

### Variable Speed Ramp + Curve Editor
- **Difficulty:** Hard
- **Value:** ★★
- **Why:** Creative control (slow → fast → slow). Differentiator feature.
- **Effort:** Custom curve UI, segmented composition with different time scales.

### Motion Blur / Frame Blending
- **Difficulty:** Hard
- **Value:** ★★
- **Why:** Smooth light trails effect. Pro-level feature.
- **Effort:** CIFilter or Metal shader to blend consecutive frames during export.

### Markers + Snap-to
- **Difficulty:** Medium
- **Value:** ★
- **Why:** Helpful for complex edits but most users use simple in/out.
- **Effort:** Marker model, timeline overlay, snap logic.

### Burn-in Overlays (Timestamp, Watermark)
- **Difficulty:** Medium
- **Value:** ★
- **Why:** Niche use case (construction timelapses, branding).
- **Effort:** CATextLayer or CIFilter composition, overlay during export.

### Auto-Stabilization / Crop
- **Difficulty:** Complex
- **Value:** ★★
- **Why:** Handheld timelapses are shaky. Useful but scope creep.
- **Effort:** Core Image or VNTrackTranslationalImageRegistrationRequest, complex.

---

## Tier 4: Low Priority / Future Consideration

### Watch Folders (Auto-process)
- **Difficulty:** Medium
- **Value:** ★
- **Why:** Very niche automation use case.
- **Effort:** FSEvents monitoring, background processing.

### Reverse Playback
- **Difficulty:** Easy
- **Value:** ★
- **Why:** Creative effect but not core to timelapse workflow.
- **Effort:** Negative rate or reversed composition.

### Format/Codec Deep Control
- **Difficulty:** Medium
- **Value:** ★
- **Why:** Most users don't understand bitrate profiles. Presets are better.
- **Effort:** UI complexity for minimal user benefit.

### Keybinding Customization
- **Difficulty:** Medium
- **Value:** ★
- **Why:** Power user feature. Current defaults (J/K/L, I/O) are standard.
- **Effort:** Preferences pane, key recording, storage.

### Templates (Traffic, Clouds, Construction)
- **Difficulty:** Easy
- **Value:** ★
- **Why:** Cute but artificial. Speed depends on source, not "type."
- **Effort:** Preset values that don't actually help.

### Proxy Playback Toggle
- **Difficulty:** Medium
- **Value:** ★
- **Why:** AVPlayer handles large files well. Only needed if performance issues arise.
- **Effort:** Generate proxy, switch assets, manage storage.

### Metadata Passthrough
- **Difficulty:** Medium
- **Value:** ★
- **Why:** GPS/camera info rarely survives processing anyway. Niche.
- **Effort:** AVMetadataItem reading/writing, format-specific handling.

---

## Accessibility (Ongoing)

| Item | Difficulty | Status |
|------|------------|--------|
| VoiceOver labels | Easy | Partial |
| Focus rings | Trivial | Needed |
| Larger hit targets | Easy | Some done |
| Keyboard navigation | Medium | J/K/L done |

---

## Recommended Roadmap

### Phase 5 (Polish Completion)
1. Sparkle Updates (ship blocker)
2. About Window (ship blocker)
3. Reveal in Finder / Open in QuickTime
4. Background export notification

### Phase 6 (Post-launch Quick Wins)
1. Export presets (YouTube, Instagram, ProRes)
2. Recent projects list
3. First-run guide
4. Mini inspector panel

### Phase 7 (Feature Expansion)
1. Undo/Redo
2. Frame stepping
3. Music import
4. Quick Share

### Phase 8+ (Future)
- Variable speed ramps
- Motion blur
- Batch processing

---

*Created 2026-01-27. Update as priorities shift.*
