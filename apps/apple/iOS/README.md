# Together for iPhone and iPad

This application shares the signed replication core, persistence, feature views,
onboarding and release data with the existing Mac application. Phone and tablet
layouts use one business implementation. It targets iOS/iPadOS 15 and ARM64.

## Phone and tablet presentation

The native phone drawer follows the Android destinations: Home, Plans, Wishes,
Our Finances, Connection and Settings. Plans contains Pending and Completed;
Finances contains Reserves, Expenses and Bills. The same ApplicationModel and
signed core serve every layout. Regular-width iPads retain native split navigation;
landscape iPhones keep the drawer. Gifts are overflow actions rather than a page.

Forms reflow at compact/accessibility sizes; the keyboard and safe area determine
sheet height. iOS uses native currency/day wheels, and preserves search/filter
state while navigating. Photos can be selected with PHPicker or Files. PHPicker
requests the selected current representation and copies its file without UIImage
re-encoding; library edits may already be part of that representation. Use Files
when exact bytes of an independently held original are required. Selection staging
is cleaned after import or cancellation; verified export copies the stored file.

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

## Current candidate

0.2.4 Build26 is an unsigned generic-device build for iOS/iPadOS15 and ARM64,
including phone/tablet families1/2 and portrait/landscape. No camera, modem,
biometric or model capability is required. This floor includes the first iPhone
SE and iPhone6s generation when upgraded to iOS15; older devices and every new
physical model are not claimed tested.

Local retained deliverable: `dist/Together-0.2.4-Build26-iOS-unsigned.app.zip`.
It is an inspection/re-signing `.app` archive, **not an installable IPA** or an
App Store/TestFlight release. A signing team, valid provisioning and actual-device
acceptance are still required. Simulator testing remains deferred by the user;
no new runtime or screenshot baseline has been approved.
