# Dispatch: Addon & Product Validation Consolidation

**Date:** 2026-03-23
**Workstream:** server

## Problem

Addon and product validation logic is duplicated across three handler paths, each with its own constants and checks:

1. **`addons_post.rs`** — `MAX_ADDON_QUANTITY = 100`, delegates cap check to `BookingAddon::create_for_booking` (`MAX_ADDONS_PER_BOOKING = 20`)
2. **`bookings_preview.rs`** — `MAX_ADDON_QUANTITY = 100`, `MAX_ADDONS = 20` (inline constants with sync comments)
3. **Slice 3 (future)** — `bookings_post.rs` will gain inline addon creation with the same validation

Additionally, `generate_slots()` produces 17 zero-width slots when `duration_minutes = 0`. Product creation may or may not guard against this — unverified.

## Reasoning

- Constants that must stay in sync across files will drift. The sync comments help but don't enforce.
- When Slice 3 adds inline addons to `bookings_post.rs`, a third copy of the validation will exist. Three copies is the threshold where extraction pays for itself.
- The zero-duration product issue is either already guarded at creation time (in which case a comment documenting the invariant is sufficient) or it's a latent bug that produces nonsensical availability slots.

## Proposed Solution

1. **Verify product duration guard.** Check `products_post.rs` (or wherever products are created) for `duration_minutes > 0` validation. If present, add a comment in `generate_slots` referencing the upstream invariant. If absent, add the validation at creation time and a defensive early return in `generate_slots`.

2. **Extract shared addon validation.** Add a method on `BookingAddon` (or a new `validation` submodule in `types/bookings/`) that validates an addon selection list without inserting:
   ```rust
   /// Validates addon selections: product exists, is active Addon type, quantity in bounds, count in bounds.
   /// Returns resolved addons with snapshotted prices. No DB writes.
   pub async fn validate_selections(selections: &[AddonSelection], db: &DatabaseConnection) -> Result<Vec<ValidatedAddon>>
   ```
   This serves both the preview handler (read-only price lookup) and the booking handler (pre-insert validation). The existing `create_for_booking` can call `validate_selections` internally then insert.

3. **Consolidate constants.** Move `MAX_ADDON_QUANTITY` and `MAX_ADDONS_PER_BOOKING` to `BookingAddon` as `pub const` so all consumers reference a single source.

## Confidence

**High** on items 1 and 3 — these are mechanical and low-risk.

**Medium** on item 2 — the extraction is straightforward, but the right API shape depends on Slice 3's exact needs. Recommend resolving this dispatch as part of Slice 3 implementation rather than ahead of it, so the extraction is informed by real usage in `bookings_post.rs`.
