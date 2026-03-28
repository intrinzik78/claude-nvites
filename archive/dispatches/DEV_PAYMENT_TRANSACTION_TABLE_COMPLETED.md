# Dispatch: Restore and adapt payment_transaction table for nvites.me

**Date:** 2026-03-28
**Workstream:** dev

## Problem

The `payment_transaction` table was dropped in the schema baseline rewrite (94b9b59) because it belonged to the old UWZ booking system. However, the full Authorize.Net payment processing stack still exists in code and references this table:

- **Server type:** `PaymentTransaction` with `#[derive(FromRow)]` helper (`server/api/src/types/payments/payment_transaction.rs:102-122`) — this struct IS the de facto table definition
- **Handlers:** `HeldPaymentsGet`, `PaymentApprovePost`, `PaymentDeclinePost` — fraud review workflow
- **Domain logic:** CAS status updates (DEC-099), void/refund reversal with row-level locking, webhook reconciliation
- **Contract types:** `TransactionType`, `TransactionStatus`, `PaymentTransactionDto`, `HeldPaymentDto`, `PaymentSummaryDto` in api-contracts
- **Schema-emitter:** 4 type registrations for OpenAPI
- **sdk-ts:** Generated types + wrapper methods (`getHeldPayments`, `approvePayment`, `declinePayment`)

All of this compiles but would fail at runtime — the table doesn't exist in any migration.

## The booking_id problem

The entire payment stack is anchored on `booking_id: i32` as the foreign key:

- `PaymentTransaction.booking_id` field
- `by_booking_id()`, `by_booking_id_for_update()` queries
- `reverse_for_booking()` — void/refund logic keyed on booking
- `INSERT INTO payment_transaction (booking_id, ...)` in all write paths

Bookings don't exist in nvites.me. The payment system will serve client subscriptions, which means `booking_id` needs to become something else — but that "something else" depends on the subscription model, which hasn't been designed yet.

## Suggested solutions

1. **Adapt when subscription model is designed** — the cleanest option. When the subscription domain is built, define the payment anchor (e.g., `subscription_id`, `account_id`, or `person_id`) and adapt the table + code in one pass. Until then, the code compiles and the handlers are registered but inert.

2. **Restore table now with generic anchor** — add the migration with a generic `reference_id` + `reference_type` polymorphic pattern. Keeps the table live for testing. Risk: premature abstraction that may not fit the actual subscription model.

3. **Restore table as-is with booking_id** — exact DDL from the old schema. Keeps code runnable against the DB. Risk: `booking_id` references nothing and creates confusion about what it means.

## Minor side item

`SmsSubscriptionStatus` and `EmailSubscriptionStatus` enums are genuinely dead — no table, no domain, no plan. Two files + two error variants + two mod.rs re-exports. Trivial removal whenever convenient.

## Confidence

**High** on the problem. **Medium** on solution — leans toward option 1 (wait for subscription model) since the code is safe to leave as-is until then.
