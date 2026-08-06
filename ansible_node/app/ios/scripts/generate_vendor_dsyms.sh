#!/bin/sh
# Generates UUID-matching dSYMs for prebuilt vendor frameworks that are
# embedded by CocoaPods or Swift Package Manager without their own dSYMs.
#
# Xcode only archives dSYMs placed in DWARF_DSYM_FOLDER_PATH.  The current
# OpenSSL-Universal pod and Swoirenberg binary package ship stripped binaries,
# but dsymutil can still emit an UUID-matching bundle for them.  Keeping this
# as an archive build phase makes symbol uploads deterministic for every
# release, rather than relying on a manual Organizer export step.

set -eu

# A simulator build does not produce an App Store archive, and should not
# write symbols into its build products.
if [ "${ACTION:-}" != "install" ]; then
  exit 0
fi

frameworks_dir="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"
dsym_dir="${DWARF_DSYM_FOLDER_PATH:-}"

if [ -z "$dsym_dir" ] || [ ! -d "$frameworks_dir" ]; then
  echo "warning: [Elix] Skipping vendor dSYMs: archive paths are unavailable."
  exit 0
fi

mkdir -p "$dsym_dir"

generate_dsym() {
  framework_name="$1"
  executable_path="$frameworks_dir/$framework_name.framework/$framework_name"
  output_path="$dsym_dir/$framework_name.framework.dSYM"

  if [ ! -f "$executable_path" ]; then
    echo "warning: [Elix] $framework_name.framework is not embedded; skipping dSYM."
    return 0
  fi

  rm -rf "$output_path"
  dsymutil "$executable_path" -o "$output_path"

  if [ ! -f "$output_path/Contents/Resources/DWARF/$framework_name" ]; then
    echo "error: [Elix] Could not generate dSYM for $framework_name.framework."
    exit 1
  fi

  echo "[Elix] Generated dSYM for $framework_name.framework"
}

generate_dsym OpenSSL
generate_dsym SwoirenbergLib
