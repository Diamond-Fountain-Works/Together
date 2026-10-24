#!/usr/bin/env python3
"""Select an already-installed SDK that supports the declared deployment floor.

No SDK download, system SDK modification or deployment-range override is used.
Xcode 27's default Mac SDK starts at 12; an installed older SDK may still support
the first M-series release. A final linked-bundle gate must verify the result.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def version(value):
    pieces = tuple(int(x) for x in value.split("."))
    return pieces + (0,) * max(0, 3 - len(pieces))


def supports(sdk, platform, minimum):
    try:
        data = json.loads((sdk / "SDKSettings.json").read_text())
        target = data["SupportedTargets"]["macosx" if platform == "macos" else "iphoneos"]
        return version(target["MinimumDeploymentTarget"]) <= version(minimum) <= version(target["MaximumDeploymentTarget"])
    except (OSError, ValueError, KeyError, TypeError):
        return False


def select(platform, override=None):
    policy = json.loads((ROOT / "packages/together-native-source/platform-support.json").read_text())
    minimum = policy["macOS" if platform == "macos" else "iOS"]["minimumVersion"]
    if override:
        sdk = Path(override).resolve(strict=True)
        if not supports(sdk, platform, minimum):
            raise RuntimeError("Selected SDK does not support the declared deployment minimum")
        return sdk
    name = "macosx" if platform == "macos" else "iphoneos"
    default = Path(subprocess.check_output(["xcrun", "--sdk", name, "--show-sdk-path"], text=True).strip())
    if supports(default, platform, minimum):
        return default
    if platform == "macos":
        installed = Path("/Library/Developer/CommandLineTools/SDKs")
        candidates = [sdk for sdk in installed.glob("MacOSX*.sdk") if supports(sdk, platform, minimum)]
        if candidates:
            # CanonicalName comes from installed metadata, not a guessed name.
            return max(candidates, key=lambda sdk: version(json.loads((sdk / "SDKSettings.json").read_text())["Version"]))
    raise RuntimeError("No installed SDK supports the declared minimum; a compatible toolchain is required")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", choices=["macos", "ios"], required=True)
    args = parser.parse_args()
    print(select(args.platform, os.environ.get("TOGETHER_MACOS_SDK" if args.platform == "macos" else "TOGETHER_IOS_SDK")))
