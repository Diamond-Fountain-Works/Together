#!/usr/bin/env python3
"""Rebuild pinned FFI wrapper with a reviewed secure lock and 16KiB link flags.

Requires an existing trusted checkout, installed Rust Android target and NDK.
Does not install tools, update dependencies, sign APKs, publish, deploy or use ADB.
All generated source/build/native outputs remain below ignored qa/results.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import zipfile

from test_release_delivery import digest, elf_load_segments

ROOT = Path(__file__).resolve().parents[1]
REF = "5e451092dba0c1a09ee83ff6e5be37b1152a5c58"
UPSTREAM_LOCK_SHA256 = "3e0dbd3b87ba9a85833ace8802661128c6965766566655607981eadc6df719b4"
SECURE_LOCK_SHA256 = "0904d9b3cc5c1b5c3384f2a8fc8881da91bcee6231ad1c8813a1ae6eaae268e5"
SOURCE_FILES = ROOT / "packages/together-native-source"
AAR_SHA256 = "ed747f627da6dad314b25b9ff17d38232d8d75cb31e663af348368e6be845ab8"
TARGET = "aarch64-linux-android"
NATIVE_PATH = "jni/arm64-v8a/libiroh_ffi.so"
# Keep TARGET/NATIVE_PATH and default API 28 for reproducible historical builds.
# A broader app must explicitly rebuild every advertised ABI at its own API floor.
ABI_TARGETS = {
    "arm64-v8a": {"target": "aarch64-linux-android", "clang": "aarch64-linux-android",
                  "elfClass": 2, "machine": 183},
    "armeabi-v7a": {"target": "armv7-linux-androideabi", "clang": "armv7a-linux-androideabi",
                    "elfClass": 1, "machine": 40},
}
MIN_ANDROID_API = 24  # Pinned upstream AndroidManifest.xml; never tools:overrideLibrary.


def android_build_plan(abis=None, api=28):
    selected = tuple(abis or ("arm64-v8a",))
    require(isinstance(api, int) and not isinstance(api, bool) and MIN_ANDROID_API <= api <= 35, "Android API must respect the pinned wrapper floor (24..35)")
    require(len(selected) == len(set(selected)) and all(abi in ABI_TARGETS for abi in selected),
            "Unsupported or repeated Android ABI")
    return [{"abi": abi, "androidAPI": api, **ABI_TARGETS[abi],
             "entry": "jni/" + abi + "/libiroh_ffi.so"} for abi in selected]


def android_api_note(data):
    """Read the NDK linker note from the actual ELF, not a caller-provided receipt."""
    require(len(data) >= 64 and data[:4] == b"\x7fELF" and data[4] in (1, 2) and data[5] == 1,
            "Invalid little-endian Android ELF note input")
    wide = data[4] == 2
    offset = struct.unpack_from("<" + ("Q" if wide else "I"), data, 32 if wide else 28)[0]
    entry_size, count = struct.unpack_from("<HH", data, 54 if wide else 42)
    require(count > 0 and entry_size >= (56 if wide else 32) and
            offset + entry_size * count <= len(data), "Invalid Android note program headers")
    levels = []
    for index in range(count):
        at = offset + index * entry_size
        if struct.unpack_from("<I", data, at)[0] != 4:  # PT_NOTE
            continue
        start = struct.unpack_from("<" + ("Q" if wide else "I"), data, at + (8 if wide else 4))[0]
        length = struct.unpack_from("<" + ("Q" if wide else "I"), data, at + (32 if wide else 16))[0]
        end = start + length
        require(end <= len(data), "Android note lies outside ELF")
        while start + 12 <= end:
            names, desc, kind = struct.unpack_from("<III", data, start)
            name_at = start + 12
            desc_at = name_at + ((names + 3) & ~3)
            next_at = desc_at + ((desc + 3) & ~3)
            require(next_at <= end and next_at > start, "Malformed Android note")
            if data[name_at:name_at + names].rstrip(b"\0") == b"Android" and kind == 1:
                require(desc >= 4, "Android note has no API level")
                levels.append(struct.unpack_from("<I", data, desc_at)[0])
            start = next_at
    require(len(levels) == 1 and 1 <= levels[0] <= 100, "Missing or conflicting NDK Android API note")
    return levels[0]


def verify_android_elf(data, abi, max_api=None):
    require(abi in ABI_TARGETS and len(data) >= 64 and data[:4] == b"\x7fELF" and data[5] == 1,
            "Invalid Android little-endian ELF")
    spec = ABI_TARGETS[abi]
    require(data[4] == spec["elfClass"] and struct.unpack_from("<H", data, 18)[0] == spec["machine"],
            "ELF architecture does not match " + abi)
    try:
        segments = elf_load_segments(data)
    except ValueError as error:
        raise RuntimeError("Rebuilt Android ELF is malformed: " + str(error)) from error
    if max_api is not None:
        require(android_api_note(data) <= max_api, "ELF was linked for a newer Android API than the application floor")
    require(aligned(segments), "Rebuilt ELF LOAD segments fail 16KiB alignment/congruence")
    return segments
UPSTREAM_FIX = "https://github.com/n0-computer/iroh-ffi/commit/c948937663ffe58df1a0a1bfda2def64e5bcdaa4"


def checked(*args, cwd=None, env=None):
    return subprocess.run([str(a) for a in args], cwd=cwd, env=env, check=True,
                          capture_output=True, text=True).stdout.strip()


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def local_output_path(path):
    """Refuse symlink redirection before resolving any generated path."""
    absolute = Path(os.path.abspath(path))
    local = ROOT / "qa/results"
    require(local in absolute.parents, "Generated path must stay below ignored qa/results")
    cursor = absolute
    while cursor != ROOT:
        require(not cursor.is_symlink(), "Symlink in generated path: " + str(cursor))
        cursor = cursor.parent
    return absolute


def verify_wrapper_tree(source):
    # Git's normal diff can intentionally skip working files marked assume-
    # unchanged/skip-worktree. Such an index must never certify source bytes.
    indexed = subprocess.check_output(["git", "ls-files", "-v", "-z"], cwd=source).split(b"\x00")
    require(all(not row or (not chr(row[0]).islower() and row[0:1] != b"S") for row in indexed),
            "Source index has assume-unchanged/skip-worktree flags")
    rows = subprocess.check_output(["git", "ls-tree", "-r", "-z", "HEAD"], cwd=source).split(b"\x00")
    for row in rows:
        if not row:
            continue
        header, path_bytes = row.split(b"\t", 1)
        mode, kind, oid = header.split()
        name = path_bytes.decode("utf-8")
        file = source / name
        require(mode in (b"100644", b"100755") and kind == b"blob" and file.is_file() and not file.is_symlink(),
                "Source tree entry must remain a regular tracked file: " + name)
        # Reject a symlink parent as well; otherwise a regular leaf could read
        # bytes outside this exact checkout.
        require(file.resolve() == file.absolute(), "Symlink parent in tracked source: " + name)
        if name == "Cargo.lock":
            continue
        data = file.read_bytes()
        # The pinned kotlin/.gitattributes checks out this Windows launcher as
        # CRLF while Git stores LF. It is not Rust/build input on these hosts;
        # accept only that declared newline conversion, never a source edit.
        if name == "kotlin/gradlew.bat":
            data = data.replace(b"\r\n", b"\n")
        actual = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\x00" + data).hexdigest()
        require(actual == oid.decode(), "Tracked source bytes differ from pinned HEAD: " + name)


def source_manifest():
    path = SOURCE_FILES / "source-manifest.json"
    manifest = json.loads(path.read_text())
    require(manifest.get("schemaVersion") == 1 and manifest.get("sourceCommit") == REF and
            manifest.get("upstreamCargoLockSHA256") == UPSTREAM_LOCK_SHA256 and
            manifest.get("secureCargoLockSHA256") == SECURE_LOCK_SHA256 and
            manifest.get("sourceChanges") == ["Cargo.lock"] and
            manifest.get("originalAndroidAARSHA256") == AAR_SHA256,
            "Tracked secure source manifest does not match reviewed build inputs")
    lock = SOURCE_FILES / "Cargo.lock"
    require(lock.is_file() and not lock.is_symlink() and digest(lock) == SECURE_LOCK_SHA256,
            "Tracked secure Cargo.lock hash mismatch")
    versions = {}
    for block in lock.read_text().split("[[package]]"):
        name = re.search(r'^name = "([^"]+)"', block, re.M)
        version = re.search(r'^version = "([^"]+)"', block, re.M)
        if name and version:
            versions.setdefault(name[1], []).append(version[1])
    for crate, version in manifest.get("dependencyVersions", {}).items():
        require(versions.get(crate) == [version], "Tracked dependency version mismatch: " + crate)
    for crate in ("iroh", "iroh-base", "iroh-relay"):
        require(versions.get(crate) == ["1.1.0"] and manifest["dependencyVersions"].get(crate) == "1.1.0",
                "Vulnerable or unreviewed native core version: " + crate)
    return manifest


def input_gate(source, original, apply_secure_lock=False):
    manifest = source_manifest()
    require(checked("git", "rev-parse", "HEAD", cwd=source) == REF, "Unexpected source commit")
    verify_wrapper_tree(source)
    changes = checked("git", "diff", "--name-only", "HEAD", cwd=source).splitlines()
    require(not set(changes) - {"Cargo.lock"}, "Source changes outside the reviewed Cargo.lock")
    upstream = subprocess.check_output(["git", "show", "HEAD:Cargo.lock"], cwd=source)
    require(hashlib.sha256(upstream).hexdigest() == UPSTREAM_LOCK_SHA256, "Base source Cargo.lock mismatch")
    source_lock = source / "Cargo.lock"
    require(source_lock.is_file() and not source_lock.is_symlink(), "Source Cargo.lock must be a regular file")
    if apply_secure_lock and digest(source_lock) == UPSTREAM_LOCK_SHA256:
        shutil.copyfile(SOURCE_FILES / "Cargo.lock", source_lock)
    require(digest(source_lock) == SECURE_LOCK_SHA256,
            "Secure Cargo.lock mismatch; build-time cargo update is forbidden")
    require(digest(original) == AAR_SHA256, "Original published 1.1.0 AAR hash mismatch")
    # The pinned tag has no local cargo configuration. An untracked config could
    # silently alter sources/linking, so this build accepts neither form.
    require(not any((source / ".cargo" / name).exists() for name in ("config", "config.toml")),
            "Unexpected checkout-local Cargo configuration")
    return manifest


def exports(nm, path):
    lines = checked(nm, "--dynamic", "--defined-only", "--format=posix", path).splitlines()
    names = {line.split()[0] for line in lines if line.split()}
    api = {name for name in names if name.startswith(("uniffi_", "ffi_", "Java_", "JNI_"))}
    require(api, "No FFI/UniFFI/JNI exports found; cannot validate native API")
    return names, api


def aligned(segments):
    return bool(segments) and all(s["alignment"] >= 16384 and s["alignment"] & (s["alignment"] - 1) == 0 and
               s["offset"] % s["alignment"] == s["virtualAddress"] % s["alignment"] and
               s["offset"] % 16384 == s["virtualAddress"] % 16384 for s in segments)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--ndk", required=True, type=Path)
    parser.add_argument("--original-aar", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--jobs", type=int, default=2)
    parser.add_argument("--android-api", type=int, default=28)
    parser.add_argument("--abi", action="append", choices=tuple(ABI_TARGETS))
    args = parser.parse_args()
    plan = android_build_plan(args.abi, args.android_api)
    source, ndk, original = (p.resolve(strict=True) for p in (args.source, args.ndk, args.original_aar))
    output = local_output_path(args.output)
    local = (ROOT / "qa/results").resolve()
    require(local in source.parents and local in output.parents,
            "Checkout and generated outputs must stay below ignored qa/results")
    require(output.suffix == ".aar" and output != original and not output.exists(),
            "Use a new .aar output; never overwrite original or an existing candidate")
    require(1 <= args.jobs <= 32, "Invalid bounded build concurrency")
    manifest = input_gate(source, original, apply_secure_lock=True)
    host = {"Darwin": "darwin-x86_64", "Linux": "linux-x86_64"}.get(platform.system())
    require(host is not None, "Unsupported NDK host")
    tools = ndk / "toolchains/llvm/prebuilt" / host / "bin"
    ar, nm = tools / "llvm-ar", tools / "llvm-nm"
    require(all(p.is_file() and os.access(p, os.X_OK) for p in (ar, nm)), "Existing NDK tools required")
    require(shutil.which("cargo") is not None and shutil.which("rustc") is not None,
            "Existing Cargo/Rust toolchain required")
    output.parent.mkdir(parents=True, exist_ok=True)
    target_dir = local_output_path(output.parent / "iroh-native-target")
    log = local_output_path(output.with_suffix(".build.log"))
    local_output_path(output.with_suffix(".json"))
    local_output_path(output.with_suffix(".aar.sha256"))
    libraries = {}
    with log.open("w") as stream, zipfile.ZipFile(original) as archive:
        names = archive.namelist()
        require(len(names) == len(set(names)) and "classes.jar" in names and
                all(spec["entry"] in names for spec in plan), "Unexpected original AAR entries")
        original_entries = {name: hashlib.sha256(archive.read(name)).hexdigest() for name in names}
        for spec in plan:
            target = spec["target"]
            clang = tools / (spec["clang"] + str(spec["androidAPI"]) + "-clang")
            require(clang.is_file() and os.access(clang, os.X_OK), "Existing NDK compiler missing: " + str(clang))
            env = os.environ.copy()
            env.pop("RUSTFLAGS", None)
            env.pop("CARGO_ENCODED_RUSTFLAGS", None)
            suffix = target.upper().replace("-", "_")
            cc_suffix = target.replace("-", "_")
            flags = "-C link-arg=-Wl,-z,max-page-size=16384"
            env.update({"LC_ALL": "C", "CARGO_TARGET_DIR": str(target_dir),
                        "CARGO_TARGET_" + suffix + "_LINKER": str(clang),
                        "CARGO_TARGET_" + suffix + "_RUSTFLAGS": flags,
                        "CC_" + cc_suffix: str(clang), "AR_" + cc_suffix: str(ar)})
            command = ["cargo", "build", "--locked", "--release", "--lib", "-p", "iroh-ffi",
                       "--target", target, "--jobs", str(args.jobs)]
            print("Building pinned secure FFI:", spec["abi"], "API", spec["androidAPI"], "Log:", log, flush=True)
            stream.write("\n" + spec["abi"] + " / API " + str(spec["androidAPI"]) + "\n"); stream.flush()
            completed = subprocess.run(command, cwd=source, env=env, stdout=stream, stderr=subprocess.STDOUT)
            require(completed.returncode == 0, "Cargo build failed; original artifact unchanged; inspect local build log")
            input_gate(source, original)
            rebuilt = target_dir / target / "release/libiroh_ffi.so"
            segments = verify_android_elf(rebuilt.read_bytes(), spec["abi"], max_api=spec["androidAPI"])
            with tempfile.TemporaryDirectory(prefix="iroh-exports-", dir=output.parent) as temporary:
                old_so = Path(temporary) / "original.so"
                old_so.write_bytes(archive.read(spec["entry"]))
                old_all, old_api = exports(nm, old_so)
                new_all, new_api = exports(nm, rebuilt)
            require(old_api == new_api, "Exported FFI/UniFFI/JNI names changed for " + spec["abi"])
            libraries[spec["abi"]] = {**spec, "sha256": digest(rebuilt), "path": rebuilt,
                "loadSegments": segments, "ndkAndroidAPI": android_api_note(rebuilt.read_bytes()),
                "ffiExportsEqual": True, "ffiExportCount": len(old_api),
                "otherExportNameCounts": {"original": len(old_all - old_api), "rebuilt": len(new_all - new_api)},
                "command": command, "targetRustFlags": flags,
                "clang": checked(clang, "--version").splitlines()[0]}
        modified = {spec["entry"]: libraries[spec["abi"]]["path"] for spec in plan}
        with tempfile.TemporaryDirectory(prefix="iroh-native-verify-", dir=output.parent) as temporary:
            candidate = Path(temporary) / "candidate.aar"
            with zipfile.ZipFile(candidate, "w") as destination:
                for item in archive.infolist():
                    value = modified[item.filename].read_bytes() if item.filename in modified else archive.read(item.filename)
                    destination.writestr(item, value)
            with zipfile.ZipFile(candidate) as verification:
                require(verification.namelist() == names, "AAR entry list/order changed")
                require(all(hashlib.sha256(verification.read(name)).hexdigest() == sha
                            for name, sha in original_entries.items() if name not in modified),
                        "AAR changed outside the explicitly rebuilt native libraries")
                for name, file in modified.items():
                    require(verification.read(name) == file.read_bytes(), "Rebuilt native copy mismatch: " + name)
            candidate.replace(output)
    input_gate(source, original)
    primary = libraries.get("arm64-v8a", next(iter(libraries.values())))
    serializable_libraries = {abi: {key: value for key, value in info.items() if key != "path"}
                              for abi, info in libraries.items()}
    report = {"status": "PASS", "scope": "Build/link repair only; not protocol or device acceptance",
              "sourceRepository": "https://github.com/n0-computer/iroh-ffi", "sourceCommit": REF,
              "cargoLockSHA256": SECURE_LOCK_SHA256, "secureCargoLockSHA256": SECURE_LOCK_SHA256,
              "upstreamCargoLockSHA256": UPSTREAM_LOCK_SHA256, "upstreamLinkFix": UPSTREAM_FIX,
              "sourceManifestSHA256": digest(SOURCE_FILES / "source-manifest.json"),
              "platformSupportSHA256": digest(SOURCE_FILES / "platform-support.json"),
              "sourceChanges": ["Cargo.lock"], "dependencyVersions": manifest["dependencyVersions"],
              "originalAARSHA256": AAR_SHA256, "outputAARSHA256": digest(output),
              "arm64LibrarySHA256": libraries.get("arm64-v8a", {}).get("sha256"),
              "classesJarSHA256": original_entries["classes.jar"],
              "classesJarPreserved": True, "otherEntriesPreserved": True,
              "modifiedEntry": primary["entry"], "modifiedEntries": list(modified),
              "rebuiltABI": primary["abi"], "rebuiltABIs": list(libraries), "androidAPI": args.android_api,
              "libraries": serializable_libraries,
              "loadSegments": primary["loadSegments"], "ffiExportsEqual": True,
              "ffiExportCount": primary["ffiExportCount"],
              "otherExportNameCounts": primary["otherExportNameCounts"],
              "tools": {"rustc": checked("rustc", "--version"), "cargo": checked("cargo", "--version"),
                        "ndkRevision": next((line.partition("=")[2].strip() for line in
                            (ndk / "source.properties").read_text().splitlines() if line.startswith("Pkg.Revision")), "unknown"),
                        "clang": primary["clang"]},
              "command": primary["command"], "targetRustFlags": primary["targetRustFlags"],
              "runtimeFFIValidation": "NOT RUN", "physicalDevice": "NOT RUN",
              "apkZipAlignment": "NOT RUN", "ffiWrapperSourceChanged": False,
              "limitations": ["Only receipt-listed ABIs have reviewed rebuilt native libraries",
                              "APK ABI filters must exactly match the receipt; original other ABIs are not approved",
                              "Export names and unchanged generated classes do not replace runtime FFI validation"]}
    output.with_suffix(".json").write_text(json.dumps(report, indent=2) + "\n")
    output.with_suffix(".aar.sha256").write_text(digest(output) + "  " + output.name + "\n")
    print("Native link repair PASS:", output)
    print("SHA-256:", report["outputAARSHA256"])
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (RuntimeError, OSError, ValueError, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        print("Native link repair FAIL:", str(error), file=sys.stderr)
        sys.exit(1)
