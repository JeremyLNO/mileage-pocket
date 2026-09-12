#!/usr/bin/env bash
# Archive Mileage Pocket and upload it to TestFlight from this Mac.
#
#   export ASC_KEY_ID=88BAZ9XND3
#   export ASC_ISSUER_ID=***ASC-ISSUER-ID-RETIRE***
#   export ASC_KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"
#   ./release.sh
#
# The build number defaults to a timestamp, so every upload is unique and no two archives
# ever collide in App Store Connect.
set -euo pipefail

: "${ASC_KEY_ID:?set ASC_KEY_ID}"
: "${ASC_ISSUER_ID:?set ASC_ISSUER_ID}"
: "${ASC_KEY_PATH:?set ASC_KEY_PATH to your AuthKey_*.p8}"

PROJ="$(cd "$(dirname "$0")" && pwd)"
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%y%m%d%H%M)}"
ARCHIVE="$PROJ/build/MileagePocket.xcarchive"

python3 "$PROJ/gen_pbxproj.py"

echo "▶︎ Archiving (build $BUILD_NUMBER)…"
xcodebuild archive \
  -project "$PROJ/MileagePocket.xcodeproj" \
  -scheme MileagePocket \
  -configuration Release \
  -archivePath "$ARCHIVE" \
  -destination 'generic/platform=iOS' \
  -allowProvisioningUpdates \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"

echo "▶︎ Exporting and uploading to TestFlight…"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$PROJ/ExportOptions.plist" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"

echo "✅ Uploaded as build $BUILD_NUMBER. Confirm it in App Store Connect → TestFlight:"
echo "   an upload that is accepted is not yet a build that processed."
