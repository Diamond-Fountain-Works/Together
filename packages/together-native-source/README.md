# Pinned native transport build inputs

These are reviewed source inputs, not bundled binaries or another sync engine.
The application Protocol 4 signatures, canonical JSON, operation log, business
projection and receipt semantics are unchanged.

## Fixed source and dependencies

- FFI wrapper: [n0-computer/iroh-ffi](https://github.com/n0-computer/iroh-ffi),
  commit `5e451092dba0c1a09ee83ff6e5be37b1152a5c58` (FFI version 1.1.0).
- Original wrapper Cargo.lock SHA-256:
  `3e0dbd3b87ba9a85833ace8802661128c6965766566655607981eadc6df719b4`.
- Approved `Cargo.lock` SHA-256:
  `0904d9b3cc5c1b5c3384f2a8fc8881da91bcee6231ad1c8813a1ae6eaae268e5`.
- Rust `iroh`, `iroh-base`, `iroh-relay`, `iroh-dns`: exactly 1.1.0.
- `noq`, `noq-proto`, `noq-udp`: exactly 1.2.0, the minimum family required by
  Iroh 1.1.0. Other exact package versions and registry checksums live in the lock.

Only the wrapper's dependency lock changes. Its Rust implementation, UniFFI API,
generated bindings and public application wire format are not rewritten. Builds
must use `--locked`; resolving new versions during a release build is forbidden.
The machine-readable authority is `source-manifest.json`, plus the exact lock
bytes. Any future change to these inputs needs review and fresh native tests.
The build guard hashes every tracked wrapper file against its pinned Git blob,
independently of index stat flags. `assume-unchanged` and `skip-worktree` are
rejected. Only the pinned Windows Gradle launcher's declared CRLF checkout
conversion is normalized; Rust source bytes must match exactly. Generated
output/cache/log/receipt paths reject symlink redirection outside local QA data.

## Why an unchanged Maven version is insufficient

The published FFI 1.1.0 artifact contains Rust Iroh 1.0.2. The FFI/Maven version
does not prove that its Rust transport dependencies include security fixes:

- [GHSA-7cq4-mhxw-xw78](https://github.com/n0-computer/iroh/security/advisories/GHSA-7cq4-mhxw-xw78):
  relay receive progress can be stopped by an oversized batch before application
  authentication. The affected Rust core must be replaced; changing page
  alignment or verifying Together operation signatures does not fix it.
- [GHSA-vwh7-9883-83xj](https://github.com/n0-computer/iroh/security/advisories/GHSA-vwh7-9883-83xj):
  reserved-address classification can misroute peer path probes. Upstream does
  not describe business-data disclosure or identity impersonation from this bug.
- [GHSA-jx4g-cg2x-jc35](https://github.com/n0-computer/iroh/security/advisories/GHSA-jx4g-cg2x-jc35):
  malformed custom-address deserialization can panic. The vulnerable type exists
  in the old dependency; the current App's typed address adapter does not parse
  endpoint tickets or register custom transports, so its App-level reachability
  has not been established. The fixed dependency is still required.

All three advisories name Rust 1.1.0 as fixed. Static version/source inspection
does not replace focused upstream regressions, rebuilt-library runtime tests,
actual App interoperability or the separate independent protocol-review gate.

## Android rebuild

Use `scripts/rebuild_android_native.py` with an existing checkout, installed NDK,
original published Android AAR and an output below ignored `qa/results`.
The tool verifies the base commit and original lock; it can copy only this exact
approved lock onto a clean base. Any other tracked-source change, unexpected lock
or checkout-local Cargo config is rejected. It never runs `cargo update`.

The Android link option follows the
[upstream 16KiB fix](https://github.com/n0-computer/iroh-ffi/commit/c948937663ffe58df1a0a1bfda2def64e5bcdaa4).
Only the arm64 shared library is replaced inside the original verified AAR.
`classes.jar` and every other entry are checked byte for byte. Actual LOAD
alignment/congruence and FFI exports must pass; the final APK must separately
pass ZIP alignment, signing, native initialization and device sync tests.
Other untouched AAR ABIs remain unsuitable for this arm64-only delivery.

The generated receipt records source/lock/manifest hashes, exact Rust versions,
tools, native-library hash and AAR hash. It is build provenance, not independent
security certification. Gradle must reject an aligned-only receipt with the old
vulnerable lock, even if that artifact has a valid signature.

Apple builds use the same fixed lock with independently recorded Swift/C binding
inputs and a local rebuilt library. A matching binary/receipt is required; never
silently fall back to the older remote prebuilt framework.

On an existing Apple Silicon Xcode/Rust host, build from the isolated source
checkout using `python3 scripts/rebuild_apple_native.py --source <checkout>
--jobs 2`. The default generated package is `.native-build/apple/iroh-ffi`.
`python3 scripts/rebuild_apple_native.py --verify-only` checks the source/lock and
binding-manifest receipt, exact package file hashes, arm64 static archive and
413 pinned FFI exports before a release build. The optional
`TOGETHER_IROH_SECURE_PACKAGE` path must remain under `.native-build`; it cannot
select an arbitrary remote binary or bypass a missing receipt.

Native source clones, Cargo targets, AAR/framework/library outputs, full logs,
keys and APKs remain local and ignored. No production deployment is involved.
