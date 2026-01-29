#!/bin/bash
set -e

# Sign exported app for Sparkle updates
# Usage: ./scripts/sign-for-sparkle.sh /path/to/QuickMotion.app [version]
#
# After exporting from Xcode Organizer (Developer ID, notarized):
#   ./scripts/sign-for-sparkle.sh ~/Desktop/QuickMotion.app 1.1.0

if [ -z "$1" ]; then
    echo "Usage: ./scripts/sign-for-sparkle.sh /path/to/QuickMotion.app [version]"
    exit 1
fi

APP_PATH="$1"
PROJECT_NAME="QuickMotion"

cd "$(dirname "$0")/.."
PROJECT_ROOT=$(pwd)

# Get version from argument, app bundle, or xcconfig
if [ -n "$2" ]; then
    VERSION="$2"
else
    VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist" 2>/dev/null || \
              grep "MARKETING_VERSION" Config/Shared.xcconfig | cut -d'=' -f2 | tr -d ' ')
fi

echo "=== Signing $PROJECT_NAME $VERSION for Sparkle ==="

# Find Sparkle tools
DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData"
SPARKLE_BIN=$(find "$DERIVED_DATA" -path "*$PROJECT_NAME*/SourcePackages/artifacts/sparkle/Sparkle/bin" -type d 2>/dev/null | head -1)

if [ -z "$SPARKLE_BIN" ]; then
    echo "❌ Sparkle tools not found. Build the project in Xcode first."
    exit 1
fi

# Paths
RELEASES_DIR="$PROJECT_ROOT/releases"
mkdir -p "$RELEASES_DIR"

ZIP_NAME="$PROJECT_NAME-$VERSION.zip"
ZIP_PATH="$RELEASES_DIR/$ZIP_NAME"

# Create ZIP
echo ""
echo "📁 Creating ZIP..."
APP_DIR=$(dirname "$APP_PATH")
APP_NAME=$(basename "$APP_PATH")
cd "$APP_DIR"
ditto -c -k --keepParent "$APP_NAME" "$ZIP_PATH"
cd "$PROJECT_ROOT"
echo "✅ ZIP created: $ZIP_PATH"

# Sign for Sparkle
echo ""
echo "🔑 Signing for Sparkle..."
SIGNATURE=$("$SPARKLE_BIN/sign_update" "$ZIP_PATH")
echo "   $SIGNATURE"

# Get file info
FILE_SIZE=$(stat -f%z "$ZIP_PATH")
PUB_DATE=$(date -R)

# Output appcast item
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
                length="$FILE_SIZE"
                type="application/octet-stream"
            />
        </item>
APPCAST

echo ""
echo "=== Next Steps ==="
echo "1. Add the item above to appcast.xml (newest first)"
echo "2. Commit and push appcast.xml"
echo "3. Create GitHub Release v$VERSION"
echo "4. Upload $ZIP_PATH to the release"
echo ""
echo "✅ Done!"
