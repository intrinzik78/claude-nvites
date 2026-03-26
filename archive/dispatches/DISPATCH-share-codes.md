# Dispatch: Booking Share Codes

**From:** surface-website
**To:** server
**Date:** 2026-03-11
**Priority:** Required for website waiver flow (not yet blocking — website can build around the portal UUID link flow first)

## Problem

The booking UUID is 16-char mixed-case alphanumeric — great for links and QR codes, unusable for verbal/manual sharing. When a guest shows up at the facility without the booking link, staff currently has no way to give them a human-speakable code to attach their waiver.

**Concrete scenario:** Wife books a birthday party, gets the link, shares it with friends. Dad shows up day-of with extra kids. One guest hasn't done the waiver. Dad doesn't have the link. Staff needs to hand the guest a code they can type into their phone.

## Proposed Feature: Ephemeral Share Codes

### Format
`XXX-XXX` — 6 characters from `[0-9A-Z]`, dash-separated. 36⁶ = ~2.18 billion permutations. With ~1-2 dozen active codes at any given time, collision is effectively impossible.

### Generation
- **Idempotent.** If an active code exists for the booking, return it. If not, generate one.
- **Two callers:** Staff (from command center) and booking owner (from portal). Same endpoint, same behavior. Auth determines who can call — booking owner can only generate for their own bookings.
- Enforce uniqueness among active codes. Retry on collision (astronomically unlikely but handle it).

### Lifecycle
- Tied to booking date — expires end of event day (midnight local).
- **Proactive deletion** of expired codes. Cron, TTL, or cleanup on generation — whatever fits the existing background job pattern. Don't let expired codes accumulate.
- If a code expires (e.g., customer no-shows, reschedules), a new one can be generated. Old code is dead.
- One active code per booking at a time.

### Endpoints Needed

| Method | Path | Auth | Purpose |
|---|---|---|---|
| POST | `/v1/bookings/{uuid}/share-code` | booking owner OR staff | Generate or return active share code |
| GET | `/v1/share-code/{code}` | any authenticated user | Resolve share code → booking UUID |

The resolve endpoint is what the website calls. Guest enters `XXX-XXX`, website calls resolve, gets back the booking UUID, then uses the existing `attachWaiversToBooking` flow unchanged.

### Database
The original schema had a `waiver_share_code` table that was dropped in `20260225000000_waiver_schema_alignment.sql`. This feature brings back the concept. Minimal schema:
- `booking_id` (FK)
- `code` (unique index, the XXX-XXX value stored without dash)
- `expires_at` (datetime)
- `created_by` (FK → user, for audit)
- `created_at`

### SDK
After endpoints are built, SDK needs:
- `generateShareCode(bookingUuid: string)` wrapper
- `resolveShareCode(code: string)` wrapper
- Type exports for request/response shapes

## Getting Up to Speed
- `archive/waiver-workflow.md` — original design doc describing the share code concept
- `server/migrations/20260225000000_waiver_schema_alignment.sql` — where `waiver_share_code` was dropped
- `server/api/src/api/portal/portal_waivers_attach_post.rs` — existing attach flow (share code feeds into this)
- `docs/DECISIONS.md` — DEC-085, DEC-108 for waiver design context

## Resolved Decisions
- **Resolve response shape:** Return booking UUID + **date, time, and booking owner's last name only**. No headcount (privacy), no product (irrelevant, potentially embarrassing). The website will display something like "Doe party — 2:00 PM, Wednesday, January 15th" so the guest can confirm they're in the right place.

## Open Questions
1. **Resolve endpoint auth level:** Should resolving a share code require authentication, or should it be public? The code itself is ephemeral and low-entropy by design — but the guest needs to be authenticated anyway to sign a waiver. Leaning toward authenticated (any role).
2. **Rate limiting on resolve:** The code space is huge, but the endpoint should still be rate-limited to prevent brute-force enumeration. Existing rate limiter should cover this — just flagging.
