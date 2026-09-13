#!/usr/bin/env bash
# Produces the App Store screenshots, straight from the simulator.
#
# No UI automation: the app opens on the right screen from a launch argument, so each shot is
# one launch and one `simctl io screenshot`. That is deliberate — driving a UI test to a
# screen and attaching images means digging them back out of an .xcresult, and every timing
# flake there produces a *wrong* image rather than a failure.
#
# 6.9" (1290 × 2796) is the size App Store Connect accepts for every modern iPhone.
set -euo pipefail
cd "$(dirname "$0")/.."

DEVICE="${SHOT_DEVICE:-723833F4-0304-406C-9AC7-6F360E508C33}"   # iPhone 16 Plus
BUNDLE_ID="Mileage.lno.company"
OUT="${SHOT_OUT:-docs/screenshots}"
DD="${SHOT_DD:-/tmp/mp-shots-dd}"

mkdir -p "$OUT"

python3 gen_pbxproj.py >/dev/null
xcodebuild build -project MileagePocket.xcodeproj -scheme MileagePocket \
  -destination "id=$DEVICE" -derivedDataPath "$DD" SYMROOT=/tmp/mp-shots-sym >/dev/null

APP=$(find /tmp/mp-shots-sym -name "MileagePocket.app" -path "*Debug-iphonesimulator*" | head -1)
[ -n "$APP" ] || { echo "no app built"; exit 1; }

xcrun simctl boot "$DEVICE" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE" -b >/dev/null 2>&1 || true
# The status bar is part of the image: a real clock and a half-empty battery date a listing.
xcrun simctl status_bar "$DEVICE" override --time "9:41" --batteryState charged --batteryLevel 100 \
  --cellularMode active --cellularBars 4 --dataNetwork wifi --wifiMode active --wifiBars 3
xcrun simctl install "$DEVICE" "$APP"

shoot() {
  local name="$1"; shift
  xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl launch "$DEVICE" "$BUNDLE_ID" "$@" >/dev/null
  sleep "${SHOT_SETTLE:-4}"
  xcrun simctl io "$DEVICE" screenshot --type=png "$OUT/$name.png" >/dev/null
  echo "  $name"
}

echo "▶︎ Capturing into $OUT"
shoot 01-home           --demo --reset-data
shoot 02-trips          --demo --tab=trips
shoot 03-trip           --demo --tab=trips --open-last-trip
shoot 04-reports        --demo --tab=reports
shoot 05-settings       --demo --tab=settings
shoot 06-paywall        --demo-data-only --fake-store --screen=paywall

xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl status_bar "$DEVICE" clear

echo "▶︎ Sizes:"
for f in "$OUT"/*.png; do
  printf '   %-22s %s\n' "$(basename "$f")" "$(sips -g pixelWidth -g pixelHeight "$f" | awk '/pixel/{printf "%s ", $2}')"
done
