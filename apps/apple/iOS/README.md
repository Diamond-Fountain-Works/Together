# Together for iPhone and iPad

This application shares the signed replication core, persistence, feature views,
onboarding and release data with the existing Mac application. Phone and tablet
layouts use one business implementation. It targets iOS/iPadOS 15 and ARM64.

## Build

From the repository root, using the existing Rust and Xcode installations:

```sh
rustup target add aarch64-apple-ios
python3 -B scripts/rebuild_apple_native.py --platform macos --platform ios --jobs 2
python3 -B apps/apple/iOS/script/generate_project.py
apps/apple/iOS/script/build.sh
```

The final command performs an unsigned generic-device build. It does not install
or launch an application, create a simulator or access an existing user's data.
Installing on a physical iPhone/iPad requires that device and valid Apple signing
and provisioning. An unsigned `.app` is not a distributable IPA.

`TogetheriOSQA` is a separate bundle identifier. It refuses to initialize any
database without the explicit `TOGETHER_IOS_QA=1` test launch environment. Its
stores and keys are isolated in its own temporary application sandbox; the QA
product never calls the production factory. The normal Release excludes that
bootstrap at compile time. UI/runtime testing is separate from successful builds.

The application reconnects while foregrounded and catches up on resume. It does
not promise a permanently running background WebSocket/QUIC connection or an
offline server mailbox. Original media export is user initiated through the
system document picker. Device keys are excluded from backup; losing a key does
not authorize a silent replacement identity.

The default derived-data path is project-local `.derivedData/ios`; set
`TOGETHER_IOS_DERIVED_DATA` for an isolated run. A simulator requires a separately
source-built `ios-simulator` native slice and an installed compatible runtime.
Neither is downloaded or started by the device build command. Current runtime
QA is deferred at the user's request; no simulator result is claimed.
