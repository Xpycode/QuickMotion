<p align="center">
  <img src="03_Screenshots/QM%20Main%20Window%201.jpeg" alt="QuickMotion" width="700">
</p>

<h1 align="center">QuickMotion</h1>

<p align="center">
  Turn videos into timelapses — drop a video in, adjust speed, preview the result, export. One job done well.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14.0%2B-blue" alt="macOS 14.0+">
  <img src="https://img.shields.io/badge/Swift-5.9-orange" alt="Swift 5.9">
  <img src="https://img.shields.io/github/license/Xpycode/QuickMotion" alt="License">
  <img src="https://img.shields.io/github/v/release/Xpycode/QuickMotion" alt="Version">
  <a href="https://github.com/Xpycode/QuickMotion/releases/latest"><img src="https://img.shields.io/badge/Download-DMG-green" alt="Download"></a>
  <img src="https://img.shields.io/github/downloads/Xpycode/QuickMotion/total" alt="Downloads">
</p>

## Features
- Logarithmic speed slider (2x–100x) with fine control at the low end
- Real-time preview via AVPlayer
- Fast passthrough export for speed >2x (no re-encode, I/O bound)
- Quality presets: Fast (HEVC/.mp4) and Quality (ProRes/.mov)
- IN/OUT trim points
- J/K/L playback shortcuts, ⌘O to open, ⌘E to export
- Multiple concurrent export windows
- Sparkle auto-updates
- Notarized and hardened runtime

## Screenshots

<p align="center">
  <img src="03_Screenshots/QM%20Main%20Window%202.jpeg" alt="Main Window" width="600">
</p>

<p align="center">
  <img src="03_Screenshots/QM%20Export%20Dialogue%20FAST.png" alt="Export Dialog" width="350">
  &nbsp;
  <img src="03_Screenshots/QM%20Export%20StatusHEVC%202.png" alt="Export Progress" width="350">
  &nbsp;
  <img src="03_Screenshots/QM%20Export%20StatusHEVC%203%20COMPLETE.png" alt="Export Complete" width="350">
</p>

## Install

Download `QuickMotion-1.0.3.dmg` from the [releases page](https://github.com/Xpycode/QuickMotion/releases/latest), open it, and drag QuickMotion to your Applications folder.

### Requirements
- macOS 14.0+

---

## Development

A **workspace + SPM package** architecture for clean separation between app shell and feature code.

### Project Structure

```
QuickMotion/
├── 01_Project/                              # Xcode project & source code
│   ├── QuickMotion.xcworkspace/           # Open this in Xcode
│   ├── QuickMotionPackage/                # SPM package (primary dev area)
│   │   ├── Sources/QuickMotionFeature/    # Feature code
│   │   └── Tests/                         # Unit tests
│   └── Config/                            # XCConfig build settings
├── 02_Design/                               # Icon source files
├── 03_Screenshots/                          # App screenshots
├── 04_Exports/                              # Built DMGs (gitignored)
└── docs/                                    # Project documentation
```

### Building
```bash
open 01_Project/QuickMotion.xcworkspace
# Or from command line:
xcodebuild -workspace 01_Project/QuickMotion.xcworkspace -scheme QuickMotion -configuration Debug build
```

## License

[MIT](LICENSE) - Luces Umbrarum
