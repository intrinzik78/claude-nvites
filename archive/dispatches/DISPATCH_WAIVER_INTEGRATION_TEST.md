# DISPATCH: Waiver Discrete Flow Integration Test

**Date:** 2026-03-15
**Target:** server branch
**Depends on:** DISPATCH_DOCUMENT_TIMESTAMP_BUG.md (document retrieval must work)

---

## Problem

The discrete waiver flow (begin → consent → confirm → sign) has unit tests for transforms, error codes, and validation, but no integration test that exercises the full state machine against a real database. The workflow engine has this pattern (`integration_tests.rs`) and it has caught real bugs. The waiver state machine is equally critical.

## What to test

Add integration tests in `server/api/src/types/waivers/` (new file, e.g. `integration_tests.rs`) following the workflow integration test pattern:

### Happy path
1. Seed a document with content_hash
2. Seed a user (person + user rows)
3. Call `begin_tx` — assert Draft status, content_hash_at_begin populated, expires_at set
4. Call `consent_tx` — assert Ok
5. Call `confirm_tx` — assert Ok
6. Call `sign_tx` — assert Pending status, signature_data set, signed_document_hash set
7. Verify `fetch_audit_trail` returns events in correct order with distinct timestamps

### State machine enforcement
- Call `consent_tx` without begin → `WaiverAuditPrerequisiteMissing`
- Call `confirm_tx` without consent → `WaiverAuditPrerequisiteMissing`
- Call `sign_tx` without consent → `WaiverAuditPrerequisiteMissing`
- Call `sign_tx` without confirm → `WaiverAuditPrerequisiteMissing`

### Idempotency
- Call `consent_tx` twice → second returns Ok, no duplicate audit row
- Call `confirm_tx` twice → same

### Ownership
- Call `consent_tx` with wrong `signer_user_id` → `WaiverNotFound`

### Expiry
- Create a draft, manually set `expires_at` to past, call `consent_tx` → `WaiverExpired`

### Content hash verification
- Begin with document, modify `document_body.json` between begin and sign → `WaiverDocumentIntegrityFailed`

### Sweeper
- Create expired draft, call `delete_expired_drafts` → row deleted, audit rows cascade-deleted

## Pattern

Follow `server/api/src/types/workflow/integration_tests.rs`:
- `#[cfg(test)]` module
- `#[sqlx::test]` or manual pool + transaction with rollback
- Fixture helpers for document + person seeding
- Static atomic counters for unique UUIDs
