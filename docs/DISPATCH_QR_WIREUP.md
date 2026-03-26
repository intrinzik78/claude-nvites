# Dispatch: QR Code Wireup — Booking Confirmation Artifact

**Date:** 2026-03-26
**Workstream:** crosscutting (server + surface-website)

## Problem

The `qr-frame` crate is built and wired into AppState, but nothing generates or serves QR codes yet. After booking, the QR code is the primary artifact guests need — they share it, scan it for check-in, and save it. Currently the booking confirmation (both website step 5 and the email) shows text details but no QR image.

## Surfaces

### 1. Server: QR generation endpoint

Add a GET endpoint that generates a branded QR PNG on demand:

```
GET /v1/bookings/{uuid}/qr
```

- Reads the booking UUID from the path
- Encodes a URL pointing to the booking (e.g., `{SITE_URL}/portal/booking/{uuid}` or the waiver/check-in flow)
- Calls `AppState::qr_generator().generate_png(url)` inside `tokio::task::spawn_blocking()` (image composition is CPU-bound)
- Returns `image/png` with appropriate cache headers
- If `qr_generator` is `None`, return 503
- Public (no auth) — the UUID is the secret, same as share codes

**URL:** `{SITE_URL}/invite/{uuid}` — a dedicated party invite page. Shows date, time, location, what to expect, and CTA to sign the waiver. The booker shares this QR with their group; each guest scans it to get party details and complete their waiver. This page does not exist yet — it's a new surface-website route built for the scan-and-act flow.

### 2. Booking confirmation email

The booking confirmation email template (`server/email-template/src/types/receipts/booking_confirmation.rs`) should include the QR code as an inline image or a link to the QR endpoint. Options:

- **Inline CID attachment** — QR renders server-side, attached as a `cid:` image in the MJML. Works offline, no external fetch. Adds ~5-15KB to email payload.
- **Hosted image URL** — `<img src="{SITE_URL}/v1/bookings/{uuid}/qr">` in the template. Lighter email, but requires fetch on open and may be blocked by email clients.

**Decision: CID inline attachment.** The QR is the core artifact — it must work without network access.

### 3. Website booking confirmation (step 5)

`BookingConfirm.svelte` should display the QR code prominently after successful booking. Options:

- Fetch from the QR endpoint (`/v1/bookings/{uuid}/qr`) and render as `<img>`
- Generate client-side using a JS QR library (no server round-trip, but no brand frame)

Recommendation: Fetch from server endpoint. The brand frame is the differentiator — a plain QR code loses the "PARTY LINK" branding. The endpoint already exists from item 1.

The QR should be:
- Visually prominent — this is what the guest saves/screenshots
- Downloadable — "Save QR Code" button
- Shareable — native share API on mobile if available

## Dependencies

- `qr-frame` crate: done, wired into AppState
- Brand frame asset: done (`server/qr-frame/src/assets/frame.png`)
- Booking UUID: already exists on `BookingDto`
- Email templates: confirmation email exists, needs QR addition

## Confidence

**High** on endpoint + website display (mechanical).
**Medium** on email CID attachment — need to verify Postmark's API supports inline attachments and the MJML template can reference them.
