#!/bin/bash
set -euo pipefail
# Usage: SPARKLE_BIN=/path/to/Sparkle/bin ./scripts/release.sh [version]
# Version is an assertion against the exported app, never a filename-only override.
PROJECT_ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$PROJECT_ROOT"
: "${SPARKLE_BIN:?Set SPARKLE_BIN to the intended Sparkle distribution bin directory}"
if [[ -z "${SPARKLE_KEY_FILE:-}" ]]; then
    export SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-quickmotion}"
fi
BUILD_PATH=$(mktemp -d "$PROJECT_ROOT/build-release.XXXXXX")
ARCHIVE_PATH="$BUILD_PATH/QuickMotion.xcarchive"
EXPORT_PATH="$BUILD_PATH/export"
APP_PATH="$EXPORT_PATH/QuickMotion.app"
echo "Build logs and intermediate artifacts: $BUILD_PATH" >&2
xcodebuild archive \
    -workspace 01_Project/QuickMotion.xcworkspace \
    -scheme QuickMotion -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE_PATH" \
    | tee "$BUILD_PATH/archive.log"
cat > "$BUILD_PATH/ExportOptions.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>developer-id</string>
<key>signingStyle</key><string>manual</string>
<key>teamID</key><string>FDMSRXXN73</string>
<key>signingCertificate</key><string>Developer ID Application</string>
</dict></plist>
PLIST
xcodebuild -exportArchive -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" -exportOptionsPlist "$BUILD_PATH/ExportOptions.plist" \
    | tee "$BUILD_PATH/export.log"
codesign --verify --deep --strict "$APP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$BUILD_PATH/notarization.zip"
if [[ -n "${NOTARY_KEY_PATH:-}" ]]; then
    : "${NOTARY_KEY_ID:?Set NOTARY_KEY_ID}" "${NOTARY_ISSUER:?Set NOTARY_ISSUER}"
    NOTARY_AUTH=(--key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER")
else
    NOTARY_AUTH=(--keychain-profile "${NOTARY_PROFILE:-notarytool}")
fi
xcrun notarytool submit "$BUILD_PATH/notarization.zip" \
    "${NOTARY_AUTH[@]}" --wait --output-format json \
    > "$BUILD_PATH/notarization.json"
python3 - "$BUILD_PATH/notarization.json" <<'PY'
import json, sys
with open(sys.argv[1]) as stream:
    result = json.load(stream)
if result.get('status') != 'Accepted':
    raise SystemExit('Notarization was not accepted; release stopped.')
PY
xcrun stapler staple "$APP_PATH"
# Packaging rechecks Apple signing/ticket and verifies the final archive with its embedded key.
"$PROJECT_ROOT/scripts/sign-for-sparkle.sh" "$APP_PATH" "$@"
