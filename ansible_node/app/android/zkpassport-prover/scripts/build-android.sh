#!/usr/bin/env bash
set -euo pipefail

# Build the reviewed Android JNI backend for all Flutter-supported ABIs.  The
# output is intentionally ignored by git and recreated by Gradle/CI; committing
# a host-built .so would make the security boundary non-reproducible.
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
crate_dir=$(cd "$script_dir/.." && pwd)
app_dir=$(cd "$crate_dir/../app" && pwd)
ndk_dir=${ANDROID_NDK_HOME:-}
if [[ -z "$ndk_dir" ]]; then
  sdk_dir=$(sed -n 's/^sdk.dir=//p' "$app_dir/local.properties" | head -n 1)
  ndk_dir="$sdk_dir/ndk/28.2.13676358"
fi
toolchain="$ndk_dir/toolchains/llvm/prebuilt/$(uname -s | tr '[:upper:]' '[:lower:]')-x86_64/bin"
if [[ ! -d "$toolchain" ]]; then
  # GitHub Actions uses linux-x86_64, which the expression above already
  # yields; this keeps a clear error for unsupported build hosts.
  echo "Android NDK LLVM toolchain is unavailable: $toolchain" >&2
  exit 1
fi

# Prefer the rustup-managed Cargo when available. Homebrew Rust intentionally
# does not share rustup's installed Android standard-library targets.
cargo_bin=${CARGO_BIN:-}
rustc_bin=${RUSTC_BIN:-}
if [[ -z "$cargo_bin" ]] && command -v rustup >/dev/null 2>&1; then
  cargo_bin=$(rustup which cargo)
fi
if [[ -z "$rustc_bin" ]] && command -v rustup >/dev/null 2>&1; then
  rustc_bin=$(rustup which rustc)
fi
if [[ -z "$cargo_bin" ]]; then
  cargo_bin=cargo
fi
if [[ -z "$rustc_bin" ]]; then
  rustc_bin=rustc
fi

build_one() {
  local target=$1 abi=$2 linker=$3 ar=$4
  # macOS still ships Bash 3.2, which has no `${value^^}` expansion.
  local upper
  upper=$(printf '%s' "$target" | tr '[:lower:]-' '[:upper:]_')
  local lower
  lower=${target//-/_}
  env \
    "RUSTC=$rustc_bin" \
    "CARGO_TARGET_${upper}_LINKER=$toolchain/$linker" \
    "AR_${upper}=$toolchain/$ar" \
    "CC_${lower}=$toolchain/$linker" \
    "CXX_${lower}=$toolchain/${linker/clang/clang++}" \
    "AR_${lower}=$toolchain/$ar" \
    "BINDGEN_EXTRA_CLANG_ARGS=--target=$target --sysroot=$toolchain/../sysroot" \
    "$cargo_bin" build --manifest-path "$crate_dir/Cargo.toml" --release --target "$target"
  mkdir -p "$app_dir/src/main/jniLibs/$abi"
  install -m 0755 \
    "$crate_dir/target/$target/release/libelix_zkpassport.so" \
    "$app_dir/src/main/jniLibs/$abi/libelix_zkpassport.so"
}

build_one aarch64-linux-android arm64-v8a aarch64-linux-android24-clang llvm-ar
# Barretenberg 5, the pinned iOS-equivalent backend, does not publish a
# 32-bit ARM FFI target.  Do not substitute a different prover: callers on
# armeabi-v7a must fail closed as unsupported rather than receive a weaker
# verification path.
build_one x86_64-linux-android x86_64 x86_64-linux-android24-clang llvm-ar
