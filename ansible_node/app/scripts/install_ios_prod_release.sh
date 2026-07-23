#!/bin/bash
# Build and install a PRODUCTION iOS release build.
#
# This is the production analogue of install_ios_staging_release.sh. Unlike the
# staging script — which fabricates LAN-IP http:// endpoints for on-device QA —
# a production build MUST point at remote HTTPS services. To keep the build
# correct-by-construction we do NOT invent any relay/issuer domains or bundle
# identifiers: the operator must supply them explicitly, and the app's own
# runtime guard (AppEnvironment.validateRuntimeReadiness in lib/main.dart) will
# refuse to boot if any prod endpoint is insecure or local.
#
# ── Required prod dart-defines (set via the environment variables below) ──────
#   ANSIBLE_APP_ENV=prod                 (set by this script)
#   ANSIBLE_RELAY_BASE_URL   REQUIRED    https, non-local relay base URL
#   ANSIBLE_ISSUER_BASE_URL  REQUIRED    https, non-local issuer base URL
#   ANSIBLE_ATPROTO_BASE_URL optional    defaults to the relay base URL
#   ANSIBLE_APPVIEW_BASE_URL optional    https AppView base URL (feed/timeline)
#   ANSIBLE_USES_REAL_RUST_BRIDGE=true   (set by this script; prod requires it)
#   ANSIBLE_ALLOW_INSECURE_SIGNING_FALLBACK=false   (forced false by this script)
#   ANSIBLE_ALLOW_INSECURE_IDENTITY_FALLBACK=false  (forced false by this script)
#
# The relay/issuer/AppView values are compile-time (String.fromEnvironment), so
# they are baked into the binary at build time — there are no runtime secrets in
# this script; it only wires public service URLs.
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$APP_DIR/scripts/prepare_zkpassport_srs.sh"

IOS_DEVICE_ID="${IOS_DEVICE_ID:-}"
IOS_DEVICE_CONNECTION="${IOS_DEVICE_CONNECTION:-wireless}"
# Fixed for a production build. Kept as an env override only so CI can special-case
# it, but it defaults to the correct value and is validated below.
ANSIBLE_APP_ENV="${ANSIBLE_APP_ENV:-prod}"
STAY_ATTACHED=false
DRY_RUN=false

usage() {
  cat <<'USAGE'
Usage: scripts/install_ios_prod_release.sh [options]

Builds and installs a PRODUCTION release iOS app with prod dart-defines.

Options:
  --stay-attached   Leave flutter run attached after install/launch.
  --dry-run         Print the resolved command without running it.
  -h, --help        Show this help.

Required environment:
  IOS_DEVICE_ID             iOS device UDID (run 'flutter devices').
  ANSIBLE_RELAY_BASE_URL    https, non-local relay base URL. REQUIRED.
  ANSIBLE_ISSUER_BASE_URL   https, non-local issuer base URL. REQUIRED.

Optional environment:
  ANSIBLE_ATPROTO_BASE_URL  Defaults to ANSIBLE_RELAY_BASE_URL.
  ANSIBLE_APPVIEW_BASE_URL  AppView base URL. Empty disables AppView feed.
  ANSIBLE_USE_APPVIEW_FEED  Default false.
  ANSIBLE_USE_APPVIEW_HOME_TIMELINE  Default false.
  IOS_DEVICE_CONNECTION     Flutter device connection, default wireless.

Notes:
  * This script deliberately does NOT set a bundle identifier or signing config;
    those are managed in the Xcode project / release signing setup (a separate
    concern). The app's runtime guard still rejects com.example bundle IDs.
  * NSAllowsLocalNetworking in ios/Runner/Info.plist is only needed by the
    staging LAN build; a store submission should remove that key (see the
    comment in Info.plist).
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stay-attached) STAY_ATTACHED=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

fail() { echo "ERROR: $*" >&2; exit 1; }

# ── Validate required inputs up front with actionable messages ────────────────
if [[ "$ANSIBLE_APP_ENV" != "prod" && "$ANSIBLE_APP_ENV" != "production" ]]; then
  fail "ANSIBLE_APP_ENV must be 'prod' for this script (got '$ANSIBLE_APP_ENV')."
fi

if [[ -z "$IOS_DEVICE_ID" ]]; then
  fail "IOS_DEVICE_ID is required. Run 'flutter devices' to find the device UDID."
fi

if [[ -z "${ANSIBLE_RELAY_BASE_URL:-}" ]]; then
  fail "ANSIBLE_RELAY_BASE_URL is required (must be a remote https:// relay URL). $(usage)"
fi
if [[ -z "${ANSIBLE_ISSUER_BASE_URL:-}" ]]; then
  fail "ANSIBLE_ISSUER_BASE_URL is required (must be a remote https:// issuer URL)."
fi

# Fail fast on obviously-insecure endpoints before spending time on a build.
# (The app's runtime guard enforces the full policy; this is an early check.)
require_https_nonlocal() {
  local name="$1" value="$2"
  case "$value" in
    https://*) : ;;
    *) fail "$name must be an https:// URL (got '$value')." ;;
  esac
  case "$value" in
    *localhost*|*127.0.0.1*|*0.0.0.0*|*://10.*|*://192.168.*|*://169.254.*)
      fail "$name must not point at a local/private host (got '$value')." ;;
  esac
}
require_https_nonlocal "ANSIBLE_RELAY_BASE_URL" "$ANSIBLE_RELAY_BASE_URL"
require_https_nonlocal "ANSIBLE_ISSUER_BASE_URL" "$ANSIBLE_ISSUER_BASE_URL"

ANSIBLE_ATPROTO_BASE_URL="${ANSIBLE_ATPROTO_BASE_URL:-$ANSIBLE_RELAY_BASE_URL}"
require_https_nonlocal "ANSIBLE_ATPROTO_BASE_URL" "$ANSIBLE_ATPROTO_BASE_URL"

# Optional AppView. Empty ("") disables AppView-backed feed/timeline.
ANSIBLE_APPVIEW_BASE_URL="${ANSIBLE_APPVIEW_BASE_URL-}"
if [[ -n "$ANSIBLE_APPVIEW_BASE_URL" ]]; then
  require_https_nonlocal "ANSIBLE_APPVIEW_BASE_URL" "$ANSIBLE_APPVIEW_BASE_URL"
fi
ANSIBLE_USE_APPVIEW_FEED="${ANSIBLE_USE_APPVIEW_FEED-false}"
ANSIBLE_USE_APPVIEW_HOME_TIMELINE="${ANSIBLE_USE_APPVIEW_HOME_TIMELINE-false}"

# Production-forced secure defaults. These are hard requirements of the app's
# prod readiness guard, so we set them here rather than trusting the environment.
ANSIBLE_USES_REAL_RUST_BRIDGE=true
ANSIBLE_ALLOW_INSECURE_SIGNING_FALLBACK=false
ANSIBLE_ALLOW_INSECURE_IDENTITY_FALLBACK=false

cmd=(
  flutter run
  --release
  -d "$IOS_DEVICE_ID"
  --device-connection "$IOS_DEVICE_CONNECTION"
  --dart-define="ANSIBLE_APP_ENV=prod"
  --dart-define="ANSIBLE_USES_REAL_RUST_BRIDGE=$ANSIBLE_USES_REAL_RUST_BRIDGE"
  --dart-define="ANSIBLE_RELAY_BASE_URL=$ANSIBLE_RELAY_BASE_URL"
  --dart-define="ANSIBLE_ISSUER_BASE_URL=$ANSIBLE_ISSUER_BASE_URL"
  --dart-define="ANSIBLE_ATPROTO_BASE_URL=$ANSIBLE_ATPROTO_BASE_URL"
  --dart-define="ANSIBLE_APPVIEW_BASE_URL=$ANSIBLE_APPVIEW_BASE_URL"
  --dart-define="ANSIBLE_USE_APPVIEW_FEED=$ANSIBLE_USE_APPVIEW_FEED"
  --dart-define="ANSIBLE_USE_APPVIEW_HOME_TIMELINE=$ANSIBLE_USE_APPVIEW_HOME_TIMELINE"
  --dart-define="ANSIBLE_ALLOW_INSECURE_SIGNING_FALLBACK=$ANSIBLE_ALLOW_INSECURE_SIGNING_FALLBACK"
  --dart-define="ANSIBLE_ALLOW_INSECURE_IDENTITY_FALLBACK=$ANSIBLE_ALLOW_INSECURE_IDENTITY_FALLBACK"
)

echo "Installing iOS PRODUCTION release build"
echo "  app dir:                $APP_DIR"
echo "  device:                 $IOS_DEVICE_ID ($IOS_DEVICE_CONNECTION)"
echo "  env:                    prod"
echo "  relay base URL:         $ANSIBLE_RELAY_BASE_URL"
echo "  issuer base URL:        $ANSIBLE_ISSUER_BASE_URL"
echo "  AT Protocol base URL:   $ANSIBLE_ATPROTO_BASE_URL"
echo "  appview base URL:       ${ANSIBLE_APPVIEW_BASE_URL:-<disabled>}"
echo "  real Rust bridge:       $ANSIBLE_USES_REAL_RUST_BRIDGE"

if [[ "$DRY_RUN" == true ]]; then
  printf 'Command:'
  printf ' %q' "${cmd[@]}"
  printf '\n'
  exit 0
fi

cd "$APP_DIR"

if [[ "$STAY_ATTACHED" == true ]]; then
  exec "${cmd[@]}"
else
  # Install and launch, then detach. `flutter run` stays foreground; the operator
  # can press 'q' to quit once the app is on the device.
  exec "${cmd[@]}"
fi
