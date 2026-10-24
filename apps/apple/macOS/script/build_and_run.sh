#!/usr/bin/env bash
set -euo pipefail
MODE="${1:-run}"
CONFIGURATION="Debug"
case "$MODE" in
  --release|--release-build-only) CONFIGURATION="Release" ;;
  run|--build-only|--verify|--logs) ;;
  *) echo 'usage: build_and_run.sh [--build-only|--release|--release-build-only|--verify|--logs]' >&2; exit 2 ;;
esac
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
python3 -B script/generate_project.py
SDK_PATH="$(python3 -B ../../../scripts/select_apple_sdk.py --platform macos)"
mkdir -p .build/logs dist
BUILD_ARCH="$(uname -m)"
BUILD_ARCHS="$BUILD_ARCH"
DERIVED_DATA=".derivedData"
if [[ "${TOGETHER_LEGACY_C1:-0}" != "1" ]]; then
  DERIVED_DATA=".derivedData/native-secure"
  [[ "$BUILD_ARCH" == arm64 ]] || { echo 'Native distribution requires the pinned Apple Silicon transport; use TOGETHER_LEGACY_C1=1 for legacy regression.' >&2; exit 1; }
elif [[ "$CONFIGURATION" == Release ]]; then
  BUILD_ARCHS="arm64 x86_64"
fi
DEFAULT_SDK="$(xcrun --sdk macosx --show-sdk-path)"
DEFAULT_SDK="$(python3 -B -c 'from pathlib import Path; import sys; print(Path(sys.argv[1]).resolve())' "$DEFAULT_SDK")"
if [[ "$SDK_PATH" != "$DEFAULT_SDK" ]]; then
  # Xcode's named-SDK build service cannot register an older CLT SDK. Use the
  # same source and actual compiler/linker deployment target, never a patched
  # SDK setting or a rewritten Mach-O minimum.
  python3 -B script/build_compatibility.py --configuration "$CONFIGURATION" --sdk "$SDK_PATH" >.build/logs/compatibility-driver.log 2>&1 || { tail -80 .build/logs/compatibility-driver.log; exit 1; }
else
  xcodebuild -project Together.xcodeproj -scheme Together -configuration "$CONFIGURATION" -sdk "$SDK_PATH" -destination "platform=macOS,arch=$BUILD_ARCH" -derivedDataPath "$DERIVED_DATA" "ARCHS=$BUILD_ARCHS" build >.build/logs/xcode-build.log 2>&1 || { tail -80 .build/logs/xcode-build.log; exit 1; }
fi
APP_SOURCE="$ROOT_DIR/$DERIVED_DATA/Build/Products/$CONFIGURATION/Together.app"
python3 -B script/verify_bundle.py "$APP_SOURCE"
APP_BUNDLE="$ROOT_DIR/dist/Together.app"
rm -rf "$APP_BUNDLE"
cp -R "$APP_SOURCE" "$APP_BUNDLE"
if [[ "$MODE" == "--build-only" || "$MODE" == "--release-build-only" ]]; then exit 0; fi
pkill -x Together >/dev/null 2>&1 || true
/usr/bin/open -n "$APP_BUNDLE"
case "$MODE" in
  --verify) sleep 1; pgrep -x Together >/dev/null ;;
  --logs) /usr/bin/log stream --info --style compact --predicate 'process == "Together"' ;;
  run|--release) ;;
esac
