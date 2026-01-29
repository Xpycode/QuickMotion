#!/bin/bash
set -e

# QuickMotion Release Script
# Usage: ./scripts/release.sh [version]
# Example: ./scripts/release.sh 1.1.0

cd "$(dirname "$0")/.."
PROJECT_ROOT=$(pwd)
PROJECT_NAME="QuickMotion"
SCHEME="QuickMotion"

# Get version from argument or read from xcconfig
if [ -n "$1" ]; then
    VERSION="$1"
else
    VERSION=$(grep "MARKETING_VERSION" Config/Shared.xcconfig | cut -d'=' -f2 | tr -d ' ')
fi

echo "=== Releasing $PROJECT_NAME $VERSION ==="

# Paths
ARCHIVE_PATH="$PROJECT_ROOT/build/$PROJECT_NAME.xcarchive"
EXPORT_PATH="$PROJECT_ROOT/build/export"
APP_PATH="$EXPORT_PATH/$PROJECT_NAME.app"
ZIP_NAME="$PROJECT_NAME-$VERSION.zip"
ZIP_PATH="$PROJECT_ROOT/build/$ZIP_NAME"
RELEASES_DIR="$PROJECT_ROOT/releases"

# Sparkle tools (from DerivedData after building)
DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData"
SPARKLE_BIN=$(find "$DERIVED_DATA" -path "*$PROJECT_NAME*/SourcePackages/artifacts/sparkle/Sparkle/bin" -type d 2>/dev/null | head -1)

if [ -z "$SPARKLE_BIN" ]; then
    echo "❌ Sparkle tools not found. Build the project in Xcode first."
    exit 1
fi

# Clean build directory
rm -rf "$PROJECT_ROOT/build"
mkdir -p "$PROJECT_ROOT/build"
mkdir -p "$RELEASES_DIR"

# Step 1: Archive
echo ""
echo "📦 Step 1: Creating archive..."
xcodebuild archive \
    -project "$PROJECT_NAME.xcodeproj" \
    -scheme "$SCHEME" \
    -archivePath "$ARCHIVE_PATH" \
    -configuration Release \
    CODE_SIGN_IDENTITY="Developer ID Application" \
    | grep -E "(Archive|error:|warning:)" || true

if [ ! -d "$ARCHIVE_PATH" ]; then
    echo "❌ Archive failed"
    exit 1
fi
echo "✅ Archive created"

# Step 2: Export
echo ""
echo "📤 Step 2: Exporting app..."

# Create export options plist
cat > "$PROJECT_ROOT/build/ExportOptions.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$PROJECT_ROOT/build/ExportOptions.plist" \
    | grep -E "(Export|error:|warning:)" || true

if [ ! -d "$APP_PATH" ]; then
    echo "❌ Export failed"
    exit 1
fi
echo "✅ App exported"

# Step 3: Notarize (optional but recommended)
echo ""
echo "🔏 Step 3: Notarizing..."
echo "   (This may take a few minutes)"

xcrun notarytool submit "$APP_PATH" \
    --keychain-profile "notarytool" \
    --wait 2>&1 | tee "$PROJECT_ROOT/build/notarize.log" || {
    echo "⚠️  Notarization failed or profile not set up."
    echo "   To set up: xcrun notarytool store-credentials notarytool"
    echo "   Continuing without notarization..."
}

# Staple the notarization ticket
xcrun stapler staple "$APP_PATH" 2>/dev/null || echo "   (Stapling skipped)"

# Step 4: Create ZIP
echo ""
echo "📁 Step 4: Creating ZIP..."
cd "$EXPORT_PATH"
ditto -c -k --keepParent "$PROJECT_NAME.app" "$ZIP_PATH"
cd "$PROJECT_ROOT"
echo "✅ ZIP created: $ZIP_PATH"

# Step 5: Sign for Sparkle
echo ""
echo "🔑 Step 5: Signing for Sparkle..."
SIGNATURE=$("$SPARKLE_BIN/sign_update" "$ZIP_PATH")
echo "   Signature: $SIGNATURE"

# Step 6: Get file info for appcast
echo ""
echo "📋 Step 6: Gathering release info..."
FILE_SIZE=$(stat -f%z "$ZIP_PATH")
PUB_DATE=$(date -R)

echo ""
echo "=== Release Info ==="
echo "Version: $VERSION"
echo "File: $ZIP_NAME"
echo "Size: $FILE_SIZE bytes"
echo "Date: $PUB_DATE"
echo ""
echo "Sparkle signature:"
echo "$SIGNATURE"
echo ""

# Copy to releases folder
cp "$ZIP_PATH" "$RELEASES_DIR/"
echo "✅ Copied to releases/$ZIP_NAME"

# Generate appcast snippet
echo ""
echo "=== Add this to appcast.xml ==="
cat << APPCAST

        <item>
            <title>Version $VERSION</title>
            <pubDate>$PUB_DATE</pubDate>
            <sparkle:version>$VERSION</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <enclosure
                url="https://github.com/Xpycode/QuickMotion/releases/download/v$VERSION/$ZIP_NAME"
                $SIGNATURE
                type="application/octet-stream"
            />
        </item>
APPCAST

echo ""
echo "=== Next Steps ==="
echo "1. Update appcast.xml with the item above"
echo "2. Commit and push appcast.xml"
echo "3. Create GitHub Release v$VERSION"
echo "4. Upload releases/$ZIP_NAME to the release"
echo ""
echo "✅ Release build complete!"
