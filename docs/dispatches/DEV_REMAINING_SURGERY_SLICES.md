# Dispatch: Complete remaining surgery slices (4-9)

**Date:** 2026-03-26
**Workstream:** dev

## Problem

The api-contracts layer has been gutted (slices 1-3 complete) but the downstream crates still reference deleted types. The codebase does not compile. Remaining slices need to cascade the cleanup through schema-emitter, api crate, database, SDKs, and surfaces.

## Reasoning

- Slices 1-3 removed contracts for bookings, waivers, queues, albums, extractions
- Red team report (this session) identified 20 landmines — most are in remaining slices
- Each slice has a natural commit point for rollback safety
- The compiler guides the work from here — `cargo check` surfaces each broken reference

## Proposed Solution

Slice order (established in this session):

4. **schema-emitter** — remove path/schema registrations for deleted contracts
5. **api crate + doc-extractor** — delete handler modules, sweepers, error variants, env.rs extractor fields, route_collection sentinel tests. Remove doc-extractor from Cargo.toml. Redesign `PaymentTransaction::to_held_dto()` (see SERVER_PAYMENT_BOOKING_FK dispatch)
6. **database** — remove orphaned queries/models. See `TABLES_TO_REMOVE.md`
7. **sdk-rust + sdk-ts** — remove client modules and hand-written type re-exports for deleted domains
8. **surfaces** — remove pages/components/Tauri commands referencing deleted SDK types
9. **proof of life** — `cargo xtask build-all` passes

Key landmines from red team:
- `doc-extractor` is NOT a leaf — has tendrils into api crate (Cargo.toml, error.rs, main.rs, env.rs)
- `route_collection.rs` has sentinel tests with hardcoded counts (PUBLIC_ROUTES, EXPECTED_SCOPE_COUNT)
- `email-template` has dead booking/waiver variants (clippy cleanup)
- CI has EXTRACTOR_* env vars to remove

## Confidence

**High** — plan is validated by red team, each slice is compiler-guided
