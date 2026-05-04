#!/bin/bash
# dev_relay.sh - Start the Ansible Relay server
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

echo "Starting Ansible Relay server..."
pushd "$ROOT_DIR/ansible_relay/phoenix" >/dev/null
mix run --no-halt
popd >/dev/null
