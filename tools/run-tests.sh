#!/usr/bin/env bash
# Runs the whole suite with the preconditions the UI tests need.
#
# Two of them are easy to forget and both fail in a way that looks like an app bug rather
# than a missing precondition:
#   - location permission, which a reinstall resets;
#   - a location simulation actually running, without which a "drive" covers 0 m and the
#     distance assertion fails while the app is behaving correctly.
#
# StoreKit Testing is inert on the iOS 26.x runtimes, so the default device is an 18.6 one.
set -euo pipefail
cd "$(dirname "$0")/.."

DEVICE_ID="${MILEAGE_TEST_DEVICE:-4E7D3A99-767A-4FE0-BCA1-5084F2CC173D}"
BUNDLE_ID="Mileage.lno.company"

python3 gen_pbxproj.py

xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE_ID" -b >/dev/null 2>&1 || true
xcrun simctl privacy "$DEVICE_ID" grant location-always "$BUNDLE_ID" 2>/dev/null || true

# Paris → the A6, fed for long enough to outlast the whole UI suite. Killed on exit so a
# stale simulation cannot leak into the next run.
xcrun simctl location "$DEVICE_ID" start --speed=25 --interval=1 \
  48.8566,2.3522 48.8500,2.3000 48.8400,2.2600 48.8300,2.2200 48.8200,2.1800 \
  48.8100,2.1500 48.8049,2.1204 48.7900,2.0900 48.7800,2.0600 48.7700,2.0300 >/dev/null 2>&1 &
LOCATION_PID=$!
trap 'kill $LOCATION_PID 2>/dev/null || true; xcrun simctl location "$DEVICE_ID" clear 2>/dev/null || true' EXIT
sleep 2

xcodebuild test \
  -project MileagePocket.xcodeproj \
  -scheme MileagePocket \
  -destination "id=$DEVICE_ID" \
  -derivedDataPath build/dd \
  SYMROOT="$(pwd)/build/sym" \
  "$@"
