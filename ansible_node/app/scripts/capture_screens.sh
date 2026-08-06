#!/usr/bin/env bash
# Capture the current app screens on an iOS simulator and write a PNG per screen
# to design/current-screens/ (ready to drop into Claude design for style work).
# Set SCREENSHOT_OUTPUT_DIR to capture an additional set without overwriting the
# default design-reference images.
#
# Mounts each real screen with seeded zh-Hant data via integration_test, so the
# run never waits on the network or a registered identity. A background watchdog
# kills the stuck Xcode `clang -v` metadata probe this machine hangs on (the
# same issue install_ios_staging_release.sh --watchdog-clang-probe handles).
#
# Usage: IOS_SIM_ID=<udid> ./scripts/capture_screens.sh
#        SCREENSHOT_OUTPUT_DIR=../../design/app-store-screenshots/iphone \
#          IOS_SIM_ID=<udid> ./scripts/capture_screens.sh
#        (defaults to the iPhone 13 Pro simulator if IOS_SIM_ID is unset)
set -euo pipefail

cd "$(dirname "$0")/.."

SIM_ID="${IOS_SIM_ID:-159D7590-D192-4A72-9A7A-EAD1ACC34437}"
SCREENSHOT_OUTPUT_DIR="${SCREENSHOT_OUTPUT_DIR:-../../design/current-screens}"
TOUR_HOLD_SECONDS="${TOUR_HOLD_SECONDS:-0}"

echo "Booting simulator $SIM_ID ..."
xcrun simctl boot "$SIM_ID" 2>/dev/null || true
xcrun simctl bootstatus "$SIM_ID" -b >/dev/null 2>&1 || true
open -a Simulator >/dev/null 2>&1 || true

# Watchdog: kill any clang metadata probe that has been stuck for >30s while the
# build runs. Exits once `flutter drive` is gone.
(
  for _ in $(seq 1 240); do
    pgrep -f "drive --driver=test_driver/screenshot_driver" >/dev/null 2>&1 || break
    ps -axo pid,etime,command | grep "clang -v -E -dM" | grep "/dev/null" | grep -v grep | awk '{
      split($2,a,":"); n=length(a); secs=a[n]; mins=(n>1?a[n-1]:0);
      total=mins*60+secs; if (n>2) total+=a[n-2]*3600;
      if (total>30) print $1
    }' | xargs -r kill -9 2>/dev/null || true
    sleep 15
  done
) &
WATCHDOG_PID=$!
trap 'kill "$WATCHDOG_PID" 2>/dev/null || true' EXIT

drive_args=(
  --driver=test_driver/screenshot_driver.dart \
  --target=integration_test/screens_tour.dart \
  -d "$SIM_ID"
)

if [[ "$TOUR_HOLD_SECONDS" != "0" ]]; then
  drive_args+=("--dart-define=SCREENSHOT_TOUR_HOLD_SECONDS=$TOUR_HOLD_SECONDS")
fi

flutter drive "${drive_args[@]}"

echo "Screens written to $SCREENSHOT_OUTPUT_DIR"
ls -1 "$SCREENSHOT_OUTPUT_DIR"/*.png
