# GitHub main protection

Verified on 2026-10-17 for the Public `Diamond-Fountain-Works/Together` repository.
GitHub repository settings are server configuration; this document describes the verified policy,
not a claim that committing a file configures protection.

- Exact protected branch: `main`; protections apply to administrators too.
- No force pushes or branch deletion.
- Changes require a pull request. No PR was merged as part of configuration.
- Required GitHub Actions app checks (app ID 15368): `macOS build, Swift, local relay and migration`
  and `Relay, protocol, copy and source safety`.
- Branch must be current with its base; review conversations must be resolved.
- Zero mandatory independent approvals while the repository has only one write-capable account.
  The author cannot approve their own PR. User approval before agent merges remains required.
- No linear-history restriction: the existing migration history may retain merge commits.
- No deployment requirement or permission grant was added; visibility remains Public.

Read-only verification: `gh api repos/Diamond-Fountain-Works/Together/branches/main/protection`
and `gh api repos/Diamond-Fountain-Works/Together/branches/main`. The latter must report
`protected: true`. Compare the two check names when renaming CI jobs, so a required check cannot
become permanently pending. Android checks remain additional PR checks rather than requirements
for pre-Android source trees. No destructive push/delete probe is used to test this policy.

The initial API configuration and readback are saved in ignored local Phase C QA evidence.
The main commit SHA was unchanged before/after protection. Rules may later be changed by an
administrator; this document is an audit record, not proof of future settings.
