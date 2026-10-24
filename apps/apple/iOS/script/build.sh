#!/bin/bash
set -euo pipefail
app_root="$(cd "$(dirname "$0")/.." && pwd)"
repo_root="$(cd "$app_root/../../.." && pwd)"
python3 -B "$app_root/script/generate_project.py"
exec xcodebuild -project "$app_root/Together.xcodeproj" -scheme TogetheriOS \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath "${TOGETHER_IOS_DERIVED_DATA:-$repo_root/.derivedData/ios}" \
  CODE_SIGNING_ALLOWED=NO build "$@"
