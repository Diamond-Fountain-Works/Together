# Normal Debug startup incident — read-only investigation

Status: investigated with explicit remaining **UNKNOWN** items. This is a production-data incident, not a successful isolation check.

The audit copied Application Support, the existing identity file and persisted application preferences into an owner-only location outside the repository. Every copied file hash was checked; source hashes and metadata were stable before/after copying. Raw copies were made read-only. SQLite analysis used a separate writable analysis copy, never the source or frozen evidence. No production application, SwiftData container, Keychain migration, rollback, cleanup or key replacement was run by this investigation. Private manifests, filenames, hashes, SQL output and preference values stay outside public Git.

| Question | Evidence and conclusion |
| --- | --- |
| Identity/key changed? | **UNCHANGED CONTENT** against the trusted pre-incident hash. No new identity file exists in the captured directory. Old permission/ctime values were not recorded, so their historical equality is UNKNOWN. |
| Main database unchanged? | Main file hash matches the trusted pre-incident hash. WAL/SHM differ; the main file alone cannot establish logical equality. |
| New business operations or bills? | **NONE FOUND** in retained persistent history or current operation records since the incident. A pre-incident isolated-copy report has the same operation count. This is evidence, not an immediately-before full logical snapshot or tamper-proof history attestation. |
| LocalRecord changes? | **CONFIRMED** insertion of `replication4/change-review` at the incident time. Its source is the startup history-seeding path. Retained history shows no other post-incident record changes. No business object was edited by this insertion. |
| Preferences? | **CONFIRMED** last-launch timestamp write matching incident startup. Previous complete preferences, prior release-seen value and window preference differences are **UNKNOWN**: no trusted pre-incident plist copy exists. Do not guess or restore prior values. |
| Pairing/Relay? | Current copy has no binding; the trusted pre-incident copy rehearsal also recorded no binding. No new binding transaction was found. |

The complete private report and frozen evidence are retained locally. No actual user content or private diagnostic artifacts are attached to GitHub. Further audit can refine UNKNOWN only if a trustworthy earlier snapshot becomes available; absence of such evidence is not a reason to restore or reset data.

All subsequent native UI automation must use `com.together.app.qa`, a private temporary database/preferences suite, and the fail-closed QA compilation/bootstrap path. Selecting or launching a normal Debug/Release app is not a testing fallback. Candidate captures still need human approval.
