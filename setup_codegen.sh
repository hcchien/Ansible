#!/usr/bin/env bash
# =============================================================================
# setup_codegen.sh — Tris-Aura V1.1 one-shot build & codegen
# =============================================================================
#
# Run this from the repository root after a fresh clone or whenever you change
# ansible_rust_core/src/api.rs or any Drift schema file.
#
# What it does:
#   1. Checks prerequisites (Rust, cargo, flutter, dart, frb-codegen)
#   2. Builds the Rust crate (debug + release for the host platform)
#   3. Runs flutter_rust_bridge_codegen to emit frb_generated.dart
#   4. Runs `dart run build_runner build` in ansible_core/store (Drift schema)
#   5. Runs `flutter pub get` in the app package
#   6. Optionally runs `flutter test` across all Dart packages
#
# Prerequisites (install once):
#   brew install rustup-init && rustup-init -y
#   cargo install flutter_rust_bridge_codegen --version 2.4.0
#   # Flutter SDK must already be on PATH
#
# Usage:
#   chmod +x setup_codegen.sh
#   ./setup_codegen.sh          # build + codegen + Drift
#   ./setup_codegen.sh --test   # also run all Dart tests afterwards
#   ./setup_codegen.sh --clean  # cargo clean + build_runner clean first

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"

# ── Colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'

step()  { echo -e "\n${BLUE}${BOLD}▶ $*${RESET}"; }
ok()    { echo -e "${GREEN}✓ $*${RESET}"; }
warn()  { echo -e "${YELLOW}⚠ $*${RESET}"; }
die()   { echo -e "${RED}✗ $*${RESET}" >&2; exit 1; }

RUN_TESTS=false
CLEAN=false
for arg in "$@"; do
  case $arg in
    --test)  RUN_TESTS=true ;;
    --clean) CLEAN=true ;;
  esac
done

# ── 1. Prerequisites check ────────────────────────────────────────────────────
step "Checking prerequisites"

check_cmd() {
  local cmd="$1" install_hint="$2"
  if command -v "$cmd" &>/dev/null; then
    ok "$cmd $(${cmd} --version 2>&1 | head -1)"
  else
    die "$cmd not found. $install_hint"
  fi
}

check_cmd cargo   "Install Rust: curl https://sh.rustup.rs -sSf | sh"
check_cmd flutter "Install Flutter SDK and add to PATH."
check_cmd dart    "Comes with Flutter SDK."

# flutter_rust_bridge_codegen 2.4.0 has a transitive `indicatif` version
# conflict that prevents compilation.  We try three approaches in order:
#
#   1. --locked  — uses the crate's own Cargo.lock (often resolves the conflict)
#   2. 2.7.0     — a later release where the conflict is fixed upstream
#   3. latest    — removes the version pin entirely as a last resort

_install_frb_codegen() {
  local version="$1" extra_flags="${2:-}"
  warn "Trying flutter_rust_bridge_codegen ${version:+v$version }${extra_flags}..."
  if cargo install flutter_rust_bridge_codegen \
      ${version:+--version "$version"} $extra_flags 2>&1; then
    return 0
  fi
  return 1
}

# Prefer 2.7.0: frb 2.4.0 has a path-handling bug where --dart-output is
# treated as a directory base, causing mkdir(frb_generated.dart) to collide
# with the pre-existing stub file.  2.7.0 fixes this.
# Both 2.4.x and 2.7.x have an indicatif transitive dep conflict unless
# installed with --locked.  Prefer 2.7.0 (fixes the dart-output path bug);
# fall back to 2.4.0 --locked if 2.7.0 --locked also fails.
if ! command -v flutter_rust_bridge_codegen &>/dev/null; then
  warn "flutter_rust_bridge_codegen not found — attempting install..."
  _install_frb_codegen "2.7.0" "--locked"   \
  || _install_frb_codegen "2.4.0" "--locked" \
  || _install_frb_codegen "" "--locked"      \
  || die "Could not install flutter_rust_bridge_codegen. See error above."
else
  FRB_VER="$(flutter_rust_bridge_codegen --version 2>&1 | head -1)"
  if [[ "$FRB_VER" == *"2.4."* ]]; then
    warn "frb 2.4.x has a known path bug — upgrading to 2.7.0 --locked..."
    _install_frb_codegen "2.7.0" "--locked --force" \
    || warn "Upgrade failed; proceeding with $FRB_VER (may hit EEXIST)"
  elif flutter_rust_bridge_codegen --version &>/dev/null; then
    ok "flutter_rust_bridge_codegen already installed"
  else
    warn "Existing flutter_rust_bridge_codegen appears broken — reinstalling..."
    _install_frb_codegen "2.7.0" "--locked"   \
    || _install_frb_codegen "2.4.0" "--locked" \
    || die "Reinstall failed."
  fi
fi

# After install, verify the binary works and surface the version
FRB_CODEGEN_VER="$(flutter_rust_bridge_codegen --version 2>&1 | head -1)"
ok "flutter_rust_bridge_codegen ${FRB_CODEGEN_VER}"

# If the installed version doesn't match the Dart package pin (2.4.0), warn the
# user so they can update ansible_core/did/pubspec.yaml accordingly.
if [[ "$FRB_CODEGEN_VER" != *"2.7."* && "$FRB_CODEGEN_VER" != *"2.4."* ]]; then
  warn "Codegen version ($FRB_CODEGEN_VER) may differ from the Dart package pin."
  warn "Check flutter_rust_bridge in ansible_core/did/pubspec.yaml."
fi

# ── 2. Optional clean ─────────────────────────────────────────────────────────
if $CLEAN; then
  step "Cleaning previous build artefacts"
  ( cd ansible_rust_core && cargo clean )
  ok "cargo clean done"

  STORE_PKG="$REPO_ROOT/ansible_core/store"
  ( cd "$STORE_PKG" && dart run build_runner clean --delete-conflicting-outputs ) || true
  ok "build_runner clean done"
fi

# ── 3. Build Rust crate ───────────────────────────────────────────────────────
step "Building ansible_rust_core (debug)"
( cd ansible_rust_core && cargo build )
ok "Debug build succeeded"

step "Building ansible_rust_core (release)"
( cd ansible_rust_core && cargo build --release )
ok "Release build succeeded"

# ── 4. flutter_rust_bridge_codegen ───────────────────────────────────────────
step "Running flutter_rust_bridge_codegen generate"

# frb ≥ 2.5 uses Rust module paths (crate::api) + --rust-root instead of
# file paths.  All three API modules are listed so Ed25519, ZKP, and CRDT
# functions are emitted into a single frb_generated.dart.
# frb 2.4 --dart-output / --c-output take FILE paths (not directories).
# frb canonicalize()s the dart output path, so the file must pre-exist.
# Wipe ALL frb_generated* files first — stale siblings (*.io.dart, *.web.dart)
# cause EEXIST when frb tries to create them with O_CREAT|O_EXCL.
FRB_DART_DIR="$REPO_ROOT/ansible_core/did/lib/src/rust"
FRB_C_DIR="$REPO_ROOT/ansible_core/did/ios/Classes"
FRB_DART_OUTPUT="$FRB_DART_DIR/frb_generated.dart"
FRB_C_OUTPUT="$FRB_C_DIR/frb_generated.h"

# frb 2.4 with web=true tries to create a DIRECTORY named frb_generated.dart/
# for platform-split impl files, which collides with the pre-touched file.
# --no-web collapses output to a single frb_generated.dart file, eliminating
# the subdirectory and the EEXIST.  The canonicalize() call still requires the
# output file to pre-exist, hence the touch after wiping.
rm -rf "$FRB_DART_DIR"
mkdir -p "$FRB_DART_DIR" "$FRB_C_DIR"
touch "$FRB_DART_OUTPUT"                         # must exist for frb canonicalize()
rm -f "$FRB_C_DIR"/frb_generated*.h
rm -f "$REPO_ROOT/ansible_rust_core/src/frb_generated.rs"

flutter_rust_bridge_codegen generate \
  --rust-input  "crate::api,crate::api_atproto,crate::api_zkp,crate::api_crdt" \
  --rust-root   "$REPO_ROOT/ansible_rust_core" \
  --dart-output "$FRB_DART_OUTPUT" \
  --c-output    "$FRB_C_OUTPUT" \
  --no-web

ok "frb_generated.dart written to ansible_core/did/lib/src/rust/"

# ── 5. Drift build_runner ─────────────────────────────────────────────────────
step "Running Drift build_runner (ansible_core/store)"

STORE_PKG="$REPO_ROOT/ansible_core/store"
( cd "$STORE_PKG" && flutter pub get )
( cd "$STORE_PKG" && dart run build_runner build --delete-conflicting-outputs )
ok "app_database.g.dart regenerated"

# ── 6. pub get for all Flutter packages ───────────────────────────────────────
step "Running flutter pub get across all packages"

FLUTTER_PKGS=(
  "ansible_core/domain"
  "ansible_core/store"
  "ansible_core/did"
  "ansible_core/vc"
  "ansible_node/app"
)

for pkg in "${FLUTTER_PKGS[@]}"; do
  if [[ -f "$REPO_ROOT/$pkg/pubspec.yaml" ]]; then
    echo "  pub get: $pkg"
    ( cd "$REPO_ROOT/$pkg" && flutter pub get --no-example ) 2>&1 | grep -E '(Resolving|Got|Changed)' || true
  fi
done
ok "pub get complete"

# ── 7. Optional: run tests ────────────────────────────────────────────────────
if $RUN_TESTS; then
  step "Running Dart / Flutter tests"

  TEST_PKGS=(
    "ansible_core/domain"
    "ansible_core/store"
    "ansible_core/did"
    "ansible_core/vc"
    "ansible_node/app"
  )

  PASS=0; FAIL=0
  for pkg in "${TEST_PKGS[@]}"; do
    if [[ -d "$REPO_ROOT/$pkg/test" ]]; then
      echo "  testing: $pkg"
      if ( cd "$REPO_ROOT/$pkg" && flutter test --reporter=compact ) 2>&1; then
        PASS=$((PASS+1))
      else
        FAIL=$((FAIL+1))
        warn "Tests failed in $pkg"
      fi
    fi
  done

  # Rust tests
  step "Running Rust tests"
  ( cd ansible_rust_core && cargo test )
  ok "Rust tests passed"

  echo ""
  if [[ $FAIL -eq 0 ]]; then
    ok "All $PASS Dart package(s) passed"
  else
    die "$FAIL Dart package(s) had test failures"
  fi
fi

# ── Elixir dependency reminder ─────────────────────────────────────────────────
echo ""
echo -e "${BOLD}Elixir relay (ansible_relay/phoenix):${RESET}"
echo "  cd ansible_relay/phoenix"
echo "  mix deps.get"
echo "  mix test          # run unit tests"
echo "  mix run --no-halt # start relay on port 4000"
echo ""

ok "All done!  Run the app with: cd ansible_node/app && flutter run"
