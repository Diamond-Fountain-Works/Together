#!/usr/bin/env python3
"""Build the pinned Apple FFI from reviewed Rust sources; never fetch a binary.

Requires existing Rust/Xcode tools. Generated artifacts are local, ignored and
Apple Silicon only. --verify-only is the release/build fail-closed input gate.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile

from rebuild_android_native import (REF, ROOT, SOURCE_FILES, SECURE_LOCK_SHA256,
                                   UPSTREAM_LOCK_SHA256, checked, require,
                                   source_manifest, verify_wrapper_tree)

TARGET = "aarch64-apple-darwin"
MAGIC = "together-secure-apple-iroh-source-build-v2"
PLATFORM_POLICY = SOURCE_FILES / "platform-support.json"
PLATFORMS = {
    "macos": {"target": TARGET, "identifier": "macos-arm64", "platform": "macos", "sdk": "macosx", "env": "MACOSX_DEPLOYMENT_TARGET", "minimum": "11.0", "machPlatform": "MACOS"},
    "ios": {"target": "aarch64-apple-ios", "identifier": "ios-arm64", "platform": "ios", "sdk": "iphoneos", "env": "IPHONEOS_DEPLOYMENT_TARGET", "minimum": "15.0", "machPlatform": "IOS"},
    "ios-simulator": {"target": "aarch64-apple-ios-sim", "identifier": "ios-arm64-simulator", "platform": "ios", "variant": "simulator", "sdk": "iphonesimulator", "env": "IPHONEOS_DEPLOYMENT_TARGET", "minimum": "15.0", "machPlatform": "IOSSIMULATOR"},
}
DEFAULT_PACKAGE = ROOT / ".native-build/apple/iroh-ffi"
BINDINGS = SOURCE_FILES / "apple-bindings"
BINDING_MANIFEST = SOURCE_FILES / "apple-bindings-manifest.json"
PACKAGE_TEXT = '''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "IrohLib", platforms: [.macOS("11.0"), .iOS("15.0")],
    products: [.library(name: "IrohLib", targets: ["IrohLib", "Iroh"])],
    targets: [
        .target(name: "IrohLib", dependencies: [.byName(name: "Iroh")],
            path: "IrohLib/Sources/IrohLib",
            linkerSettings: [.linkedFramework("SystemConfiguration"),
                .linkedFramework("Network"),
                .linkedFramework("CoreWLAN", .when(platforms: [.macOS]))]),
        .binaryTarget(name: "Iroh", path: "Iroh.xcframework")])
'''
LIBRARY_PATH = "Iroh.xcframework/macos-arm64/libiroh_ffi.a"
def package_files(platforms):
    files = {"Package.swift", "IrohLib/Sources/IrohLib/IrohLib.swift", "Iroh.xcframework/Info.plist"}
    for name in platforms:
        prefix = "Iroh.xcframework/" + PLATFORMS[name]["identifier"]
        files.add(prefix + "/libiroh_ffi.a")
        files.update(prefix + "/Headers/" + name for name in ("Export.h", "iroh_ffiFFI.h", "module.modulemap"))
    return files


def platform_gate():
    policy = json.loads(regular(PLATFORM_POLICY).read_text())
    require(policy.get("schemaVersion") == 1 and policy.get("macOS", {}).get("minimumVersion") == "11.0"
            and policy.get("iOS", {}).get("minimumVersion") == "15.0"
            and policy.get("iPadOS", {}).get("minimumVersion") == "15.0",
            "Unreviewed Apple minimum platform policy")
    return policy


def sha(path):
    value = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def regular(path):
    path = Path(os.path.abspath(path))
    require(path.is_file() and not path.is_symlink() and path.resolve() == path,
            "Regular file without symlink parents required: " + str(path))
    return path


def output_path(path):
    path = Path(os.path.abspath(path))
    require(path.name == "iroh-ffi" and ROOT / ".native-build" in path.parents,
            "Generated Apple package must be named iroh-ffi under ignored .native-build")
    cursor = path
    while cursor != ROOT:
        require(not cursor.is_symlink(), "Symlink in generated output: " + str(cursor))
        cursor = cursor.parent
    return path


def binding_gate():
    manifest = json.loads(regular(BINDING_MANIFEST).read_text())
    require(manifest.get("ffiSourceCommit") == REF and manifest.get("binaryIncluded") is False,
            "Unexpected Apple binding manifest")
    files = manifest.get("files", {})
    require(set(files) == {"IrohLib/Sources/IrohLib/IrohLib.swift", "Headers/Export.h",
                           "Headers/iroh_ffiFFI.h", "Headers/module.modulemap"},
            "Unexpected tracked Apple binding files")
    for name, expected in files.items():
        require(sha(regular(BINDINGS / name)) == expected, "Apple binding hash mismatch: " + name)
    return manifest


def verify_exports(library):
    header = (BINDINGS / "Headers/iroh_ffiFFI.h").read_text()
    expected = set(re.findall(r"\b((?:uniffi_|ffi_)[A-Za-z0-9_]+)\s*\(", header))
    # Rust 1.96 embeds LLVM22 compiler-builtins bitcode, newer than Xcode27's
    # LLVM21 nm reader. Inspect the actual native FFI Mach-O object, rather
    # than ignoring archive-wide nm failures or trusting a receipt assertion.
    entries = checked("ar", "-t", library).splitlines()
    native = [name for name in entries if re.fullmatch(r"iroh_ffi\.[A-Za-z0-9_.-]+\.rcgu\.o", name)]
    require(1 <= len(native) <= 16, "Unexpected compiled FFI archive members")
    names = set()
    with tempfile.TemporaryDirectory(prefix="ffi-exports-", dir=library.parent) as temporary:
        for index, name in enumerate(native):
            obj = Path(temporary) / (str(index) + ".o")
            obj.write_bytes(subprocess.check_output(["ar", "-p", str(library), name]))
            names.update(line.lstrip("_") for line in checked("nm", "-gjU", obj).splitlines())
    actual = {name for name in names if name.startswith(("ffi_", "uniffi_"))}
    require(actual == expected and len(actual) == 413, "Pinned FFI header/export mismatch")
    return actual


def verify_native_platform(library, name):
    """Inspect compiled FFI objects, not just the self-reported receipt."""
    expected = PLATFORMS[name]
    entries = checked("ar", "-t", library).splitlines()
    objects = [x for x in entries if re.fullmatch(r"iroh_ffi\.[A-Za-z0-9_.-]+\.rcgu\.o", x)]
    require(objects, "Missing native platform witness")
    versions = []
    with tempfile.TemporaryDirectory(prefix="ffi-platform-", dir=library.parent) as temporary:
        for index, member in enumerate(objects):
            obj = Path(temporary) / (str(index) + ".o")
            obj.write_bytes(subprocess.check_output(["ar", "-p", str(library), member]))
            output = checked("xcrun", "vtool", "-show-build", obj)
            match = re.search(r"\bplatform\s+(\S+).*?\bminos\s+([0-9.]+)", output, re.S)
            require(match is not None and match[1] == expected["machPlatform"], "Native Mach-O platform mismatch")
            actual = tuple(map(int, match[2].split(".")))
            minimum = tuple(map(int, expected["minimum"].split(".")))
            require(actual <= minimum, "Native code raises the advertised OS minimum")
            versions.append(match[2])
    return versions


def source_gate(source, apply_lock=False):
    manifest = source_manifest()
    binding = binding_gate()
    require(checked("git", "rev-parse", "HEAD", cwd=source) == REF, "Unexpected FFI source commit")
    verify_wrapper_tree(source)
    require(set(checked("git", "diff", "--name-only", "HEAD", cwd=source).splitlines()) <= {"Cargo.lock"},
            "FFI source changed beyond the reviewed lock")
    original_lock = subprocess.check_output(["git", "show", "HEAD:Cargo.lock"], cwd=source)
    require(hashlib.sha256(original_lock).hexdigest() == UPSTREAM_LOCK_SHA256, "Unexpected upstream lock")
    lock = regular(source / "Cargo.lock")
    if apply_lock and sha(lock) == UPSTREAM_LOCK_SHA256:
        shutil.copyfile(SOURCE_FILES / "Cargo.lock", lock)
    require(sha(lock) == SECURE_LOCK_SHA256, "Safe lock missing; cargo update is forbidden")
    require(not any((source / ".cargo" / name).exists() for name in ("config", "config.toml")),
            "Unreviewed checkout-local Cargo configuration")
    require(sha(regular(source / "IrohLib/Sources/IrohLib/IrohLib.swift")) ==
            binding["files"]["IrohLib/Sources/IrohLib/IrohLib.swift"], "Swift wrapper differs from pinned source")
    return manifest


def verify(package, required_platforms=()):
    source_manifest()
    binding_gate()
    platform_gate()
    package = output_path(package)
    receipt = json.loads(regular(package / "secure-build.json").read_text())
    require(receipt.get("format") == MAGIC and receipt.get("sourceCommit") == REF and
            receipt.get("secureCargoLockSHA256") == SECURE_LOCK_SHA256 and
            receipt.get("sourceManifestSHA256") == sha(SOURCE_FILES / "source-manifest.json") and
            receipt.get("appleBindingsManifestSHA256") == sha(BINDING_MANIFEST) and
            receipt.get("architecture") == "arm64" and receipt.get("minimumMacOS") == "11.0" and
            receipt.get("minimumIOS") == "15.0" and receipt.get("platformPolicySHA256") == sha(PLATFORM_POLICY) and
            receipt.get("ffiExportCount") == 413 and receipt.get("ffiExportsEqual") is True,
            "Missing/stale secure Apple source-build provenance; rebuild required")
    require(receipt.get("dependencyVersions") == source_manifest()["dependencyVersions"],
            "Unexpected Rust dependency versions")
    actual = {str(p.relative_to(package)) for p in package.rglob("*") if p.is_file()
              and p.name != "secure-build.json"}
    expected = receipt.get("files", {})
    platforms = receipt.get("platforms", [])
    require(isinstance(platforms, list) and platforms and len(set(platforms)) == len(platforms)
            and all(name in PLATFORMS for name in platforms) and set(required_platforms) <= set(platforms),
            "Required native platform slice missing")
    require(actual == set(expected) == package_files(platforms), "Generated Apple package file list differs from reviewed layout")
    require((package / "Package.swift").read_text() == PACKAGE_TEXT, "Unreviewed SwiftPM wrapper")
    for name, expected_sha in expected.items():
        relative = Path(name)
        require(not relative.is_absolute() and ".." not in relative.parts,
                "Unsafe receipt-relative path")
        require(sha(regular(package / relative)) == expected_sha, "Apple artifact hash mismatch: " + name)
    binding = binding_gate()
    info = plistlib.loads((package / "Iroh.xcframework/Info.plist").read_bytes())
    slices = info.get("AvailableLibraries", [])
    require(len(slices) == len(platforms), "Unexpected native XCframework slice count")
    for name in platforms:
        selected = PLATFORMS[name]
        matching = [s for s in slices if s.get("LibraryIdentifier") == selected["identifier"]]
        require(len(matching) == 1 and matching[0].get("SupportedArchitectures") == ["arm64"]
                and matching[0].get("SupportedPlatform") == selected["platform"]
                and matching[0].get("SupportedPlatformVariant") == selected.get("variant"), "Unexpected native XCframework platform")
        for path, expected_sha in binding["files"].items():
            generated = path if path.startswith("IrohLib/") else "Iroh.xcframework/" + selected["identifier"] + "/" + path
            require(expected[generated] == expected_sha, "Generated wrapper/header differs from tracked ABI")
        library = regular(package / ("Iroh.xcframework/" + selected["identifier"] + "/libiroh_ffi.a"))
        with library.open("rb") as stream:
            require(stream.read(8) == b"!<arch>\n", "Native input must be a static archive, not upstream dylib")
        require(sha(library) == receipt.get("libraries", {}).get(name, {}).get("sha256"), "Static library receipt mismatch")
        verify_exports(library)
        verify_native_platform(library, name)
    print("PASS secure Apple source-built package:", package)
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path)
    parser.add_argument("--package-dir", type=Path, default=Path(os.environ.get("TOGETHER_IROH_SECURE_PACKAGE", DEFAULT_PACKAGE)))
    parser.add_argument("--jobs", type=int, default=2)
    parser.add_argument("--verify-only", action="store_true")
    parser.add_argument("--platform", choices=list(PLATFORMS), action="append", help="Repeat for additional Apple slices; default macos")
    args = parser.parse_args()
    package = output_path(args.package_dir)
    if args.verify_only:
        verify(package, args.platform or ["macos"])
        return
    require(platform.system() == "Darwin" and platform.machine() == "arm64", "Apple Silicon macOS build host required")
    require(1 <= args.jobs <= 32, "Invalid bounded build concurrency")
    source = args.source or ROOT / ".native-build/source/iroh-ffi"
    source = Path(os.path.abspath(source))
    require((ROOT / ".native-build" in source.parents or ROOT / "qa/results" in source.parents)
            and source.resolve() == source, "Source must be an isolated owned local checkout without symlinks")
    if not source.exists():
        source.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["git", "clone", "--no-checkout", "https://github.com/n0-computer/iroh-ffi", str(source)], check=True)
        subprocess.run(["git", "checkout", "--detach", REF], cwd=source, check=True)
    manifest = source_gate(source, apply_lock=True)
    platform_gate()
    platforms = list(dict.fromkeys(args.platform or ["macos"]))
    if package.exists():
        verify(package, platforms)
        print("Existing verified package retained; no rebuild requested.")
        return
    target = ROOT / ".native-build/apple/cargo-target"
    target.mkdir(parents=True, exist_ok=True)
    require(target.resolve() == target, "Symlink build output")
    env = os.environ.copy()
    env.pop("CARGO_ENCODED_RUSTFLAGS", None)
    home = Path.home()
    remaps = [(home / ".cargo/registry", "/cargo/registry"), (home / ".cargo/git", "/cargo/git"),
              (home / ".rustup", "/rustup"), (source, "/build")]
    env.update({"CARGO_TARGET_DIR": str(target),
                "RUSTFLAGS": " ".join("--remap-path-prefix=" + str(a) + "=" + b for a, b in remaps),
                "CFLAGS": " ".join("-ffile-prefix-map=" + str(a) + "=" + b for a, b in remaps if b != "/rustup")})
    libraries, commands = {}, []
    for name in platforms:
        selected = PLATFORMS[name]
        build_env = env.copy()
        # Host proc-macros always use the host SDK; target C code uses its own.
        build_env["MACOSX_DEPLOYMENT_TARGET"] = "11.0"
        build_env[selected["env"]] = selected["minimum"]
        build_env["SDKROOT"] = checked("xcrun", "--sdk", selected["sdk"], "--show-sdk-path")
        command = ["cargo", "build", "--locked", "--release", "--target", selected["target"], "--lib", "--jobs", str(args.jobs),
                   "--config", "profile.release.build-override.strip=false"]
        log = target.parent / ("secure-build-" + name + ".log")
        print("Building source-verified", name, "minimum", selected["minimum"], "log", log, flush=True)
        with log.open("w") as stream:
            result = subprocess.run(command, cwd=source, env=build_env, stdout=stream, stderr=subprocess.STDOUT)
        require(result.returncode == 0, "Rust build failed; inspect " + str(log))
        source_gate(source)
        library = regular(target / selected["target"] / "release/libiroh_ffi.a")
        verify_exports(library)
        versions = verify_native_platform(library, name)
        libraries[name] = {"path": library, "sha256": sha(library), "bytes": library.stat().st_size, "nativeMinimumVersions": versions}
        commands.append(command)
    package.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="secure-apple-stage-", dir=package.parent) as temporary:
        staged = Path(temporary) / "iroh-ffi"
        staged.mkdir()
        shutil.copytree(BINDINGS / "IrohLib", staged / "IrohLib")
        (staged / "Package.swift").write_text(PACKAGE_TEXT)
        command = ["xcodebuild", "-create-xcframework"]
        for name in platforms:
            command.extend(["-library", str(libraries[name]["path"]), "-headers", str(BINDINGS / "Headers")])
        command.extend(["-output", str(staged / "Iroh.xcframework")])
        subprocess.run(command, check=True)
        files = {str(p.relative_to(staged)): sha(p) for p in staged.rglob("*") if p.is_file()}
        receipt = {"format": MAGIC, "sourceCommit": REF, "secureCargoLockSHA256": SECURE_LOCK_SHA256,
                   "sourceManifestSHA256": sha(SOURCE_FILES / "source-manifest.json"),
                   "appleBindingsManifestSHA256": sha(BINDING_MANIFEST), "architecture": "arm64", "minimumMacOS": "11.0", "minimumIOS": "15.0",
                   "platformPolicySHA256": sha(PLATFORM_POLICY), "platforms": platforms,
                   "dependencyVersions": manifest["dependencyVersions"], "files": files,
                   "ffiExportsEqual": True, "ffiExportCount": 413, "commands": commands,
                   "libraries": {name: {key: value for key, value in data.items() if key != "path"} for name, data in libraries.items()},
                   "tools": {"rustc": checked("rustc", "--version"), "cargo": checked("cargo", "--version"),
                             "xcode": checked("xcodebuild", "-version")},
                   "scope": "Source/ABI provenance only; not independent security review or real-network acceptance"}
        (staged / "secure-build.json").write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n")
        staged.rename(package)
    source_gate(source)
    verify(package, platforms)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, subprocess.CalledProcessError, ValueError) as error:
        print("FAIL:", error, file=sys.stderr)
        sys.exit(1)
