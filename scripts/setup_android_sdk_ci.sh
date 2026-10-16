#!/usr/bin/env bash
set -euo pipefail
# CI-only bootstrap; reuse a runner SDK, never install another SDK on the developer Mac.
# Published archive/checksum: https://developer.android.com/studio#command-tools
[[ "${GITHUB_ACTIONS:-}" == true && "$(uname -s)" == Linux ]] || { echo 'This bootstrap is for a Linux GitHub runner only.' >&2; exit 2; }
TASK_ANDROID_SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$RUNNER_TEMP/together-android-sdk}}"
TASK_SDK_MANAGER="$(command -v sdkmanager || true)"
if [[ -z "$TASK_SDK_MANAGER" && -x "$TASK_ANDROID_SDK/cmdline-tools/latest/bin/sdkmanager" ]]; then
  TASK_SDK_MANAGER="$TASK_ANDROID_SDK/cmdline-tools/latest/bin/sdkmanager"
fi
if [[ -z "$TASK_SDK_MANAGER" ]]; then
  TASK_SDK_ZIP="$RUNNER_TEMP/together-commandline-tools.zip"
  curl --fail --location --retry 2 https://dl.google.com/android/repository/commandlinetools-linux-15859902_latest.zip --output "$TASK_SDK_ZIP"
  TASK_ACTUAL_SHA="$(sha256sum "$TASK_SDK_ZIP" | cut -d ' ' -f 1)"
  [[ "$TASK_ACTUAL_SHA" == 4e4c464f145a7512b57d088ac6c278c03c9eea610886b35a5e0804e74eedf583 ]] || { echo 'SDK checksum mismatch' >&2; exit 1; }
  mkdir -p "$TASK_ANDROID_SDK/cmdline-tools"
  TASK_SDK_UNZIP="$RUNNER_TEMP/together-commandline-tools"
  mkdir -p "$TASK_SDK_UNZIP"
  unzip -q "$TASK_SDK_ZIP" -d "$TASK_SDK_UNZIP"
  mv "$TASK_SDK_UNZIP/cmdline-tools" "$TASK_ANDROID_SDK/cmdline-tools/22.0"
  TASK_SDK_MANAGER="$TASK_ANDROID_SDK/cmdline-tools/22.0/bin/sdkmanager"
fi
"$TASK_SDK_MANAGER" --sdk_root="$TASK_ANDROID_SDK" --licenses <<< $'y\ny\ny\ny\ny\ny\ny\ny\ny\ny\n' > /dev/null
"$TASK_SDK_MANAGER" --sdk_root="$TASK_ANDROID_SDK" 'platforms;android-36' 'build-tools;35.0.0'
{
  echo "ANDROID_HOME=$TASK_ANDROID_SDK"
  echo "ANDROID_SDK_ROOT=$TASK_ANDROID_SDK"
} >> "$GITHUB_ENV"
{
  dirname "$TASK_SDK_MANAGER"
  echo "$TASK_ANDROID_SDK/platform-tools"
} >> "$GITHUB_PATH"
