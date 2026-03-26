# Dispatch: Email table vs EmailID enum — resolve source of truth

**Date:** 2026-03-20
**From:** dev session (crosscutting)
**To:** server worktree
**Priority:** Medium — not blocking launch, but a quiet inconsistency that will confuse future work

---

## Problem

Sender addresses for outbound emails exist in two places:

1. **`email` database table** — `from_address` and `reply_to_address` columns, populated by migration `20260224000000_fix_email_sender_addresses.sql`. Currently holds stale `@battletexas.com` addresses (`noreply@` for id=1, `bookings@` for id=2). Rows for ids 3 and 4 (QueuePendingConfirmation, WaiverConfirmation) were never updated by that migration.

2. **`EmailID::from_address()` in `server/api/src/enums/email_id.rs`** — hardcoded Rust enum returning the correct `@urbanwarzonepaintball.com` addresses:
   - EmailVerification (1) → `verify@urbanwarzonepaintball.com`
   - BookingConfirmation (2) → `events@urbanwarzonepaintball.com`
   - QueuePendingConfirmation (3) → `contact@urbanwarzonepaintball.com`
   - WaiverConfirmation (4) → `events@urbanwarzonepaintball.com`

Every handler that sends email uses `email_id.from_address()` — the Rust enum, not the database. The DB values are never read for sending. This means:

- The `email` table has stale data that no code path consumes
- The table gives a false impression that it controls sender addresses
- A future developer reading the table would see `@battletexas.com` and assume that's what's being sent
- The `from_address` and `reply_to_address` columns on the `email` table are effectively dead columns for sending purposes

## Options

### Option A: Enum is canonical — clean up the table
**Confidence: High**

Accept that `EmailID::from_address()` is the source of truth. Write a migration to update the `email` table rows to match the enum values, so the DB at least isn't misleading. The columns become documentation, not configuration.

Pros: Minimal code change. Honest data. No behavioral change.
Cons: The columns still exist but serve no functional purpose.

### Option B: Table is canonical — read from DB
**Confidence: Low**

Refactor `EmailID::from_address()` to read from the `email` table at startup (or per-request). The table becomes the configuration source, editable without redeployment.

Pros: Sender addresses become runtime-configurable.
Cons: Adds a DB dependency to what's currently a pure function. Over-engineering for a single-venue business with 4 email types that change approximately never. The Postmark verified-sender list is the real constraint — changing the DB value without updating Postmark causes `SendingEmailAddressNotPermitted`.

### Option C: Remove dead columns from the table
**Confidence: Medium**

If the table's `from_address` / `reply_to_address` columns aren't used, migrate them away. The `email` table would keep only the template-related columns (subject, html_body, text_body, etc.).

Pros: No dead data. Clean schema.
Cons: Destructive migration. Need to verify nothing else reads those columns (campaign_email has its own from_address — check that it's independent).

## Proposed Solution

**Option A.** Write a migration that updates the 4 `email` rows to match `EmailID::from_address()` values. This is the lowest-risk fix — it makes the data honest without changing any code paths or schema. If a future decision moves to Option B or C, the data is at least correct in the meantime.

```sql
UPDATE `email` SET `from_address` = 'verify@urbanwarzonepaintball.com', `reply_to_address` = 'verify@urbanwarzonepaintball.com' WHERE `id` = 1;
UPDATE `email` SET `from_address` = 'events@urbanwarzonepaintball.com', `reply_to_address` = 'events@urbanwarzonepaintball.com' WHERE `id` = 2;
UPDATE `email` SET `from_address` = 'contact@urbanwarzonepaintball.com', `reply_to_address` = 'contact@urbanwarzonepaintball.com' WHERE `id` = 3;
UPDATE `email` SET `from_address` = 'events@urbanwarzonepaintball.com', `reply_to_address` = 'events@urbanwarzonepaintball.com' WHERE `id` = 4;
```

## Before implementation

- Verify that `campaign_email.from_address` is independent from `email.from_address` (different table, different purpose)
- Check if any other code reads `email.from_address` or `email.reply_to_address` — a grep should confirm they're dead
- Decide whether to add a comment to `EmailID::from_address()` noting it's the canonical source

## After completion

- Note the decision in the handoff (enum is canonical, table is documentation)
- Flag for future DEC promotion if the pattern should be formalized
