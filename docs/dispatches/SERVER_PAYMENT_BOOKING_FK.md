# Dispatch: Sever payment_transaction → booking FK dependency

**Date:** 2026-03-26
**Workstream:** server

## Problem

`PaymentTransactionDto` in api-contracts still has a `booking_id: i32` field, and the `payment_transaction` DB table has a FK to `booking(id)`. The booking domain has been removed from the codebase but this coupling remains. The server-side `PaymentTransaction::to_held_dto()` method also took `&Booking` as a parameter — that code path is broken after the api crate cleanup.

## Reasoning

- Bookings were stripped in slice 3 (api-contracts) but payment code was kept
- `HeldPaymentDto` already had its booking context fields removed (slice 2, option c)
- `PaymentTransactionDto.booking_id` is the last remaining contract-level reference
- The DB FK means `booking` table cannot be dropped without a migration
- See `TABLES_TO_REMOVE.md` in monorepo root for full orphaned table list

## Proposed Solution

1. Remove `booking_id` from `PaymentTransactionDto` in api-contracts, or make it `Option<i32>` if existing rows need to serialize
2. Write a migration: `ALTER TABLE payment_transaction DROP FOREIGN KEY fk_pt_booking`
3. Optionally make `booking_id` nullable in the DB (`ALTER TABLE payment_transaction MODIFY booking_id INT NULL`)
4. Update `to_held_dto()` in the api crate to stop requiring `&Booking`

## Confidence

**High** — the approach is straightforward, just needs to happen during the api crate surgery (slice 5)
