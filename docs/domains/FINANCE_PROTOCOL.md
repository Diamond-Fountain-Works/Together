# Finance protocol 3

This is an extension of the existing signed operation envelope and encrypted SyncTransport, not a SwiftData transport or a second ledger. Service HTTP/framing protocol remains 1; DeviceDescriptor version 3 signifies finance-entity support. Two clients with different device versions reject the session before log exchange. Server routing accepts 2 and 3 and retains the original route/key pins.

## Portable values

UUIDs use the existing uppercase canonical format. Lamport order is clock, Device ID, Operation ID; wall-clock time is not a conflict winner. Minor-unit values are signed decimal Int64 **strings** in money JSON. ISO currency precision is bundled, original amounts must fit it, and final CNY uses 2 digits. Decimal rounding is half away from zero (Kotlin BigDecimal HALF_UP). Tiny positive foreign amounts may round to zero CNY without losing their original record. Checked sums fail on overflow. The current per-entry magnitude bound is 90,000,000,000,000 minor units.

```json
{"currencyCode":"USD","finalCNYMinor":"70007","originalMinor":"10001","settlementBasis":"actualCNY"}
```

An optional `exchangeRate` object contains `cnyPerOriginalUnit` (decimal string), `source` and `quotedOn` (CivilDate). Reference basis requires a matching calculated CNY amount; actualCNY may intentionally differ from a reference quote. The quote is stored, never globally refreshed. CivilDate is `{year,month,day}`, FinanceMonth is `{year,month}`, and dates in the signed envelope retain the existing integer epoch-millisecond convention. Quote dates are calendar dates and use UTC only as the editor representation, avoiding Mac-zone shifts.

Money/payment/calendar domain objects are canonical UTF-8 JSON carried in the existing LogValue.data base64 envelope. They contain no ModelContext, persistentIdentifier, NSImage or SwiftData relationship. A future client must implement the existing JSON tag, signature canonicalization and frame protocol as well as these objects; this document is not an Android implementation.

## Entities and permissions

| Entity type | Actual record / metadata | Mutation |
|---|---|---|
| reserveEntry | Opening or deposit, depositor user ID, money, CivilDate, notes | Create, field patch, Tombstone; one deterministic opening ID |
| dateEvent | Independent dated event; multiple per date | Create/patch/Tombstone; expenses retain the historical association |
| expense | Single actual ledger record, source, amount/payment, review status | Create/patch/Tombstone; reconciliation never creates another expense |
| recurringBill | Original monthly day/zone/start month, default amount/payment | Create, title/category patch, terminate Tombstone |
| billRevision | Immutable next-month defaults or future lifecycle change | Create only; old revisions remain auditable |
| billOccurrence | Per-month forecast override, no actual debit | Sparse amount/payment create/patch |
| financeSettings | Shared or owner cycle and planning days | Shared members can edit shared settings; personal settings only owner |
| paymentMethod | Shared last-four card metadata, independent of funding | Only creator/owner writes; private cards never transmitted |

Personal settings and cards use real owner UUIDs. Labels do not authenticate or authorize. Both members can correct shared ledgers without partner approval. The existing verified device/actor/space context is enforced on every projection. Invalid inputs remain diagnosable and cannot inflate balances.

## Deterministic instances and conflict handling

The existing StableID hashes UTF-8 with SHA-256, takes 16 bytes and sets UUID version/variant bits. Instance seed: `finance-bill:<UPPERCASE billId>:<YYYY-MM>`. Forecast seed: `finance-forecast:<UPPERCASE billId>:<YYYY-MM>`. Settings seed: `finance-settings:shared` or `finance-settings:<UPPERCASE ownerId>`. Opening seed: `finance-reserves-opening`. Duplicate generation operations replay to one actual Expense. Stable settings/opening/forecast initializers merge mutable fields by Lamport order, so independent offline initialization does not silently use the earliest value.

Amount and payment each merge as an atomic domain snapshot; unrelated fields merge independently. Editors retain their original baseline and only submit fields the user changed, preserving updates arriving while a sheet is open. Stale reconciliation refuses to confirm an unseen new amount/payment. Regular default amount/payment changes become effective next **natural month** in the bill zone, not next financial cycle. The original monthly day is preserved across short months. Reconciliation freezes accepted values; late valid defaults resolve unreviewed instances consistently. Pausing/terminating future rules retains past dues and suppresses inactive unreviewed future candidates. Tombstones never resurrect.

## Delivery and privacy

The relay forwards authenticated encrypted messages in real time. It does not compute balances or store an offline financial mailbox. A socket or local save does not establish remote receipt. Existing log convergence/acknowledgement and media validation semantics remain; no Delivered claim or bank verification is introduced. Local card privacy is a routing exclusion, not remote deletion of previously shared history. Existing encryption needs independent security review and does not add local at-rest encryption.
