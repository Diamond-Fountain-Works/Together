# Together engineering gates

- Keep Swift, SwiftUI, SwiftData and the Local-first signed operation log. Do not replace the stack or reset user data.
- Follow [DESIGN_SYSTEM.md](docs/design/DESIGN_SYSTEM.md) and [UI_COPY.md](docs/design/UI_COPY.md); register new copy in the String Catalog and review index.
- Do not add decorative prose, fake statistics, mock product content, or unimplemented feature claims. Never rewrite user-authored text automatically.
- Love Gifts are event-driven sheets and native menus, never a permanent Home/sidebar module.
- Sidebar is Home / Plans / Wishes / Our Finances, stacked vertically, with Connection / Settings at the bottom. Our Finances has only Reserves / Expenses / Bills tabs. Reuse one task list/editor; Wishes retains its separate ledger. No horizontal Tasks / Wishes mode picker.
- Language selection is an icon-only globe inside Settings; click/tap opens Chinese/English choices. Keep both resource sets complete and run `make localization-qa`. Preserve user-authored text.
- Mac and Android Plans expose only Pending / Completed. Future, overdue and undated unfinished tasks share Pending; do not restore a separate Upcoming tab. Preserve scheduled-task execution rules.
- Device identity uses owner-only local files; preserve existing keys/pins and require explicit legacy migration, never silent rotation or automatic Keychain reads.
- Use isolated deterministic test fixtures. Production must never load them. Our Story/Time Capsule are not implemented; do not invent placeholder pages.
- After changes run `make qa` where available. Report business, server, UI, copy and visual checks separately; never call an unrun test PASS.
- Important visual changes require captured screenshots and comparison with human-approved baselines. Candidates do not approve themselves.
- Keep legacy transport until migration tests pass. Do not deploy, claim E2EE review, offline delivery or real cross-Wi-Fi acceptance without evidence.
- Finance uses integer minor units/Decimal, frozen CNY snapshots and one Expenses ledger. Preserve existing storage schema, signed logs, keys and pairings; recurring instances use deterministic bill/month IDs. Private card metadata stays local.
- Build/package does not authorize replacing `/Applications/Together.app`. Install or deliver to Desktop only when the current user task explicitly authorizes it; preserve source, QA and user data.
- Final report: Changed / Build / Tests / Data Migration / Sync QA / Copy QA / Visual QA / Issues, normally at most 10 lines; include concrete failures and unrun checks.

- Monorepo source authority: apps/apple/macOS, packages/together-core-swift, services/relay; qa/project.json resolves tooling paths. Version history lives in Git, never new copied source folders.
- App/sync/storage versions are separate. Keep C1 and the actual 10-minute invite unchanged here; the formal 8-hour requirement is tracked in Issue #1 for a separate network PR/deployment.
- Scan tracked files and Git history before publishing. Never commit actual stores/media/logs/keys/credentials. Local-only artifacts stay excluded; CI uses synthetic fixtures and local relay only.
