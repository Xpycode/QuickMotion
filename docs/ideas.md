# Feature Ideas & Backlog

Cross-project ideas and reusable components to build.

---

## FeedbackKit - In-App Bug Report & Feedback System

**Added:** 2026-01-23
**Status:** Idea
**Type:** Swift Package (reusable)

### What
A drop-in Swift Package for macOS (and eventually iOS) apps that provides:
- User-initiated feedback/bug reports via Help menu
- Device info collection (OS version, app version, hardware)
- Console log capture (especially useful for ffmpeg-based apps)
- User-written description
- Optional screenshot attachment

### Delivery Options (TBD)
| Option | Pros | Cons |
|--------|------|------|
| NSSharingService (Mail) | Zero infrastructure, user sees what's sent | Requires user mail setup |
| Discord Webhook | Free, easy setup, real-time notifications | Requires Discord |
| Self-hosted endpoint | Full control, Mac minis available | Maintenance overhead |
| Strato web hosting | Already have it | PHP/basic hosting limits |

### Architecture Notes
- Design with pluggable `ReportDestination` protocol
- Package handles collection + UI
- App injects the delivery mechanism
- Consider: built-in log viewer vs silent capture

### Infrastructure Available
- 2x headless M1 Mac minis (always-on, internet connected)
- Strato web hosting

### Next Steps
1. Scaffold Swift Package structure
2. Define `FeedbackReport` data model
3. Implement device info collector
4. Implement log capture (especially for apps with console output)
5. Build submission UI (sheet with description field + optional screenshot)
6. Create first `ReportDestination` implementation (probably Discord webhook for simplicity)

---

*Add new ideas below. Move to project-specific docs when starting implementation.*
