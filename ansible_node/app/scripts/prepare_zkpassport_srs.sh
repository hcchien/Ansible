#!/bin/bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$APP_DIR/ios/srs_21.local"
URL="https://cdn.zkpassport.id/srs/21.srs"
EXPECTED_SHA256="7d368f9342b99252a06249e46a3edfbda9aa2e9afb482bfe848245ab538c6996"

verify() {
  [[ -f "$DEST" ]] &&
    [[ "$(shasum -a 256 "$DEST" | awk '{print $1}')" == "$EXPECTED_SHA256" ]]
}

if verify; then
  echo "Pinned ZKPassport SRS is ready."
  exit 0
fi

rm -f "$DEST"
curl --fail --location --retry 3 --output "$DEST.tmp" "$URL"
actual="$(shasum -a 256 "$DEST.tmp" | awk '{print $1}')"
if [[ "$actual" != "$EXPECTED_SHA256" ]]; then
  rm -f "$DEST.tmp"
  echo "ZKPassport SRS hash mismatch: expected $EXPECTED_SHA256, got $actual" >&2
  exit 1
fi
mv "$DEST.tmp" "$DEST"
echo "Pinned ZKPassport SRS downloaded and verified."
