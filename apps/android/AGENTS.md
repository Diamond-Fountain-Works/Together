# Android engineering gates

- Kotlin / Jetpack Compose / Room / Coroutines / OkHttp / Android Keystore are the approved Android stack. Do not alter the Apple stack.
- Protocol 4 and enrollment contracts in `protocol/` are authoritative. Verify Swift fixtures; never change signed bytes or business rules to pass Kotlin tests.
- Run `./gradlew :core:protocol:test :core:domain:test :app:assembleDebug :app:lintDebug` here. Run connected tests only on an identified isolated emulator/device; record NOT RUN separately.
- Device keys are independent, Keystore-wrapped and excluded from backup. Missing identity is a recovery error; never silently rotate, reset a database or replace a paired space.
- No production Relay endpoint is bundled. Tests use synthetic identities and local services. No deployment, real-user activation or Mac App installation.
- Native `res/values*/strings.xml` and `qa/android_copy_review.json` govern Android copy. Run `make android-copy-qa` from root; preserve the existing Apple warnings.
- Follow `docs/design/DESIGN_SYSTEM.md`; phone/tablet share state and domain code. Android screenshots are local candidates, never self-approved baselines.
- Keep APKs, SDK paths, Gradle caches, stores and secrets untracked. Push reviewed source only; PR stays Draft until explicitly approved.
