# Repository migration stage gate

- Prior stage: Together 0.2.1 Build 4 local candidate complete, current source 0.2.1; exact QA and remaining nonlocal/distribution boundaries in FINAL_QA_BUILD4.md.
- Old 0.0.1 source remains a real migration-test dependency; do not remove before a pinned Git restoration path is tested.
- Existing external Git was copied, not moved, into project .git. HEAD, all refs, reflogs, recoverable commits and worktree status matched; fsck and temporary restored-copy checks passed. Original external Git is retained.
- Durable full Git backup includes the reflog-only amended commit, all 5 recoverable commits and 7 existing untracked QA files. It is outside the project/cache, owner-only, not uploaded.
- Current GitHub account is an active organization administrator. Target repository does not yet exist. User explicitly confirmed Public after resolving the contradictory wording. Create/push only the scanned source baseline; never include runtime/user data.
- Source publication excludes actual databases, media, keys, credentials and runtime logs. Current approved/frozen visual images are deterministic DEBUG fixture captures with exact reviewed hashes, not user data.
- The 8-hour invitation is the formal target; the 10-minute implementation remains unchanged. After repository creation, add a dedicated follow-up Issue. No Worker deployment.

## Source audit

| Role | Before refactor |
| --- | --- |
| Active macOS App / Xcode | 0.2.1/Sources/TogetherApp; 0.2.1/Together.xcodeproj |
| Core/package/tests | 0.2.1/Package.swift; Sources/TogetherCore; Tests/TogetherCoreTests |
| Native UI tests | 0.2.1/Tests/TogetherUITests |
| Release entry | Makefile → scripts/run_project.py → 0.2.1/script/package_app.py |
| C1 relay | server/src/index.ts, wrangler.jsonc; no deployment in this task |
| Actual protocols | Device/log feature version 3; relay API/frame version 1; unchanged implicit three-model SwiftData storage generation |
| Old source | 0.0.1, pinned by the actual legacy migration fixture |
| Runtime/local evidence | .build/.derivedData/dist, server/node_modules/.wrangler, qa/results; excluded from upload |

Build/QA scripts use projectDirectory from qa/project.json but still contain hardcoded version paths and server working directory. Refactor them to one root configuration; preserve historical documents as historical records, not competing active requirements.
