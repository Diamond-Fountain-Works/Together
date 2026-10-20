# Native Together App network acceptance — 2026-10-20

## Qualified checkpoint

**The minimum normal-App workflow passed on the physical Samsung and the Mac
using isolated Together QA builds. The VPN-free product goal has not passed.**
The Samsung used mobile data without VPN. The Mac used Wi-Fi with an active VPN;
route evidence included the VPN interface. The established application connection
used an encrypted native relay path. A transient native direct-path indication
does not establish a VPN-free public direct route when the underlying route uses
the VPN.

These results concern the actual SwiftUI/Compose App workspaces and their existing
business editors. They are distinct from the earlier CLI/instrumentation-only
transport tests. The production macOS installation was not replaced.

## Actual normal-App minimum workflow

| Check | Result | Observed boundary |
| --- | --- | --- |
| Samsung creates invitation; Mac joins through the Connection UI | PASS | Signed self-contained routing invitation; not a server short code |
| Both Apps show the same identity code; confirmation is exercised on both | PASS | Independent device identities; existing signed hello/consent and co-signed genesis |
| Mac creates a task through the regular task editor | PASS | The task appears in the Samsung App from a durably imported signed operation |
| Sender receives a genuine partner persistence receipt | PASS | Existing signed per-device ACK ledger reports remote persistence, independently of socket-send success |
| Mac disconnects and edits the task offline | PASS | The local edit remains in the operation log |
| Samsung edits a different field while disconnected | PASS | The completion operation remains local until catch-up |
| Reconnect merges both edits | PASS | Task notes and completion agree; the captured checkpoint contains 10 operations and a real partner receipt |
| Samsung process is force-stopped, reopened, then reconnects | PASS | A different process opens the retained workspace; existing profiles, tasks and device identities remain available |
| Mac initiates the opposite invitation direction | NOT RUN at this checkpoint | A successful Samsung-initiated run does not cover the reverse direction |
| Both devices use independent networks without any VPN | NOT RUN / BLOCKED | A VPN-free Mac route/test host is required; the user’s current VPN setting is retained |
| VPN-free public direct P2P | NOT RUN | Relay success and a native path label are insufficient evidence |
| Mac records a reserve deposit; Samsung shows the same new entry | PASS | Synthetic deposit and resulting balance agree |
| Shared-account expense and AA expense | PASS | Both Apps agree on expense totals, the reserve balance and deterministic odd-cent allocations |
| Wish grant → beneficiary creates wish → fulfiller requests completion → beneficiary confirms | PASS | Both Apps show one fulfilled and one remaining wish |
| Recurring bills and broader financial edge cases | NOT RUN in this physical run | Existing automated domain tests remain distinct from physical UI acceptance |
| Original photo transfer and content-complete receipt | PASS | Normal Mac composer imports/sends a synthetic 1,845,914-byte PNG; Samsung original SHA-256 and byte count match exactly, and Mac gift history shows Synced from the separate content receipt |
| Normal-App audio import/playback | NOT RUN / automation blocked | Audio-menu automation did not complete; original failure evidence retained. Shared original-media session tests are not physical audio acceptance |

The connection used real application traffic, rather than copying signed
operations between stores. USB was used for test installation, UI input,
out-of-band public invitation transfer and diagnostics. Raw private stores,
identities, device IDs, network addresses, user-entered content and screenshots
are not included in this public report.

## Evidence and limitations

The ignored local run directory is `qa/results/native-app-p2p-20261020-*/`.
Relevant private evidence includes:

- `mac-first-real-ack.json` and `mac-first-live-operation-ack.json`: connected
  application checkpoint, genuine persistence progress and selected relay path.
- `android-first-live-task.xml` and the corresponding candidate screenshot:
  the normal App task UI after live synchronization.
- `mac-offline-catchup-real-ack.json`,
  `android-offline-catchup-completed.xml` and its candidate screenshot: both
  independent field edits after catch-up; 10 operations in the captured Mac log.
- `android-process-restart.json`, `android-reopened-home.xml`,
  `android-after-restart-logcat.txt` and `mac-after-phone-restart.json`:
  process restart and subsequent connected state with remote persistence.
- Mac route tables and per-destination route checks: the VPN qualification
  remains explicit even when the native transport reports a direct path.
- `android-aa-expenses.xml`, `android-shared-expense-reserves.xml`,
  `android-wish-confirmed.xml` and `mac-wishes-finance-real-ack.json`:
  the subsequent normal-App financial/wish results and genuine partner receipt.

These files are local-only. Candidate screenshots are **not approved visual
baselines**. Earlier failed attempts and initialization/input problems remain in
the local evidence; their causes are not replaced by a later successful run.

### Subsequent financial and wish UI checkpoint

All values below are synthetic QA entries, not personal financial records:

- Mac records a ¥20.00 reserve deposit. Samsung shows ¥20.00.
- Mac records a ¥3.01 shared-account expense. Samsung's reserve balance becomes
  ¥16.99, without a duplicate debit.
- Mac records a separate ¥3.01 AA expense. Both Apps show ¥6.02 total expenses:
  Samsung ¥1.51, Mac ¥1.50 and shared reserves ¥3.01. The AA expense leaves the
  shared reserve balance at ¥16.99; allocations total the recorded expense.
- Mac grants two wishes. The Samsung beneficiary creates one wish, the Mac
  fulfiller requests completion, and the Samsung beneficiary confirms it. Both
  Apps then show **one fulfilled / one remaining**.
- The captured Mac state is converged with **17 operations** and a genuine
  partner persistence receipt. Its selected application path is encrypted relay.

These operations used the normal financial and wish editors and existing
domain rules. The Mac VPN qualification still applies to this entire checkpoint.

## Implemented and separately verified hardening

- Swift and Kotlin use the same signed contact body and canonical fixture.
  Fresh invitations last exactly 28,800,000 ms. Reading a previously pinned
  experimental 10-minute contact does not authorize a fresh join.
- Existing first-partner history/genesis logic is reused. No C1 server route is
  fabricated, no business ledger is replaced and existing signed fact bytes
  are preserved.
- A missing bootstrap batch ACK now produces a protocol failure instead of
  silently cancelling the child and leaving the UI waiting. The production
  deadline remains 20 seconds. Actual owner cancellation remains cancellation.
- Targeted Kotlin regression: **5 PASS / 0 FAIL / 0 SKIP**, covering contact
  conformance, mutual-consent/history bootstrap, ACK expiry/cancellation and the
  existing local C1 pairing/restart flow.
- Targeted Swift regression: **4 PASS / 0 FAIL / 0 SKIP**, covering the shared
  contact/bootstrap adapter and the existing local C1 pairing flow.

These are targeted regression counts, not a full project test-suite verdict.
Additional lifecycle and prepared-genesis recovery source changes require their
own fresh-build and runtime results; this checkpoint does not approve unrun paths.

### Historical media source checkpoint (before physical photo transfer)

The native App content bridge now reuses the exact existing C1 envelope:
`{kind:"replication",frame}` or `{kind:"media",payload}`. Swift routes media through
the existing media-only session; Kotlin shares the existing content codec and
media interface. The signed operation format, cipher and durable operation ACKs
are unchanged. App-only ALPN `together/p4/c1-content/1` distinguishes this payload
from the unchanged CLI transport ALPN `together/p4/1`; there is no raw-frame fallback.

- Swift bridge regression: **2 PASS / 0 FAIL**. The actual existing media store
  transfers a synthetic original photo larger than one chunk, interrupts after
  the first 64 KiB, resumes with a nonzero offset through fresh media sessions,
  verifies the complete SHA-256 and accepts a genuine content-complete gift
  receipt. The operation count does not change during media transfer.
- Kotlin codec regression: **1 PASS / 0 FAIL**. Both platforms round-trip the
  same seven canonical C1 envelopes, including original-byte chunks and a gift
  receipt; raw replication frames are rejected by the content codec.
- These are local adapter tests, **not physical Mac–Samsung media acceptance**.
  Both QA Apps require a fresh compatible build and an actual transfer before
  the original-media acceptance row can pass.

### Focused boundary review and current-source regression

The subsequent targeted run passed **24 Swift tests / 15 Kotlin tests**, with
zero failures and zero skips, using an isolated loopback C1 Worker where needed.
These totals include overlapping cases above and must not be added to them.
Coverage includes same-ID/different-content rejection and atomic reopen, signed
ACK membership/tampering, pinned endpoint authorization, replay rejection, fresh
8-hour versus pinned legacy-contact handling, bootstrap ACK expiry/cancellation,
the existing C1 pairing flow, and authenticated content/media compatibility.

Source review also checked the current QA bundle/package, required launch
argument, bounded temporary-root and Android namespace/empty-Relay gates. These
paths fail closed rather than selecting a production workspace. Invitation
signature-only reading does not grant current membership; the existing
authorization and fresh authenticated channel remain mandatory.

Operation persistence receipts and gift content receipts remain distinct. The
gift receipt checks the gift, creation operation, recipient and original asset
hashes; its authenticated arrival must not be inferred from an operation ACK or
a completed socket send. Native App log and media producers share a bounded
ordered clear-content writer, which allocates cipher sequences and writes them
through one consumer. The writer's concurrent-producer, cancellation and bounds
tests are separate from physical media evidence.

This is developer source/test review. It is **not an independent protocol security
review**, penetration test or production release approval.

## Remaining acceptance gates

1. Use a VPN-free Mac route/test host, verify independent Wi-Fi/mobile routes and
   no USB/reverse-tunnel business path, then repeat both invitation directions
   through the normal isolated Apps. The current user's VPN setting is retained.
   Record direct and encrypted-relay paths separately.
2. Extend passed wish/expense UI cases to physical recurring bills and remaining
   domain-specific offline/restart cases.
3. Complete normal-App audio import/playback and physically interrupt/resume a
   media transfer. The photo raw hash, save-original and content receipt have
   passed below; local bridge tests do not replace the remaining physical cases.
4. Inspect hosted CI for the published commit and preserve independent protocol
   security review, the pinned native-library platform constraints and human
   visual review as release gates.

No production deployment, production App installation, user-data reset, key
rotation, pairing reset, PR merge or visual-baseline approval is authorized by
this acceptance checkpoint.

### Physical original-photo checkpoint

Both isolated Apps were updated together (Mac QA Build 18 / Android nativeQa
code 12). They reopened the same QA roots and reconnected without pairing again.
Read-only comparisons show the QA identity/transport-key files are unchanged.
The sender used the regular menu/composer and native photo chooser. The receiver
initially showed an unopened history item; the sealed reveal contained no private
text or image in the UI hierarchy. The transferred original is 1,845,914 bytes and
matches the imported synthetic PNG SHA-256 exactly. USB was used only to inspect
the verified QA original after transmission. The sender's normal gift history
shows **Synced**, independently of the operation ACK. Audio playback and startup one-time reveal acceptance still require
their own observations.

An interruption before sending was retained: the phone foreground was the older
Debug package, so the QA foreground session stopped normally. Reopening the QA
App and reconnecting restored the session. This is not attributed to a media
protocol bug. CUA audio-menu operations reported changed-window/time-out errors;
the cause of that automation failure remains unresolved. No ambient recording or
microphone permission was requested in this run.

The receiver then used **Save Photo** in the normal gift reveal and confirmed
the system document picker. The exported PNG is also exactly 1,845,914 bytes and
has the same SHA-256 as the imported original. No resizing or transcoding
occurred. This synthetic export was requested by the QA interaction; no private
photo was selected or automatically exported. Private evidence:
`android-photo-save-original.json`, `android-photo-save-panel.xml`,
`android-gift-before-open.xml` and `android-photo-opened.xml`.

## Build, regression and publication checkpoint

- Mac QA Build 18 and default non-QA arm64 Debug compile: PASS. The default
  package remains macOS 14.0 / TogetherCore only. This is not a Universal Release
  or production installation claim.
- Android nativeQa code 12, helper and default C1 Debug builds: PASS with strict
  dependency verification. The default Debug APK contains no Iroh native library.
- Targeted shared Core regressions: Swift 24 PASS / Kotlin 15 PASS; native Swift
  transport regressions: 14 PASS; portable protocol checks: 17 PASS. These are
  selected suites, not an all-project or physical-network total.
- Android copy: 588 entries, 0 errors / 0 warnings. Apple copy: 0 errors /
  14 previously retained warnings. No audit rule or comparison threshold relaxed.
- Android nativeQa lint: 0 errors / 17 warnings. The pinned Iroh library's 4 KiB
  arm64 segment alignment remains incompatible with a 16 KiB-page release
  requirement. The measured Samsung uses 4 KiB pages; its result does not remove
  this release gate.
- Production Mac store/WAL/SHM/identity: four read-only baseline hash comparisons
  remain unchanged. QA identity files and Android native transport key also match
  before/after the QA-only update. Production App installation is unchanged.
- Candidate screenshots, source/runtime logs, stores, keys and APKs stay local.
  Publication scanning covers tracked/new source and ref/reflog history; this is
  a credential/data-leak gate, not independent protocol security approval.

Normal-App opposite invitation direction, audio-menu/playback completion,
physical interrupted-media resume and fully VPN-free public acceptance remain
NOT RUN. Core synthetic resume coverage is separate. Further phone automation
paused when the device foreground moved to other applications; no unrelated App
was controlled. The existing independent protocol/security review release gate
remains open. No production Worker was deployed or any PR merged.
