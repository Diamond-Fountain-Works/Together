#!/usr/bin/env python3
"""Build a Release DMG and verify the mounted artifact without changing user data."""
from pathlib import Path
import hashlib
import json
import os
import plistlib
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
DIST = ROOT / "dist"


def run(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True)


def digest(path):
    sha = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            sha.update(block)
    return sha.hexdigest()


def manifest(bundle):
    result = {}
    for path in sorted(bundle.rglob("*")):
        key = str(path.relative_to(bundle))
        if path.is_symlink():
            result[key] = {"link": os.readlink(path)}
        elif path.is_file():
            result[key] = {"sha256": digest(path), "bytes": path.stat().st_size,
                           "executable": bool(path.stat().st_mode & 0o111)}
    return result


def main():
    if len(sys.argv) != 1:
        raise SystemExit("usage: package_app.py (always builds Release first)")
    subprocess.run([str(ROOT / "script/build_and_run.sh"), "--release-build-only"],
                   cwd=ROOT, check=True)
    app = DIST / "Together.app"
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    version, build = info["CFBundleShortVersionString"], info["CFBundleVersion"]
    executable = app / "Contents/MacOS" / info["CFBundleExecutable"]
    architectures = sorted(run("lipo", "-archs", str(executable)).stdout.split())
    if architectures != ["arm64", "x86_64"]:
        raise RuntimeError("Release must include both arm64 and x86_64 for this Universal package")
    arch_label = "Universal"
    name = f"Together-{version}-Build{build}-{arch_label}.dmg"
    destination = DIST / name
    source_manifest = manifest(app)
    release = ROOT / ".derivedData/Build/Products/Release/Together.app"
    if manifest(release) != source_manifest:
        raise RuntimeError("dist is not identical to the Release product")
    signature = subprocess.run(["codesign", "-dvv", str(app)], capture_output=True, text=True)
    if signature.returncode:
        raise RuntimeError(signature.stderr)
    gatekeeper = subprocess.run(["spctl", "--assess", "--type", "execute", "--verbose", str(app)],
                               capture_output=True, text=True)
    instruction = f"""Together {version} · Build {build}

安装：将 Together.app 拖入 Applications。打开 Applications 中的 Together。
支持 macOS {info['LSMinimumSystemVersion']} 及以上，Intel 和 Apple 芯片。

当前为开发分发包，使用 ad-hoc 签名，尚未完成 Developer ID 签名和 Apple 公证。
若 macOS 阻止打开，在确认来源可信后，可先尝试打开 App，再进入
系统设置 → 隐私与安全性 → 仍要打开。不要关闭系统 Gatekeeper。
Apple 说明：https://support.apple.com/zh-cn/102445

首次启动设置个人资料，通过邀请码配对；无需安装 Tailscale。
尚未同步的内容需要双方 App 在线才能交换。没有离线服务器邮箱。
升级保留原有本地数据；此安装包不包含个人资料、任务、愿望或媒体。
"""
    with tempfile.TemporaryDirectory(prefix="together-package-", dir=DIST) as temporary:
        work = Path(temporary)
        payload = work / "payload"
        payload.mkdir()
        run("ditto", str(app), str(payload / "Together.app"))
        (payload / "Applications").symlink_to("/Applications")
        (payload / "安装说明.txt").write_text(instruction, encoding="utf-8")
        image = work / name
        modern = subprocess.run(["diskutil", "image", "create", "from", "-help"],
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0
        if modern:
            run("diskutil", "image", "create", "from", "--format", "UDZO", "--volumeName",
                f"Together {version}", str(payload), str(image))
        else:
            run("hdiutil", "create", "-srcfolder", str(payload), "-format", "UDZO",
                "-volname", f"Together {version}", str(image))
        run("hdiutil", "verify", str(image))
        mount = work / "mounted"
        attached = False
        try:
            if modern:
                run("diskutil", "image", "attach", "--readOnly", "--nobrowse", "--mountPoint",
                    str(mount), str(image))
            else:
                run("hdiutil", "attach", "-readonly", "-nobrowse", "-mountpoint", str(mount), str(image))
            attached = True
            mounted_app = mount / "Together.app"
            if source_manifest != manifest(mounted_app):
                raise RuntimeError("Mounted DMG differs from the Release bundle")
            if not (mount / "Applications").is_symlink() or os.readlink(mount / "Applications") != "/Applications":
                raise RuntimeError("Invalid Applications installation shortcut")
            if (mount / "安装说明.txt").read_text(encoding="utf-8") != instruction:
                raise RuntimeError("Installation instructions did not survive packaging")
            run(sys.executable, str(ROOT / "script/verify_bundle.py"), str(mounted_app))
            if sorted(run("lipo", "-archs", str(mounted_app / "Contents/MacOS/Together")).stdout.split()) != architectures:
                raise RuntimeError("Packaged architectures differ")
        finally:
            if attached:
                run("diskutil", "eject", str(mount)) if modern else run("hdiutil", "detach", str(mount))
        # Publish only after all checks pass; do not replace an existing package on failure.
        image.replace(destination)
    sha = digest(destination)
    destination.with_suffix(".dmg.sha256").write_text(f"{sha}  {name}\n")
    report = {
        "status": "PASS", "version": version, "build": build,
        "artifact": name, "byteCount": destination.stat().st_size, "sha256": sha,
        "architectures": architectures, "minimumMacOS": info["LSMinimumSystemVersion"],
        "relayOrigin": info.get("TogetherRelayURL"), "bundleFilesVerified": len(source_manifest),
        "checks": {"releaseIdentity": "PASS", "diskImageChecksum": "PASS",
                   "mountedBundleHashes": "PASS", "mountedBundleSignatureAndMetadata": "PASS",
                   "architectures": "PASS", "installationShortcutAndGuide": "PASS"},
        "signing": "ad-hoc" if "Signature=adhoc" in signature.stderr else "see codesign output",
        "notarization": "NOT RUN", "gatekeeper": "PASS" if gatekeeper.returncode == 0 else "REJECTED",
        "gatekeeperDetails": gatekeeper.stderr.strip(),
        "userDataIncluded": False
    }
    destination.with_suffix(".json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(f"Package PASS: {destination}")
    print(f"Size: {destination.stat().st_size / 1024 / 1024:.2f} MiB; {arch_label}; macOS {info['LSMinimumSystemVersion']}+")
    print(f"Verified {len(source_manifest)} bundle entries, DMG checksum, metadata, signature and installation shortcut")
    print(f"Gatekeeper: {report['gatekeeper']}; notarization: {report['notarization']}")


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        print(error.stdout or "", file=sys.stderr)
        print(error.stderr or "", file=sys.stderr)
        raise SystemExit(error.returncode)
