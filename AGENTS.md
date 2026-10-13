# Together engineering gates

- Keep Swift, SwiftUI, SwiftData and the Local-first signed operation log. Do not replace the stack or reset user data.
- Follow [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md) and [UI_COPY.md](UI_COPY.md); register new copy in the String Catalog and review index.
- Do not add decorative prose, fake statistics, mock product content, or unimplemented feature claims. Never rewrite user-authored text automatically.
- Love Gifts are event-driven sheets and native menus, never a permanent Home/sidebar module.
- Sidebar is Home / Plans / Wishes, stacked vertically, with Connection / Settings at the bottom. Reuse one task list/editor; Wishes retains its separate ledger. No horizontal Tasks / Wishes mode picker.
- Device identity uses owner-only local files; preserve existing keys/pins and require explicit legacy migration, never silent rotation or automatic Keychain reads.
- Use isolated deterministic test fixtures. Production must never load them. Our Story/Time Capsule are not implemented; do not invent placeholder pages.
- After changes run `make qa` where available. Report business, server, UI, copy and visual checks separately; never call an unrun test PASS.
- Important visual changes require captured screenshots and comparison with human-approved baselines. Candidates do not approve themselves.
- Keep legacy transport until migration tests pass. Do not deploy, claim E2EE review, offline delivery or real cross-Wi-Fi acceptance without evidence.
- Local delivery: after `make package`, run `make install` for the authorized local workflow. `/Applications/Together.app` is the daily entry; the installer goes to Desktop. Remove only generated App bundles/stale registrations after full bundle/hash checks; retain source, QA results and user data.
- Final report: Changed / Build / Tests / Copy QA / Visual QA / Security / Issues, normally at most 10 lines; include concrete failures.
