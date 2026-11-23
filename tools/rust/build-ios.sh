#!/usr/bin/env bash
# 为 iOS 编译 Rust 共享内核（真机 arm64 + 模拟器 arm64）并打包 Swift 6 XCFramework。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUST_DIR="$ROOT/shared/core-rust"
OUT_FW="$ROOT/ios/Frameworks/MoviePilotRustCore.xcframework"
SWIFT_OUT="$ROOT/ios/Sources/MoviePilotRustBridge/Generated"
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-/Volumes/DISK/TmpBuild/moviepilot-rust-target}"

cd "$RUST_DIR"
cargo build --release -p mp-ffi-uniffi --target aarch64-apple-ios
cargo build --release -p mp-ffi-uniffi --target aarch64-apple-ios-sim

mkdir -p "$SWIFT_OUT"
STAGE="/Volumes/DISK/TmpBuild/moviepilot-ios-xcframework"
rm -rf "$STAGE" "$OUT_FW"
mkdir -p "$STAGE/headers"

cargo run --release -p mp-ffi-uniffi --bin uniffi-bindgen -- \
  generate --library "$CARGO_TARGET_DIR/aarch64-apple-ios-sim/release/libmoviepilot_core.a" \
  --language swift \
  --out-dir "$STAGE/swift" \
  --config "$RUST_DIR/crates/mp-ffi-uniffi/uniffi.toml"

cp "$STAGE/swift/"*.swift "$SWIFT_OUT/"
cp "$STAGE/swift/"*.h "$STAGE/headers/"
cp "$STAGE/swift/"*.modulemap "$STAGE/headers/module.modulemap"

xcodebuild -create-xcframework \
  -library "$CARGO_TARGET_DIR/aarch64-apple-ios/release/libmoviepilot_core.a" -headers "$STAGE/headers" \
  -library "$CARGO_TARGET_DIR/aarch64-apple-ios-sim/release/libmoviepilot_core.a" -headers "$STAGE/headers" \
  -output "$OUT_FW"

echo "iOS Rust XCFramework 构建完成：$OUT_FW"
du -sh "$OUT_FW"
