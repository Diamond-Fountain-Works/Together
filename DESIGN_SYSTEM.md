# Together Design Language — Shuffles Like a Dream

## Contract

Native macOS, Soft / Dreamy / Fluid / Refined. The design must help users recognize state and act; decorative quality is not an acceptance argument. One system applies to Home, Plans, Wishes, Our Finances, menu-driven Love Gifts and Settings. Our Story and Time Capsule inherit this contract when implemented; this document does not declare them implemented.

## Tokens

`TogetherTheme` is the code authority. Warm Ivory detail background (light: #FBF7F0); dark warm charcoal (#1B181A). Soft Rose accent (RGB 0.77, 0.40, 0.47). Primary/secondary/tertiary text and ordinary surfaces use semantic system colors. Muted Gray is a semantic secondary tone, not a hardcoded low-contrast text color.

Spacing scale: 4, 8, 12, 16, 20, 24, 30 pt. Page inset 30 pt, form/sheet inset 26–32 pt, ordinary card inset 20 pt, ordinary card radius 16 pt, input/media preview radius 12 pt. Native controls retain native metrics. Page heading 30 pt semibold rounded, section heading system headline, body system body, status caption. Do not invent per-page fonts, shadows, radii or spacing scales.

Ordinary cards use a subtle system surface and one faint border, not glass on every surface. Materials/glass are reserved for native chrome, a limited modal/footer treatment, or the gift interaction. No full-page pink gradients; no opaque sidebar painting. Use the native flat sidebar and standard selection.

## Hierarchy and copy

One page title, relevant content, one clear primary action. Avoid duplicate brand/welcome banners and prose under ordinary page titles. Cards present real counts, actual records or an actionable empty state. Hide Home Upcoming content when there are no upcoming tasks. Do not turn an empty page into motivational copy.

Follow UI_COPY for categories, budgets, approval and audit. User text is data: display it faithfully; never shorten or rewrite it for aesthetic reasons. Long user content scrolls/wraps. Emotional copy belongs to gifts and specifically approved emotional interactions.

## Motion

Ordinary navigation/list changes favor opacity plus at most 12 pt movement. Motion tokens: Quick 180ms, Standard 280ms, Expressive 420ms; standard spring damping 0.9. Plans and Wishes use vertically stacked native sidebar rows; switching content moves at most 8pt. Task filters use a native segmented Picker and short list fades without large transitions. No permanent animation, particles, random rearrangement or large page bounces. Matched geometry, where used, must preserve recognizability and never block clicks or database commits. Task editing uses native sheets without cross-window geometry matching.

Sidebar: Home / Plans / Wishes / Our Finances, in that vertical order, with Connection / Settings anchored at the bottom. Do not add a second horizontal Tasks / Wishes switch. Plans owns a single task workspace and one task editor. Pending exposes the primary New Task; Upcoming / Completed do not add duplicate create controls. Native Command + N calls that same editor. Wishes keeps a single Add Wishes action and dated ledger details. Home summary cards are navigation links; no empty Upcoming section or full duplicated workspace.

Gift Reveal may use a continuous envelope expansion and sequenced appearance of actual content. Its sealed state must not render private text, audio or photo in either pixels or accessibility. Audio never autoplay. Reduce Motion uses no movement or weaker fades; fixed-time snapshot fixtures disable nondeterministic motion without disabling real business actions.

## Desktop behavior

Pointer and keyboard first. Native menus expose Send Love Gift (Cmd+Shift+L) and History. Native file/save panels handle import/export. Controls with no possible behavior are disabled with a clear status, not clickable marketing placeholders. Sheets have a clear closing action; only incomplete Initial Setup intentionally requires completion. Long media/editor/release content must scroll with reachable actions.

## Review evidence

Run copy audit, applicable build/business/server/UI tests and screenshot capture. Capture a deterministic case matrix at 1100×760 pt, zh-Hans/zh_CN, fixed injected date, explicit light/dark, and isolated data. Separate empty, populated, disconnected and reduced-motion cases. Missing Our Story is tracked as NOT IMPLEMENTED, not replaced with a screenshot of a fake page.

New screenshots go to candidates. Only a human approval tied to the reviewed image hash may update approved baselines. Obvious layout/content drift fails comparison; smaller differences require location-specific review. Font/OS/render changes must be investigated, not blanket-approved. Record actual SDK, scale, language and fixture manifest.

## Our Finances 0.2.1

Exactly three native segmented tabs: United Reserves, Expenses and Recurring Bills. Cycles and payment-tool profiles live in a settings sheet. One context-sensitive primary create action per tab. No bank-connected, approval, debt or AA page. Use monospaced amount digits and semantic negative/pending states; values always come from the ledger. Distinguish book balance, reconciled balance and provisional shared spending; do not imply bank verification. Compact windows may put tabs below the title. Category chips wrap. The searchable currency/day wheels accept pointer, scroll and arrow keys, with native focus; changing currency clears unsettled inputs. Ordinary transitions use Standard 280ms or reduced motion. Reminders and remote-change banners do not present blocking sheets. Cards share existing TogetherCard tokens.
