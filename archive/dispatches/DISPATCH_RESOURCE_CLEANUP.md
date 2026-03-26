# Dispatch: Rust enum cleanup — BookingResourceType

**Date:** 2026-03-21
**From:** dev session (product catalog migration)
**To:** server worktree (next session)
**Priority:** Low — no runtime impact, but creates confusion if new resource types are added before cleanup

---

## Problem

The product catalog migration (`20260321120000`) deleted `PartyRoom (1)` and `AxeLane (2)` from the `booking_resource_type` lookup table. The DB now has only `PaintballMarker (0)`. However, the Rust `BookingResourceType` enum still defines all three variants. The enum and DB are out of sync.

Nothing breaks at runtime — no products or resources reference the deleted types, and no code paths match on `PartyRoom` or `AxeLane`. But the next person adding a resource type will see stale variants in the enum and may pick conflicting discriminant values or assume those types are still active.

## Proposed Solution

1. Remove `PartyRoom` and `AxeLane` variants from the `BookingResourceType` enum
2. Grep for any match arms or references to the removed variants and clean them up
3. Run `cargo xtask build-all` — the schema-emitter will regenerate the OpenAPI spec without the removed types
4. Run `cargo test` to verify nothing depended on them
5. Update `sdk-ts` generated types if the build pipeline doesn't handle it automatically

## Reasoning

The enum should match the DB. Dead variants in a `repr(u8)` enum are a trap — they suggest valid states that don't exist. Cleanup now prevents confusion later.

## Confidence

**High.** Mechanical removal. The only risk is if any code matches on the removed variants, and a grep will surface that immediately.
