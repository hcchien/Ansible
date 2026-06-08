#!/bin/bash
# Build and install a standalone iOS release build for local staging testing.
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

IOS_DEVICE_ID="${IOS_DEVICE_ID:-}"
IOS_DEVICE_CONNECTION="${IOS_DEVICE_CONNECTION:-wireless}"
ANSIBLE_APP_ENV="${ANSIBLE_APP_ENV:-staging}"
ANSIBLE_USES_REAL_RUST_BRIDGE="${ANSIBLE_USES_REAL_RUST_BRIDGE:-true}"
WATCHDOG_CLANG_PROBE=false
WATCHDOG_CLANG_PROBE_AFTER_SECONDS="${WATCHDOG_CLANG_PROBE_AFTER_SECONDS:-45}"
STAY_ATTACHED=false
DRY_RUN=false

usage() {
  cat <<'USAGE'
Usage: scripts/install_ios_staging_release.sh [options]

Builds and installs a release iOS app with staging/local dart-defines.

Options:
  --watchdog-clang-probe  Kill stuck descendant clang metadata probes after
                          WATCHDOG_CLANG_PROBE_AFTER_SECONDS seconds.
  --stay-attached         Leave flutter run attached after install/launch.
  --dry-run               Print the resolved command without running it.
  -h, --help              Show this help.

Environment:
  IOS_DEVICE_ID                         iOS device UDID. Required.
  IOS_DEVICE_CONNECTION                 Flutter device connection, default wireless.
  ANSIBLE_LOCAL_HOST_IP or LOCAL_HOST_IP Host IP reachable from the phone.
  ANSIBLE_RELAY_BASE_URL                Defaults to http://<host-ip>:4001.
  ANSIBLE_ISSUER_BASE_URL               Defaults to http://<host-ip>:4002.
  ANSIBLE_ATPROTO_BASE_URL              Defaults to relay base URL.
  WATCHDOG_CLANG_PROBE_AFTER_SECONDS    Default 45.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --watchdog-clang-probe)
      WATCHDOG_CLANG_PROBE=true
      shift
      ;;
    --stay-attached)
      STAY_ATTACHED=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$IOS_DEVICE_ID" ]]; then
  echo "IOS_DEVICE_ID is required. Run 'flutter devices' to find the device UDID." >&2
  exit 1
fi

detect_host_ip() {
  if [[ -n "${ANSIBLE_LOCAL_HOST_IP:-}" ]]; then
    printf '%s\n' "$ANSIBLE_LOCAL_HOST_IP"
    return
  fi
  if [[ -n "${LOCAL_HOST_IP:-}" ]]; then
    printf '%s\n' "$LOCAL_HOST_IP"
    return
  fi
  ipconfig getifaddr en0 2>/dev/null || true
}

LOCAL_IP="$(detect_host_ip)"
if [[ -z "$LOCAL_IP" ]]; then
  echo "Could not detect local host IP. Set ANSIBLE_LOCAL_HOST_IP." >&2
  exit 1
fi

ANSIBLE_RELAY_BASE_URL="${ANSIBLE_RELAY_BASE_URL:-http://${LOCAL_IP}:4001}"
ANSIBLE_ISSUER_BASE_URL="${ANSIBLE_ISSUER_BASE_URL:-http://${LOCAL_IP}:4002}"
ANSIBLE_ATPROTO_BASE_URL="${ANSIBLE_ATPROTO_BASE_URL:-$ANSIBLE_RELAY_BASE_URL}"
# One-shot: wipe the local DID/passkeys/keypair on launch so a fresh identity is
# created and anchored against the active relay. Use when an identity anchored on
# an old relay can't re-anchor on a newly-pointed relay. Rebuild with =false after.
ANSIBLE_RESET_LOCAL_IDENTITY_ON_START="${ANSIBLE_RESET_LOCAL_IDENTITY_ON_START-false}"
# Use `-` (not `:-`) so an explicitly-set empty value is honored: when the
# AppView is not deployed (e.g. dev pointing only at relay+issuer), pass
# ANSIBLE_APPVIEW_BASE_URL="" to disable AppView-backed discovery/home-timeline.
ANSIBLE_APPVIEW_BASE_URL="${ANSIBLE_APPVIEW_BASE_URL-http://${LOCAL_IP}:4003}"
ANSIBLE_USE_APPVIEW_FEED="${ANSIBLE_USE_APPVIEW_FEED-true}"
# Phase C: server-materialized home timeline (fan-out-on-write, GET /api/v1/home).
ANSIBLE_USE_APPVIEW_HOME_TIMELINE="${ANSIBLE_USE_APPVIEW_HOME_TIMELINE-false}"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/elix-ios-release.XXXXXX")"
stdin_fifo="$tmp_dir/flutter-stdin"
log_file="$tmp_dir/flutter-run.log"
mkfifo "$stdin_fifo"

cleanup() {
  local status=$?
  exec 3>&- 2>/dev/null || true
  rm -rf "$tmp_dir"
  trap - EXIT INT TERM
  exit "$status"
}
trap cleanup EXIT INT TERM

descendants_of() {
  local root="$1"
  local pids=" $root "
  local changed=1
  local pid ppid

  while [[ "$changed" -eq 1 ]]; do
    changed=0
    while read -r pid ppid; do
      if [[ "$pids" == *" $ppid "* && "$pids" != *" $pid "* ]]; then
        pids="${pids}${pid} "
        changed=1
      fi
    done < <(ps -axo pid=,ppid= 2>/dev/null || true)
  done

  printf '%s\n' "$pids"
}

kill_stuck_clang_probes() {
  local flutter_pid="$1"
  local descendants pid ppid command now first_seen_file first_seen age
  descendants="$(descendants_of "$flutter_pid")"
  now="$(date +%s)"

  while read -r pid ppid command; do
    if [[ "$descendants" != *" $pid "* ]]; then
      continue
    fi
    if [[ "$command" != *"/clang -v -E -dM"* ]]; then
      continue
    fi
    if [[ "$command" != *"/dev/null"* ]]; then
      continue
    fi

    first_seen_file="$tmp_dir/clang-probe-${pid}.first_seen"
    if [[ ! -f "$first_seen_file" ]]; then
      printf '%s\n' "$now" > "$first_seen_file"
      continue
    fi

    first_seen="$(cat "$first_seen_file" 2>/dev/null || printf '%s\n' "$now")"
    if [[ ! "$first_seen" =~ ^[0-9]+$ ]]; then
      first_seen="$now"
    fi

    age=$((now - first_seen))
    if [[ "$age" -ge "$WATCHDOG_CLANG_PROBE_AFTER_SECONDS" ]]; then
      echo "Killing stuck Xcode clang probe pid=$pid age=${age}s"
      kill "$pid" 2>/dev/null || true
      rm -f "$first_seen_file"
    fi
  done < <(ps -axo pid=,ppid=,command= -ww 2>/dev/null || true)
}

cmd=(
  flutter run
  --release
  -d "$IOS_DEVICE_ID"
  --device-connection "$IOS_DEVICE_CONNECTION"
  --dart-define="ANSIBLE_APP_ENV=$ANSIBLE_APP_ENV"
  --dart-define="ANSIBLE_USES_REAL_RUST_BRIDGE=$ANSIBLE_USES_REAL_RUST_BRIDGE"
  --dart-define="ANSIBLE_ISSUER_BASE_URL=$ANSIBLE_ISSUER_BASE_URL"
  --dart-define="ANSIBLE_RELAY_BASE_URL=$ANSIBLE_RELAY_BASE_URL"
  --dart-define="ANSIBLE_ATPROTO_BASE_URL=$ANSIBLE_ATPROTO_BASE_URL"
  --dart-define="ANSIBLE_APPVIEW_BASE_URL=$ANSIBLE_APPVIEW_BASE_URL"
  --dart-define="ANSIBLE_USE_APPVIEW_FEED=$ANSIBLE_USE_APPVIEW_FEED"
  --dart-define="ANSIBLE_USE_APPVIEW_HOME_TIMELINE=$ANSIBLE_USE_APPVIEW_HOME_TIMELINE"
  --dart-define="ANSIBLE_RESET_LOCAL_IDENTITY_ON_START=$ANSIBLE_RESET_LOCAL_IDENTITY_ON_START"
)

echo "Installing iOS release build"
echo "  app dir:                $APP_DIR"
echo "  device:                 $IOS_DEVICE_ID ($IOS_DEVICE_CONNECTION)"
echo "  env:                    $ANSIBLE_APP_ENV"
echo "  relay base URL:         $ANSIBLE_RELAY_BASE_URL"
echo "  appview base URL:       $ANSIBLE_APPVIEW_BASE_URL"
echo "  issuer base URL:        $ANSIBLE_ISSUER_BASE_URL"
echo "  AT Protocol base URL:   $ANSIBLE_ATPROTO_BASE_URL"
echo "  real Rust bridge:       $ANSIBLE_USES_REAL_RUST_BRIDGE"
echo "  clang probe watchdog:   $WATCHDOG_CLANG_PROBE"

if [[ "$DRY_RUN" == true ]]; then
  printf 'Command:'
  printf ' %q' "${cmd[@]}"
  printf '\n'
  exit 0
fi

cd "$APP_DIR"

exec 3<>"$stdin_fifo"
"${cmd[@]}" < "$stdin_fifo" > >(tee "$log_file") 2>&1 &
flutter_pid=$!
sent_quit=false

while kill -0 "$flutter_pid" 2>/dev/null; do
  if [[ "$WATCHDOG_CLANG_PROBE" == true ]]; then
    kill_stuck_clang_probes "$flutter_pid"
  fi

  if [[ "$STAY_ATTACHED" == false && "$sent_quit" == false ]] &&
    grep -q "Flutter run key commands" "$log_file" 2>/dev/null; then
    printf 'q' >&3
    sent_quit=true
  fi

  sleep 2
done

wait "$flutter_pid"
