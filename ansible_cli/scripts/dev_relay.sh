#!/bin/bash
# dev_relay.sh - Start the Ansible Relay server
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

echo "Starting Ansible Relay server..."
pushd "$ROOT_DIR/ansible_relay/server" >/dev/null
dart run bin/server.dart
popd >/dev/null
