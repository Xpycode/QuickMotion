# QuickMotion

Turn videos into timelapses — drop a video in, adjust speed, preview the result, export. One job done well.

**[Download Latest Release (v1.0.1)](https://github.com/Xpycode/QuickMotion/releases/latest)**

### Features
- Logarithmic speed slider (2x–100x) with fine control at the low end
- Real-time preview via AVPlayer
- Fast passthrough export for speed >2x (no re-encode, I/O bound)
- Quality presets: Fast (HEVC/.mp4) and Quality (ProRes/.mov)
- IN/OUT trim points
- J/K/L playback shortcuts, ⌘O to open, ⌘E to export
- Multiple concurrent export windows
- Sparkle auto-updates
- Notarized and hardened runtime

### Requirements
- macOS 14.0+

### Install
Download `QuickMotion-1.0.1.dmg` from the [releases page](https://github.com/Xpycode/QuickMotion/releases/latest), open it, and drag QuickMotion to your Applications folder.

---

## Development

A **workspace + SPM package** architecture for clean separation between app shell and feature code.

## Project Architecture

```
QuickMotion/
├── QuickMotion.xcworkspace/              # Open this file in Xcode
├── QuickMotion.xcodeproj/                # App shell project
├── QuickMotion/                          # App target (minimal)
│   ├── Assets.xcassets/                # App-level assets (icons, colors)
│   ├── QuickMotionApp.swift              # App entry point
│   ├── QuickMotion.entitlements          # App sandbox settings
│   └── QuickMotion.xctestplan            # Test configuration
├── QuickMotionPackage/                   # 🚀 Primary development area
│   ├── Package.swift                   # Package configuration
│   ├── Sources/QuickMotionFeature/       # Your feature code
│   └── Tests/QuickMotionFeatureTests/    # Unit tests
└── QuickMotionUITests/                   # UI automation tests
```

## Key Architecture Points

### Workspace + SPM Structure
- **App Shell**: `QuickMotion/` contains minimal app lifecycle code
- **Feature Code**: `QuickMotionPackage/Sources/QuickMotionFeature/` is where most development happens
- **Separation**: Business logic lives in the SPM package, app target just imports and displays it

### Buildable Folders (Xcode 16)
- Files added to the filesystem automatically appear in Xcode
- No need to manually add files to project targets
- Reduces project file conflicts in teams

### App Sandbox
The app is sandboxed by default with basic file access permissions. Modify `QuickMotion.entitlements` to add capabilities as needed.

## Development Notes

### Code Organization
Most development happens in `QuickMotionPackage/Sources/QuickMotionFeature/` - organize your code as you prefer.

### Public API Requirements
Types exposed to the app target need `public` access:
```swift
public struct SettingsView: View {
    public init() {}
    
    public var body: some View {
        // Your view code
    }
}
```

### Adding Dependencies
Edit `QuickMotionPackage/Package.swift` to add SPM dependencies:
```swift
dependencies: [
    .package(url: "https://github.com/example/SomePackage", from: "1.0.0")
],
targets: [
    .target(
        name: "QuickMotionFeature",
        dependencies: ["SomePackage"]
    ),
]
```

### Test Structure
- **Unit Tests**: `QuickMotionPackage/Tests/QuickMotionFeatureTests/` (Swift Testing framework)
- **UI Tests**: `QuickMotionUITests/` (XCUITest framework)
- **Test Plan**: `QuickMotion.xctestplan` coordinates all tests

## Configuration

### XCConfig Build Settings
Build settings are managed through **XCConfig files** in `Config/`:
- `Config/Shared.xcconfig` - Common settings (bundle ID, versions, deployment target)
- `Config/Debug.xcconfig` - Debug-specific settings  
- `Config/Release.xcconfig` - Release-specific settings
- `Config/Tests.xcconfig` - Test-specific settings

### App Sandbox & Entitlements
The app is sandboxed by default with basic file access. Edit `QuickMotion/QuickMotion.entitlements` to add capabilities:
```xml
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
<key>com.apple.security.network.client</key>
<true/>
<!-- Add other entitlements as needed -->
```

## macOS-Specific Features

### Window Management
Add multiple windows and settings panels:
```swift
@main
struct QuickMotionApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        
        Settings {
            SettingsView()
        }
    }
}
```

### Asset Management
- **App-Level Assets**: `QuickMotion/Assets.xcassets/` (app icon with multiple sizes, accent color)
- **Feature Assets**: Add `Resources/` folder to SPM package if needed

### SPM Package Resources
To include assets in your feature package:
```swift
.target(
    name: "QuickMotionFeature",
    dependencies: [],
    resources: [.process("Resources")]
)
```

## Notes

### Generated with XcodeBuildMCP
This project was scaffolded using [XcodeBuildMCP](https://github.com/cameroncooke/XcodeBuildMCP), which provides tools for AI-assisted macOS development workflows.