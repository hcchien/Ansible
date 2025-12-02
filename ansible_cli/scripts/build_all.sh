#!/bin/bash
# build_all.sh - Build every Ansible target
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

echo "Building Ansible Relay server..."
pushd "$ROOT_DIR/ansible_relay/server" >/dev/null
dart pub get
mkdir -p build
dart compile exe bin/server.dart -o build/server
popd >/dev/null

echo "Building Ansible Node web UI..."
pushd "$ROOT_DIR/ansible_node/web_ui" >/dev/null
flutter pub get
flutter build web
popd >/dev/null

echo "Building Ansible Node desktop app..."
pushd "$ROOT_DIR/ansible_node/app" >/dev/null
flutter pub get
flutter build macos
popd >/dev/null
