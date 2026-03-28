# Dispatch: Clean up stale UWZ enums and payment handlers

**Date:** 2026-03-27
**Workstream:** dev

## Problem

Several enums and handlers reference removed domains and are dead code:

**Enums (server/api/src/enums/):**
- `SmsSubscriptionStatus` — SMS domain removed
- `EmailSubscriptionStatus` — email subscription domain removed
- `TransactionStatus` — payment_transaction table removed
- `TransactionType` — payment_transaction table removed

**Handlers (server/api/src/api/payments/):**
- `HeldPaymentsGet`, `PaymentApprovePost`, `PaymentDeclinePost` — reference payment_transaction table which no longer exists in the schema

**Route collection:**
- `RouteCollection::payments()` registers routes for the dead payment handlers
- Sentinel counts will need updating after removal

These compile because the types are still declared and re-exported in `mod.rs` even though nothing exercises them at runtime.

## Proposed Solution

Remove the dead enums, handlers, route registrations, and mod.rs re-exports. Update sentinel counts. Compiler will guide what else needs cleanup.

## Confidence

**High** — pure dead code removal, compiler-guided
