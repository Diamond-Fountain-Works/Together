#!/usr/bin/env python3
"""Read-only configured-release artifact gate. Never launches, installs, signs or clears an app.

An artifact PASS means ready for a separately authorized device test. It is not
VPN-free network acceptance, a data-migration test, notarization or security review.
JSON reports belong in ignored qa/results, not in the public source repository.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PLATFORM_SUPPORT = ROOT / "packages/together-native-source/platform-support.json"
PRIVATE = re.compile(r"(?i)(?:^|/)(?:[^/]+\.(?:sqlite3?|db|store)(?:-wal|-shm)?|[^/]+\.(?:key|p12|pfx|jks|keystore)|\.env(?:\.[^/]+)?|\.dev\.vars(?:\.[^/]+)?|native-app-state\.json)$")


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def run(*args):
    return subprocess.run([str(a) for a in args], capture_output=True, timeout=120)


def minimum_android_api(badging):
    # aapt/aapt2 releases use both spellings. Never infer a minimum from target.
    rows = re.findall(r"^\s*(?:sdkVersion|minSdkVersion):([^\n]*)$", badging, re.M)
    values = [re.fullmatch(r"\s*'(\d+)'\s*", row) for row in rows]
    if not rows or not all(values):
        return None
    levels = {int(value[1]) for value in values}
    if len(levels) != 1:
        raise ValueError("Conflicting Android minimum SDK declarations")
    return next(iter(levels))


def sdk_tool(name):
    direct = shutil.which(name)
    if direct:
        return Path(direct)
    for sdk in (os.environ.get("ANDROID_SDK_ROOT"), os.environ.get("ANDROID_HOME"),
                str(Path.home() / "Library/Android/sdk")):
        if sdk:
            matches = sorted((Path(sdk) / "build-tools").glob("*/" + name),
                             key=lambda p: tuple(int(v) for v in re.findall(r"\d+", p.parent.name)))
            if matches:
                return matches[-1]
    raise RuntimeError("Existing Android SDK tool unavailable: " + name)


def elf_load_segments(data):
    """Parse Android little-endian ELF LOAD metadata and validate its file ranges."""
    if len(data) < 64 or data[:4] != b"\x7fELF" or data[4] not in (1, 2) or data[5] != 1:
        raise ValueError("Invalid Android little-endian ELF header")
    order = "<"
    wide = data[4] == 2
    offset = struct.unpack_from(order + ("Q" if wide else "I"), data, 32 if wide else 28)[0]
    entry_size, count = struct.unpack_from(order + "HH", data, 54 if wide else 42)
    minimum = 56 if wide else 32
    if not 0 < count < 65535 or entry_size < minimum or offset < (64 if wide else 52) or offset + count * entry_size > len(data):
        raise ValueError("Invalid ELF program-header bounds")
    result = []
    for index in range(count):
        start = offset + index * entry_size
        if struct.unpack_from(order + "I", data, start)[0] == 1:
            value_format = "Q" if wide else "I"
            file_offset = struct.unpack_from(order + value_format, data, start + (8 if wide else 4))[0]
            file_size = struct.unpack_from(order + value_format, data, start + (32 if wide else 16))[0]
            memory_size = struct.unpack_from(order + value_format, data, start + (40 if wide else 20))[0]
            if file_offset > len(data) or file_size > len(data) - file_offset or file_size > memory_size:
                raise ValueError("Invalid ELF LOAD file or memory bounds")
            result.append({
                "offset": file_offset,
                "virtualAddress": struct.unpack_from(order + value_format, data, start + (16 if wide else 8))[0],
                "alignment": struct.unpack_from(order + value_format, data, start + (48 if wide else 28))[0],
            })
    if not result:
        raise ValueError("ELF has no LOAD segments")
    return result


def signed_entitlements(result):
    # codesign diagnostics and plist payload have changed output streams across
    # Xcode versions. Parse a complete plist, never an empty diagnostic string.
    for data in (result.stdout, result.stderr):
        if data.startswith(b"bplist00"):
            try:
                return plistlib.loads(data)
            except plistlib.InvalidFileException:
                continue
        start, end = data.find(b"<?xml"), data.find(b"</plist>")
        if start >= 0 and end > start:
            try:
                return plistlib.loads(data[start:end + len(b"</plist>")])
            except (plistlib.InvalidFileException, ValueError):
                continue
    return {}


def mac_native_symbols(bundle, binary):
    candidates = [binary]
    for file in (bundle / "Contents/Frameworks").rglob("*"):
        if file.is_file() and "iroh" in str(file.relative_to(bundle)).lower() and (
                file.suffix == ".dylib" or (".framework/" in str(file) and not file.suffix)):
            candidates.append(file)
    evidence = []
    for file in candidates:
        result = run("nm", "-gU", file)
        if result.returncode:
            continue
        names = {line.split()[-1] for line in result.stdout.decode(errors="replace").splitlines() if line.split()}
        ffi = sorted(n for n in names if re.match(r"_ffi_iroh(?:_ffi)?_", n))
        uniffi = sorted(n for n in names if re.match(r"_uniffi_iroh(?:_ffi)?_", n))
        if ffi and uniffi:
            evidence.append({"path": str(file.relative_to(bundle)),
                             "linkage": "static-in-app-executable" if file == binary else "embedded-native-library",
                             "ffiSymbolCount": len(ffi), "uniffiSymbolCount": len(uniffi),
                             "symbolSetSHA256": hashlib.sha256("\n".join(sorted(ffi + uniffi)).encode()).hexdigest()})
    return evidence


JNA_FIELDS = {
    "Lcom/sun/jna/Pointer;": {"peer": "J"},
    "Lcom/sun/jna/Structure;": {"memory": "Lcom/sun/jna/Pointer;", "typeInfo": "J"},
    "Lcom/sun/jna/IntegerType;": {"value": "J"},
    "Lcom/sun/jna/PointerType;": {"pointer": "Lcom/sun/jna/Pointer;"},
}
JNA_NATIVE = "Lcom/sun/jna/Native;"


def jna_dump_members(lines):
    """Read actual class definitions, not DEX string-table occurrences."""
    result = {}
    current, name, signature = None, None, None
    for line in lines:
        descriptor = re.match(r"\s*Class descriptor\s*:\s*'([^']+)'", line)
        if descriptor:
            current = descriptor[1] if descriptor[1] in {*JNA_FIELDS, JNA_NATIVE} else None
            name, signature = None, None
            if current:
                entry = result.setdefault(current, {"definitions": 0, "fields": {}, "nativeMethods": {}})
                entry["definitions"] += 1
            continue
        if current is None:
            continue
        member = re.match(r"\s*name\s*:\s*'([^']+)'", line)
        if member:
            name, signature = member[1], None
            continue
        member_type = re.match(r"\s*type\s*:\s*'([^']+)'", line)
        if member_type:
            signature = member_type[1]
            continue
        if name and signature and re.match(r"\s*access\s*:", line):
            if signature.startswith("("):
                if "NATIVE" in line:
                    result[current]["nativeMethods"][name] = signature
            else:
                result[current]["fields"][name] = signature
            name, signature = None, None
    return result


def android_jna_abi(apk):
    # Stream dexdump rather than retaining an unbounded disassembly in memory.
    # These temporary files contain application code only, never a device store.
    tool = sdk_tool("dexdump")
    local = ROOT / "qa/results"
    local.mkdir(parents=True, exist_ok=True)
    members = {}
    with tempfile.TemporaryDirectory(prefix="release-dex-abi-", dir=local) as temporary:
        with zipfile.ZipFile(apk) as archive:
            dex_names = [n for n in archive.namelist() if re.fullmatch(r"classes\d*\.dex", n)]
            if not dex_names:
                raise RuntimeError("APK contains no application DEX")
            for name in dex_names:
                dex = Path(temporary) / name
                with archive.open(name) as source, dex.open("wb") as destination:
                    shutil.copyfileobj(source, destination, length=1024 * 1024)
                with tempfile.TemporaryFile() as errors:
                    process = subprocess.Popen([str(tool), str(dex)], stdout=subprocess.PIPE,
                                               stderr=errors, text=True)
                    try:
                        parsed = jna_dump_members(process.stdout)
                        if process.wait(timeout=120):
                            raise RuntimeError("dexdump cannot inspect application DEX")
                    finally:
                        if process.poll() is None:
                            process.kill()
                            process.wait()
                        process.stdout.close()
                for descriptor, entry in parsed.items():
                    prior = members.setdefault(descriptor, {"definitions": 0, "fields": {}, "nativeMethods": {}})
                    prior["definitions"] += entry["definitions"]
                    prior["fields"].update(entry["fields"])
                    prior["nativeMethods"].update(entry["nativeMethods"])
    checks = {}
    for descriptor, fields in JNA_FIELDS.items():
        for name, signature in fields.items():
            entry = members.get(descriptor, {})
            checks[descriptor + "." + name + ":" + signature] = (
                entry.get("definitions") == 1 and entry.get("fields", {}).get(name) == signature)
    native = members.get(JNA_NATIVE, {})
    checks[JNA_NATIVE + ".initIDs:()V native"] = (
        native.get("definitions") == 1 and native.get("nativeMethods", {}).get("initIDs") == "()V")
    return {"status": "PASS" if all(checks.values()) else "FAIL", "checks": checks,
            "scope": "Shipped DEX JNI member ABI only; actual invitation/native startup is a separate runtime gate"}


def mac_report(bundle):
    info = plistlib.loads((bundle / "Contents/Info.plist").read_bytes())
    binary = bundle / "Contents/MacOS" / info["CFBundleExecutable"]
    config = json.loads((ROOT / "apps/apple/macOS/Configuration/ReleaseVersion.json").read_text())
    checks, warnings = {}, []
    checks["normalIdentity"] = info.get("CFBundleIdentifier") == "com.together.app"
    checks["version"] = info.get("CFBundleShortVersionString") == config["marketingVersion"]
    checks["incrementedBuild"] = info.get("CFBundleVersion") == config["buildNumber"] and int(info["CFBundleVersion"]) > 18
    arch = run("lipo", "-archs", binary)
    architectures = arch.stdout.decode().split() if arch.returncode == 0 else []
    support = json.loads(PLATFORM_SUPPORT.read_text())["macOS"]
    checks["nativeArchitecture"] = architectures == support["architectures"]
    checks["minimumOS"] = info.get("LSMinimumSystemVersion") == support["minimumVersion"]
    build_version = run("xcrun", "vtool", "-arch", "arm64", "-show-build", binary)
    minimum = re.search(r"platform\s+MACOS.*?minos\s+([0-9.]+)", build_version.stdout.decode(), re.S)
    checks["actualMachOMinimum"] = minimum is not None and minimum[1] == support["minimumVersion"]
    load_commands = run("otool", "-l", binary).stdout.decode()
    modern_frameworks = [entry for entry in load_commands.split("Load command") if
                         any(name in entry for name in ["SwiftData.framework/", "Observation.framework/"])]
    checks["newerFrameworksWeakLinked"] = all("LC_LOAD_WEAK_DYLIB" in entry for entry in modern_frameworks)
    dependencies = run("otool", "-L", binary).stdout.decode()
    concurrency_needed = "@rpath/libswift_Concurrency.dylib" in dependencies
    checks["oldSystemConcurrencyRuntimeIncluded"] = not concurrency_needed or (bundle / "Contents/Frameworks/libswift_Concurrency.dylib").is_file()
    checks["signature"] = run("codesign", "--verify", "--deep", "--strict", bundle).returncode == 0
    signed = run("codesign", "-d", "--entitlements", ":-", bundle)
    entitlements = signed_entitlements(signed) if signed.returncode == 0 else {}
    required = ("network.client", "network.server", "device.audio-input", "files.user-selected.read-write")
    checks["entitlements"] = all(entitlements.get("com.apple.security." + key) is True for key in required)
    checks["releaseDebuggerDisabled"] = not entitlements.get("com.apple.security.get-task-allow", False)
    paths = [str(p.relative_to(bundle)) for p in bundle.rglob("*") if p.is_file()]
    private = [p for p in paths if PRIVATE.search(p)]
    checks["noPackagedUserStoresOrKeys"] = not private
    native = mac_native_symbols(bundle, binary)
    checks["nativeLibraryIncluded"] = bool(native)
    signature = run("codesign", "-dvv", bundle).stderr.decode(errors="replace")
    gatekeeper = run("spctl", "--assess", "--type", "execute", "--verbose", bundle)
    if "Signature=adhoc" in signature:
        warnings.append("Ad-hoc signature; Developer ID/notarized distribution has not been established")
    if gatekeeper.returncode:
        warnings.append("Gatekeeper assessment rejected; do not describe this as notarized distribution")
    if architectures == ["arm64"]:
        warnings.append("Apple Silicon only; this artifact does not support Intel Macs")
    return {"platform": "macOS", "path": str(bundle), "checks": checks, "warnings": warnings,
            "architectures": architectures, "version": info.get("CFBundleShortVersionString"),
            "build": info.get("CFBundleVersion"), "minimumOS": info.get("LSMinimumSystemVersion"),
            "executableSHA256": digest(binary), "gatekeeper": "PASS" if gatekeeper.returncode == 0 else "REJECTED",
            "nativeSymbolEvidence": native, "packagedPrivatePaths": private}


def android_report(apk):
    aapt, apksigner, zipalign = (sdk_tool(n) for n in ("aapt2", "apksigner", "zipalign"))
    badging = run(aapt, "dump", "badging", apk)
    if badging.returncode:
        raise RuntimeError("aapt2 cannot inspect APK")
    text = badging.stdout.decode()
    package = re.search(r"package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'", text)
    if package is None:
        raise RuntimeError("APK package metadata missing")
    name, code, version = package.groups()
    support = json.loads(PLATFORM_SUPPORT.read_text())["android"]
    sdk = minimum_android_api(text)
    configured = re.search(r"^\s*versionCode\s*=\s*(\d+)\s*$",
        (ROOT / "apps/android/app/build.gradle.kts").read_text(), re.M)
    if configured is None:
        raise RuntimeError("Expected normal Android versionCode is not configured")
    expected_code = int(configured[1])
    signature = run(apksigner, "verify", "--verbose", "--print-certs", apk)
    certs = re.findall(r"certificate SHA-256 digest: ([0-9a-fA-F]+)", signature.stdout.decode())
    checks = {"normalIdentity": name == "com.together.android", "version": version == json.loads((ROOT / "apps/apple/macOS/Configuration/ReleaseVersion.json").read_text())["marketingVersion"],
              "incrementedBuild": int(code) == expected_code and expected_code > 12,
              "notDebuggable": "application-debuggable" not in text,
              "notTestOnly": "application-testOnly" not in text,
              "signature": signature.returncode == 0 and bool(certs)}
    checks["minimumAPIMatchesPolicy"] = sdk == support["minimumAPI"]
    checks["noMaximumAPIFilter"] = "maxSdkVersion:" not in text
    segments, private, warnings = {}, [], []
    native_headers, native_levels = {}, {}
    with zipfile.ZipFile(apk) as archive:
        names = archive.namelist()
        checks["safeArchivePaths"] = all(not p.startswith("/") and ".." not in PurePosixPath(p).parts for p in names)
        private = [p for p in names if PRIVATE.search(p)]
        checks["noPackagedUserStoresOrKeys"] = not private
        for path in names:
            if path.startswith("lib/") and path.endswith(".so"):
                data = archive.read(path)
                segments[path] = elf_load_segments(data)
                abi = path.split("/")[1]
                expected = {"arm64-v8a": (2, 183), "armeabi-v7a": (1, 40)}.get(abi)
                native_headers[path] = expected is not None and (data[4], struct.unpack_from("<H", data, 18)[0]) == expected
                if path.endswith("/libiroh_ffi.so"):
                    from rebuild_android_native import android_api_note
                    native_levels[path] = android_api_note(data)
        checks["nativeLibraryIncluded"] = any(p.endswith("/libiroh_ffi.so") for p in segments)
        checks["samsungARM64Included"] = "lib/arm64-v8a/libiroh_ffi.so" in segments
        checks["allSupportedNativeABIsIncluded"] = all("lib/" + abi + "/libiroh_ffi.so" in segments for abi in support["architectures"])
        checks["nativeABIHeaders"] = bool(native_headers) and all(native_headers.values())
        checks["nativeMinimumAPI"] = bool(native_levels) and all(level is not None and level <= support["minimumAPI"] for level in native_levels.values())
        checks["nativeELF16KiB"] = bool(segments) and all(
            all(s["alignment"] >= 16384 and s["alignment"] & (s["alignment"] - 1) == 0 and
                s["offset"] % s["alignment"] == s["virtualAddress"] % s["alignment"] and
                s["offset"] % 16384 == s["virtualAddress"] % 16384 for s in values)
            for values in segments.values())
    checks["apkZip16KiB"] = run(zipalign, "-c", "-P", "16", "4", apk).returncode == 0
    jna = android_jna_abi(apk)
    checks["shippedJnaJNIABI"] = jna["status"] == "PASS"
    if not checks["nativeELF16KiB"]:
        warnings.append("Actual native LOAD alignment is below 16KiB; broad 16KiB-device delivery is blocked")
    return {"platform": "Android", "path": str(apk), "checks": checks, "warnings": warnings,
            "package": name, "version": version, "versionCode": int(code),
            "expectedVersionCode": expected_code, "sha256": digest(apk),
            "bytes": apk.stat().st_size, "signerSHA256": certs,
            "abis": sorted({p.split("/")[1] for p in segments}), "elfLoadSegments": segments,
            "minimumAPI": sdk, "nativeAPILevels": native_levels,
            "jnaJNIABI": jna, "packagedPrivatePaths": private}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mac-app", type=Path)
    parser.add_argument("--android-apk", type=Path)
    parser.add_argument("--json", type=Path)
    args = parser.parse_args()
    if not (args.mac_app or args.android_apk):
        parser.error("Provide at least one explicit artifact path; this tool never builds or installs")
    reports = []
    for path, inspect in ((args.mac_app, mac_report), (args.android_apk, android_report)):
        if path:
            try:
                report = inspect(path.resolve(strict=True))
                report["status"] = "PASS" if all(report["checks"].values()) else "FAIL"
            except (OSError, ValueError, RuntimeError, KeyError, subprocess.TimeoutExpired, zipfile.BadZipFile) as error:
                report = {"path": str(path), "status": "FAIL", "error": str(error)}
            reports.append(report)
    result = {"artifactStatus": "PASS" if all(r["status"] == "PASS" for r in reports) else "FAIL",
              "scope": "Read-only artifact inspection; no app launch, install, reset, deploy or network test",
              "releaseAcceptance": "NOT RUN", "independentSecurityReview": "NOT RUN",
              "vpnFreePhysicalNetworkAcceptance": "NOT RUN", "artifacts": reports}
    if args.json:
        target = args.json.resolve()
        allowed = (ROOT / "qa/results").resolve()
        if allowed not in target.parents:
            parser.error("Write local artifact reports only below ignored qa/results")
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return int(result["artifactStatus"] != "PASS")


if __name__ == "__main__":
    sys.exit(main())
