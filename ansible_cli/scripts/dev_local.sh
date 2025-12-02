#!/bin/bash
# dev_local.sh - Start the Ansible Node (Flutter desktop)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

echo "Starting Ansible Node (macOS desktop)..."
pushd "$ROOT_DIR/ansible_node/app" >/dev/null
flutter run -d macos
popd >/dev/null
