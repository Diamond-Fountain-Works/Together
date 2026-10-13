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
python3 script/generate_project.py
mkdir -p .build/logs dist
BUILD_ARCH="$(uname -m)"
xcodebuild -project Together.xcodeproj -scheme Together -configuration "$CONFIGURATION" -destination "platform=macOS,arch=$BUILD_ARCH" -derivedDataPath .derivedData build >.build/logs/xcode-build.log 2>&1 || { tail -80 .build/logs/xcode-build.log; exit 1; }
APP_SOURCE="$ROOT_DIR/.derivedData/Build/Products/$CONFIGURATION/Together.app"
python3 script/verify_bundle.py "$APP_SOURCE"
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
