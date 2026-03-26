# DISPATCH: Waiver Integration Test Coverage Gaps

**Date:** 2026-03-15
**Target:** server branch
**Depends on:** DISPATCH_WAIVER_INTEGRATION_TEST.md (complete — archived)

---

## Problem

The waiver integration tests (`server/api/src/types/waivers/integration_tests.rs`) cover the core discrete flow state machine (11 tests), but do not exercise four additional code paths that run against real MySQL and have non-trivial logic.

## What to add

Extend `integration_tests.rs` with these tests, using the existing fixture helpers.

### 1. `test_verify_signed_document`

The most critical gap. `verify_signed_document()` runs on every portal record retrieval and recomputes the `signed_document_hash` from document components + audit trail. No integration test validates this end-to-end.

- Full happy path (begin → consent → confirm → sign)
- Call `verify_signed_document(waiver_id, document_id, signed_document_hash, db)` → assert Ok
- Tamper `document_body.json` → call again → assert `WaiverSignedHashVerificationFailed`
- Restore body, delete `waiver_audit_sign` row → call again → assert `WaiverAuditTrailCorrupted`

### 2. `test_accept_flow`

Staff acceptance path: `accept_batch_tx` + `create_accept_audit_tx`.

- Seed booking + waiver collection (reuse workflow fixture pattern from `workflow/integration_tests.rs`)
- Full flow through sign → attach to booking → accept
- Verify waiver status transitions to Accepted (2)
- Verify `waiver_audit_accept` row exists with `accepted_by_user_id`
- Verify `fetch_audit_trail` includes `accept` event

### 3. `test_paper_waiver`

Staff paper waiver creation via `create_paper_tx`.

- Seed booking + user
- Call `create_paper_tx` with params
- Assert: status = Accepted (2), document_id = None, has_signature = false
- Assert: `waiver_audit_create` exists (minimal audit trail)
- Assert: no consent/confirm/sign audit events

### 4. `test_child_waiver_begin`

Child waiver begin with minor-specific validation at DB level.

- Seed document + user
- Call `begin_tx` with `is_minor: true`, `guardian_relationship: Some(Parent)`, `participant_dob: Some(minor_date)`
- Assert: waiver created with `is_minor = true`, guardian_relationship = Parent
- Verify DB CHECK constraints are satisfied (guardian required for minor, DOB required for minor)

## Pattern

Follow existing `integration_tests.rs` helpers and cleanup patterns. The accept flow test will need booking/collection fixtures — reuse the `WaiverFixture` pattern from `workflow/integration_tests.rs`.
