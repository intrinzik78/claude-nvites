# DISPATCH: Remove Internal FKs from Consumer WaiverDto

**Date:** 2026-03-15
**Target:** server branch
**Priority:** Low — no consumer currently uses these fields for API calls

---

## Problem

`WaiverDto` (consumer-facing) still exposes two internal foreign keys:

- `signer_user_id: i32` — FK to `user.id`. Consumers are already authenticated as the signer; they don't need this for any API call. Could be replaced with a display name if surfaces need to show "signed by."
- `document_id: Option<i32>` — FK to `document.id`. Consumers use `document_uuid` for document retrieval, never `document_id`. No consumer endpoint accepts a `document_id` parameter.

Neither is a DEC-128 violation (they're not waiver IDs), but they leak internal schema structure to consumers unnecessarily.

## Before implementing

Verify these fields are still on `WaiverDto` — a prior session may have already cleaned them up. Check `api-contracts/src/waivers.rs` for the current struct definition. If the fields are already removed, archive this dispatch.

## Exploration needed

Before removing, verify:

1. **`signer_user_id`** — Do any surface components display "signed by user #42"? If so, they should use a name field, not an ID. Check `SignedWaiverRecordDto` to see if it already carries participant/signer name data that makes the ID redundant.
2. **`document_id`** — Confirm no surface code reads `waiver.document_id`. The portal record endpoint returns the full document content via `SignedWaiverRecordDto.document`, making the FK unnecessary.
3. **`StaffWaiverDto`** — Both fields should stay on the staff DTO (staff endpoints may need them for cross-referencing).

## Proposed change

Remove `signer_user_id` and `document_id` from `WaiverDto`. Keep them on `StaffWaiverDto`. This is a contract change — run the full pipeline and update SDK type exports.
