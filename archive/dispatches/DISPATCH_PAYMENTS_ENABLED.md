# Server: Expose payment_service status to surfaces

**Date:** 2026-03-24
**Workstream:** server
**Requested by:** surface-website (payment integration session)

## Problem

The website needs to know whether `payment_service` is `Enabled` before the user submits. Currently there is no API endpoint or response field that exposes this. The website uses the presence of Authorize.Net env vars as a proxy — if credentials are configured, the payment form renders.

This creates a config sync risk: if `payment_service` is toggled to `Disabled` on the server but the website env vars remain set, the payment form still renders. The user fills out card details, tokenizes successfully (client-side to Authorize.Net), but the server ignores the nonce and creates a booking without payment. The customer sees a confirmation with no charge — confusing and operationally wrong.

The reverse is also a problem: if `payment_service` is `Enabled` on the server but the website env vars aren't set, no payment form renders and the server returns 7004 (nonce required) on submission.

## Request

Add a `payment_required: bool` field to `BookingPreviewDto`. The preview endpoint already queries system settings to compute tax. Adding the payment flag is a single field addition.

## Proposed Solution

In the `POST /v1/bookings/preview` handler:

1. Read `payment_service` from `AppState.settings` (already loaded at boot)
2. Add `payment_required: bool` to `BookingPreviewDto`
3. Set `payment_required = payment_service == PaymentServiceStatus::Enabled`

On the website side (follow-up, not part of this dispatch):
- Read `preview.payment_required` in the ViewModel
- Show/hide the payment form based on the server's actual state instead of env var presence
- Keep the env var check as a secondary gate (can't tokenize without credentials even if server says payment is required)

## Contract Impact

This adds a required field to `BookingPreviewDto`. It's additive — existing consumers receive a new field they can ignore. The `api-contracts` crate and OpenAPI schema need updating. Run `cargo xtask build-all` after the change.

**Confidence: high** — single bool field, data already available in AppState, no new queries.

## Why Not an Alternative

| Alternative | Problem |
|------------|---------|
| Dedicated `GET /v1/settings/payment` endpoint | New endpoint for a single bool. Overkill. Also requires a new SDK wrapper + BFF endpoint on every surface. |
| Include in `GET /v1/products` response | Products are a list — the flag applies globally, not per-product. Bolting it onto ProductDto is semantically wrong. |
| Env var sync (status quo) | Two independent config sources that can drift. The whole point is eliminating this. |
| Include in booking response (422 code 7004) | Too late — the user already filled out card details or didn't see a form. Need to know before submission. |

## Verification

1. `POST /v1/bookings/preview` with `payment_service = Enabled` → response includes `payment_required: true`
2. `POST /v1/bookings/preview` with `payment_service = Disabled` → response includes `payment_required: false`
3. `cargo xtask build-all` passes
4. Existing preview consumers (website, command center) unaffected by new field
