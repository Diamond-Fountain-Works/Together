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
    args = parser.parse_args()
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
    clang, ar, nm = (tools / name for name in ("aarch64-linux-android28-clang", "llvm-ar", "llvm-nm"))
    require(all(p.is_file() and os.access(p, os.X_OK) for p in (clang, ar, nm)),
            "NDK toolchain is not fully installed; this script never installs SDK components")
    require(shutil.which("cargo") is not None and shutil.which("rustc") is not None,
            "Existing Cargo/Rust toolchain required")
    output.parent.mkdir(parents=True, exist_ok=True)
    target_dir = local_output_path(output.parent / "iroh-native-target")
    log = local_output_path(output.with_suffix(".build.log"))
    local_output_path(output.with_suffix(".json"))
    local_output_path(output.with_suffix(".aar.sha256"))
    env = os.environ.copy()
    # Generic RUSTFLAGS take priority over target flags. Do not inherit them and
    # accidentally omit the one reviewed upstream link change.
    env.pop("RUSTFLAGS", None)
    env.pop("CARGO_ENCODED_RUSTFLAGS", None)
    env.update({"LC_ALL": "C", "CARGO_TARGET_DIR": str(target_dir),
                "CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER": str(clang),
                "CARGO_TARGET_AARCH64_LINUX_ANDROID_RUSTFLAGS": "-C link-arg=-Wl,-z,max-page-size=16384",
                "CC_aarch64_linux_android": str(clang), "AR_aarch64_linux_android": str(ar)})
    command = ["cargo", "build", "--locked", "--release", "--lib", "-p", "iroh-ffi",
               "--target", TARGET, "--jobs", str(args.jobs)]
    print("Building pinned FFI + secure Rust core arm64; output remains local. Log:", log, flush=True)
    with log.open("w") as stream:
        completed = subprocess.run(command, cwd=source, env=env, stdout=stream, stderr=subprocess.STDOUT)
    require(completed.returncode == 0, "Cargo build failed; original artifact unchanged; inspect local build log")
    input_gate(source, original)
    rebuilt = target_dir / TARGET / "release/libiroh_ffi.so"
    segments = elf_load_segments(rebuilt.read_bytes())
    require(aligned(segments), "Rebuilt ELF LOAD segments fail 16KiB alignment/congruence")
    with zipfile.ZipFile(original) as archive:
        names = archive.namelist()
        require(len(names) == len(set(names)) and NATIVE_PATH in names and "classes.jar" in names,
                "Unexpected original AAR entries")
        original_entries = {name: hashlib.sha256(archive.read(name)).hexdigest() for name in names}
        with tempfile.TemporaryDirectory(prefix="iroh-native-verify-", dir=output.parent) as temporary:
            old_so = Path(temporary) / "original.so"
            old_so.write_bytes(archive.read(NATIVE_PATH))
            old_all, old_api = exports(nm, old_so)
            new_all, new_api = exports(nm, rebuilt)
            require(old_api == new_api, "Exported FFI/UniFFI/JNI names changed; original AAR remains unchanged")
            candidate = Path(temporary) / "candidate.aar"
            with zipfile.ZipFile(candidate, "w") as destination:
                for item in archive.infolist():
                    destination.writestr(item, rebuilt.read_bytes() if item.filename == NATIVE_PATH else archive.read(item.filename))
            with zipfile.ZipFile(candidate) as verification:
                require(verification.namelist() == names, "AAR entry list/order changed")
                require(all(hashlib.sha256(verification.read(name)).hexdigest() == sha
                            for name, sha in original_entries.items() if name != NATIVE_PATH),
                        "AAR changed outside the single arm64 shared library")
                require(verification.read(NATIVE_PATH) == rebuilt.read_bytes(), "Rebuilt native copy mismatch")
            candidate.replace(output)
    input_gate(source, original)
    report = {"status": "PASS", "scope": "Build/link repair only; not protocol or device acceptance",
              "sourceRepository": "https://github.com/n0-computer/iroh-ffi", "sourceCommit": REF,
              "cargoLockSHA256": SECURE_LOCK_SHA256, "secureCargoLockSHA256": SECURE_LOCK_SHA256,
              "upstreamCargoLockSHA256": UPSTREAM_LOCK_SHA256, "upstreamLinkFix": UPSTREAM_FIX,
              "sourceManifestSHA256": digest(SOURCE_FILES / "source-manifest.json"),
              "sourceChanges": ["Cargo.lock"], "dependencyVersions": manifest["dependencyVersions"],
              "originalAARSHA256": AAR_SHA256, "outputAARSHA256": digest(output),
              "arm64LibrarySHA256": digest(rebuilt), "classesJarSHA256": original_entries["classes.jar"],
              "classesJarPreserved": True, "otherEntriesPreserved": True,
              "modifiedEntry": NATIVE_PATH, "rebuiltABI": "arm64-v8a", "androidAPI": 28,
              "loadSegments": segments, "ffiExportsEqual": True, "ffiExportCount": len(old_api),
              "otherExportNameCounts": {"original": len(old_all - old_api), "rebuilt": len(new_all - new_api)},
              "tools": {"rustc": checked("rustc", "--version"), "cargo": checked("cargo", "--version"),
                        "ndkRevision": next((line.partition("=")[2].strip() for line in
                            (ndk / "source.properties").read_text().splitlines() if line.startswith("Pkg.Revision")), "unknown"),
                        "clang": checked(clang, "--version").splitlines()[0]},
              "command": command, "targetRustFlags": env["CARGO_TARGET_AARCH64_LINUX_ANDROID_RUSTFLAGS"],
              "runtimeFFIValidation": "NOT RUN", "physicalDevice": "NOT RUN",
              "apkZipAlignment": "NOT RUN", "ffiWrapperSourceChanged": False,
              "limitations": ["Only arm64 was rebuilt; other original AAR ABI entries remain unchanged",
                              "Use an arm64-only APK ABI filter; do not claim all AAR ABIs were repaired",
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
