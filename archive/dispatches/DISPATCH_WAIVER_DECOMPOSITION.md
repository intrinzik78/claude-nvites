# DISPATCH: Decompose waiver.rs into scoped modules

**Date:** 2026-03-15
**From:** dev session (architecture review of waiver system complexity)
**To:** server (next session)
**Priority:** High — primary fix for waiver system fragility

---

## Problem

`server/api/src/types/waivers/waiver.rs` is 2,267 lines with 44 public functions mixing 6 distinct concerns:
- State machine transitions (begin, consent, confirm, sign)
- SQL queries (12+ distinct query patterns)
- Hash computation (content hash, signed document hash, verification)
- Audit trail management (7 event types across subtables)
- Document retrieval and verification
- Accessors (21 getter methods)

Every waiver session touches this file. Every change risks breaking unrelated functionality. The file is too large for any agent or human to hold in working memory, which is the direct cause of repeated rework and regressions.

## Goal

Decompose into a parent module with focused sub-modules. Same code, same behavior, same public API. No functional changes. The `Waiver` struct and its `impl` blocks can span multiple files via `mod` + re-export, or methods can be organized into separate impl blocks in separate files.

## Proposed structure

```
server/api/src/types/waivers/
  mod.rs                    -- existing, update exports
  waiver.rs                 -- parent: struct definition, accessors (21 getters), re-exports
  waiver_queries.rs         -- all sqlx::query_as calls: by_id, by_uuid, find_by_*, count_*, delete_expired_drafts
  waiver_state_machine.rs   -- begin_tx, consent_tx, confirm_tx, sign_tx (the 4-step discrete flow)
  waiver_paper.rs           -- create_paper_tx (different flow, different validation, no document/signature)
  waiver_hashing.rs         -- compute_document_hash, compute_signed_document_hash, verify_signed_document
  waiver_audit.rs           -- fetch_audit_trail, record_view_audit, create_accept_audit_tx
  waiver_document.rs        -- fetch_document, fetch_document_by_uuid, fetch_current_document_uuid
  waiver_collection.rs      -- existing, no changes needed (105 lines, already clean)
  waiver_validation.rs      -- existing, no changes needed (329 lines, already clean)
  draft_sweeper.rs          -- existing, no changes needed (54 lines, already clean)
  integration_tests.rs      -- existing, no changes needed (943 lines)
```

## Implementation approach

**Option A: Separate impl blocks in separate files (recommended)**

Rust allows multiple `impl Waiver` blocks. Each sub-file defines its own `impl Waiver` block for its concern. The parent `waiver.rs` holds the struct definition and accessors. Sub-files import the struct and add methods.

```rust
// waiver_queries.rs
use super::waiver::Waiver;

impl Waiver {
    pub async fn by_id(id: i32, db: &DatabaseConnection) -> Result<Option<Self>, Error> { ... }
    pub async fn by_uuid(uuid: &str, db: &DatabaseConnection) -> Result<Option<Self>, Error> { ... }
    // ...
}
```

**Pros:** No public API change. Callers still write `Waiver::by_id()`. No trait gymnastics.
**Cons:** Requires the struct fields to be `pub(super)` or the sub-files to be in the same module. Since they're all in `types/waivers/`, this works naturally.

**Option B: Free functions with Waiver parameter**

Convert methods to functions: `sign_tx(waiver: &Waiver, ...) -> ...`. Callers change from `Waiver::sign_tx(...)` to `waiver_state_machine::sign_tx(&waiver, ...)`.

**Pros:** Clear separation, each file is fully self-contained.
**Cons:** Breaks the existing API. Every handler file changes. More churn for the same result.

**Recommendation: Option A.** Zero public API change, minimal handler churn, natural Rust pattern.

## Unit tests

`waiver.rs` contains inline `#[cfg(test)]` modules that account for roughly half the file's size. These tests must also be decomposed.

**Rule: tests live in the file they test.** When a test clearly exercises a single concern (e.g., `test_compute_document_hash` tests hashing), move it to that concern's file (e.g., `waiver_hashing.rs`). When a test exercises cross-concern behavior (e.g., a test that calls `begin_tx` and then checks the content hash), place it in whichever file owns the primary function under test.

**Do not create a standalone unit test file.** A 1,000-line test file reintroduces the god-file problem we're solving. The point of co-location is that when you open `waiver_state_machine.rs`, you see its tests right there — no hunting.

**Note:** `integration_tests.rs` (943 lines) is a separate file that tests against real MySQL. Leave it untouched. It exercises the public API of `Waiver`, which doesn't change in this decomposition.

## Verification checklist

After decomposition:
1. `cd server && cargo xtask build-all` must pass
2. `cd server && cargo test -p uwz-server` must pass — integration_tests.rs exercises the full state machine
3. No handler file should need changes (public API unchanged)
4. Each sub-file should be under 400 lines
5. Run `/review-rs` on each new file

## Files to load into context

Before starting the decomposition, read these files completely:
- `server/api/src/types/waivers/waiver.rs` — the 2,267-line file being decomposed
- `server/api/src/types/waivers/mod.rs` — current module exports
- `server/api/src/types/waivers/waiver_collection.rs` — for reference (already clean, don't touch)
- `docs/ESIGN_GUIDE.md` — understand which functions serve ESIGN requirements vs. operational practice
- `docs/waiver-esign-map.json` — hash scheme reference (critical for waiver_hashing.rs correctness)

Do NOT load handler files, api-contracts, or integration tests into context during decomposition. The decomposition is internal to the waivers module. If Option A is used correctly, nothing outside `types/waivers/` should change.

## What this does NOT address

- `sync_waiver_count` simplification (see DISPATCH_WAIVER_DESIGN_DECISIONS.md Decision 1)
- Walk-up waiver attachment (see DISPATCH_WAIVER_DESIGN_DECISIONS.md Decision 3)
- Split normalize guards (see DISPATCH_SPLIT_NORMALIZE_GUARD.md)
- Any functional changes to waiver behavior

This is purely organizational. Same code, same tests, same behavior. Smaller files.

## Risk assessment

**Risk: Low.** This is a mechanical refactor within a single module. Integration tests cover the full state machine. The build pipeline (`cargo xtask build-all`) catches contract-level breakage. The only risk is a missed import or visibility issue, both of which are compile errors (not runtime bugs).
