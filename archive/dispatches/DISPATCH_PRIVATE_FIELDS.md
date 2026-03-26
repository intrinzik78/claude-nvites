# PaymentTransaction: Private Fields + Getters

**Date:** 2026-03-24
**Workstream:** server
**Priority:** Low — no current exploit, but drift toward invariant breakage

## Problem

`PaymentTransaction` has all-public fields (`pub id`, `pub booking_id`, `pub anet_transaction_id`, etc.). This was fine when it was a pure data record with SQL methods and DTO conversions. Slice 4 added `reverse_for_booking()` — business logic that depends on field invariants:

- `anet_transaction_id` must be `Some(...)` on Approved AuthCapture rows (used as the void/refund target)
- `last_four` must be `Some(...)` for refund fallback
- `transaction_type` and `status` combinations drive the idempotency guard

The struct is currently only constructed via `PaymentTransactionHelper::transform()` from DB rows, so invariants hold today. But nothing prevents external code from constructing or mutating a `PaymentTransaction` directly — the type system doesn't enforce the contract.

## Proposed Solution

Follow the `Booking` pattern already established in the codebase:

1. Make all fields on `PaymentTransaction` private
2. Add getter methods: `id()`, `booking_id()`, `anet_transaction_id()`, `transaction_type()`, `status()`, `last_four()`, `total_cents()`, etc.
3. Update `reverse_for_booking`, `record_reversal_in`, `to_summary_dto`, `to_dto`, and any other internal access to use getters
4. The `PaymentTransactionHelper::transform()` constructor remains the only way to build a valid instance

## Scope

- `server/api/src/types/payments/payment_transaction.rs` — primary change
- `server/api/src/types/bookings/charge.rs` — accesses fields on `PaymentTransaction` (from `settle_approved` return)
- `server/api/src/api/bookings/bookings_post.rs` — accesses `transaction.to_summary_dto()` (already a method, may not need changes)
- Integration tests that construct or read `PaymentTransaction` fields directly

## Confidence

High. The pattern is well-established (`Booking`, `Product`, `QueueEntry` all use private fields + getters). The risk is purely mechanical — find all field accesses, convert to getters. No behavioral change.
