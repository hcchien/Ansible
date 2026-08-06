#!/usr/bin/env bash
# Record the seeded iOS screen tour as an App Review walkthrough video.
# The tour uses local fixture data only; it does not create or export a DID.
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIM_ID="${IOS_SIM_ID:?IOS_SIM_ID is required}"
OUTPUT_PATH="${OUTPUT_PATH:?OUTPUT_PATH is required}"
TOUR_HOLD_SECONDS="${TOUR_HOLD_SECONDS:-3}"
SCREENSHOT_OUTPUT_DIR="${SCREENSHOT_OUTPUT_DIR:-../../design/app-store-screenshots/recording-stills}"

mkdir -p "$(dirname "$OUTPUT_PATH")"

xcrun simctl boot "$SIM_ID" 2>/dev/null || true
xcrun simctl bootstatus "$SIM_ID" -b

cd "$APP_DIR"
IOS_SIM_ID="$SIM_ID" \
SCREENSHOT_OUTPUT_DIR="$SCREENSHOT_OUTPUT_DIR" \
TOUR_HOLD_SECONDS="$TOUR_HOLD_SECONDS" \
./scripts/capture_screens.sh &
TOUR_PID=$!

# Starting capture after Runner launches avoids recording the Simulator home
# screen while Flutter compiles the integration-test bundle.
for _ in $(seq 1 180); do
  if xcrun simctl spawn "$SIM_ID" launchctl print system 2>/dev/null | grep -q 'Runner'; then
    break
  fi
  sleep 1
done

if ! xcrun simctl spawn "$SIM_ID" launchctl print system 2>/dev/null | grep -q 'Runner'; then
  echo 'Timed out waiting for Runner to launch.' >&2
  wait "$TOUR_PID"
  exit 1
fi

xcrun simctl io "$SIM_ID" recordVideo --codec=h264 "$OUTPUT_PATH" &
RECORDER_PID=$!

stop_recorder() {
  kill -INT "$RECORDER_PID" 2>/dev/null || true
  wait "$RECORDER_PID" 2>/dev/null || true
}
trap stop_recorder EXIT

wait "$TOUR_PID"
