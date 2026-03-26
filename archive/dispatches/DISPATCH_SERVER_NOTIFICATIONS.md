# Payment Lifecycle Email Notifications

**Date:** 2026-03-24
**Workstream:** server
**Recipient:** server agent

## Problem

The payment integration (slices 1–5) handles charge, void, refund, held-for-review, fraud approve, and fraud decline — but the only email the customer ever receives is the booking confirmation on successful charge. Every other payment lifecycle event is silent to the customer.

Scenarios where the customer gets no notification:

1. **Fraud decline** — booking cancelled after held-for-review is declined. Customer may have planned around this booking. No email.
2. **Void** — staff cancels a same-day booking, charge is voided. Customer sees money return but gets no explanation email.
3. **Refund** — staff cancels a settled booking, refund issued. Same gap.
4. **Held-for-review approval** — this one IS covered (webhook sends confirmation email via `BookingsPost::send_confirmation`). But only because it piggybacks on the existing confirmation template.
5. **Portal cancellation with refund** — customer self-cancels, void/refund fires. No receipt or confirmation of the refund amount.

## Scope

This is an email template + handler wiring task. The server-side hooks already exist:
- `handle_fraud_declined` in `api/webhooks/authorizenet_post.rs` — log only, needs email
- `portal_cancel.rs` and `bookings_status_patch.rs` — call `reverse_for_booking` but send no email about the reversal
- `handle_void` and `handle_refund` webhook handlers — log only, could trigger confirmation emails

## Approach

1. Design email templates for each event (likely 2–3 templates, not one per event):
   - **Booking cancelled + refund/void** — covers staff cancel, portal cancel, fraud decline
   - **Refund processed** — standalone refund confirmation with amount
   - Possibly: **Booking under review** — sent at charge time when HeldForReview (currently no email at all during the review period)

2. Wire the templates into the existing handler paths using the fire-and-forget `actix_web::rt::spawn` pattern.

3. The `email-template` crate already has `BookingConfirmationEmail` as the pattern to follow.

## Dependencies

- `email-template` crate for new templates
- `postmark` crate for sending
- Email copy needs owner review before shipping
