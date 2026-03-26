# Full Payment Surface Security Audit

**Date:** 2026-03-24
**Workstream:** server
**Recipient:** server agent

## Scope

Run `/security` across the entire payment surface as the final gate before the payment feature goes live. Per-slice reviews caught slice-specific issues, but this audit covers cross-cutting concerns and the full attack surface.

## Files to Audit

### authorizenet crate
- `server/authorizenet/src/types/client.rs` — credential handling, request construction, timeout bounds
- `server/authorizenet/src/types/webhook.rs` — HMAC-SHA512 verification, constant-time comparison
- `server/authorizenet/src/types/request.rs` — request serialization, nonce handling
- `server/authorizenet/src/types/response.rs` — response parsing, error extraction
- `server/authorizenet/src/types/env.rs` — env var loading, credential storage
- `server/authorizenet/src/enums/error.rs` — error leakage in Display impl

### Payment types
- `server/api/src/types/payments/payment_transaction.rs` — SQL injection surface, FOR UPDATE patterns, raw_response PCI handling

### Booking charge flow
- `server/api/src/types/bookings/charge.rs` — charge orchestration, crash safety
- `server/api/src/api/bookings/bookings_post.rs` — nonce validation, payment gating, error leakage

### Void/refund flow
- `server/api/src/api/bookings/bookings_status_patch.rs` — staff cancellation with payment reversal
- `server/api/src/api/portal/portal_cancel.rs` — portal cancellation with payment reversal (if exists)

### Webhook handler
- `server/api/src/api/webhooks/authorizenet_post.rs` — already audited in slice 5, but re-check in full context

### Slice 6 (when shipped)
- `server/api/src/api/payments/` — held transaction approve/decline, payment history endpoints

## Focus Areas

1. **Credential handling** — are API keys, transaction keys, signature keys ever logged or exposed in error responses?
2. **PCI surface** — `raw_response` column contains full gateway JSON. Verify it never appears in API responses or logs beyond CRITICAL paths.
3. **Nonce validation** — Accept.js nonces are single-use. Can a replay attack reuse a nonce?
4. **Race conditions** — charge + concurrent cancel, webhook + concurrent void, double-submit booking
5. **Error leakage** — do payment errors expose gateway internals to the client?
6. **Rate limiting** — are expensive paths (gateway calls) adequately rate-limited?
7. **Input validation** — payment amounts, addon quantities, guest counts — can any be manipulated to cause unexpected charges?

## Timing

Run this audit after slice 6 ships and before the `payment_service` flag is set to `Enabled` in production.
