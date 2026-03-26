# DISPATCH: Child Waiver Discrete Flow

**Date:** 2026-03-15
**Target:** server branch
**Depends on:** Discrete adult flow (shipped 2026-03-15)

---

## Problem

The old `POST /v1/portal/waivers/child` endpoint was removed during the waiver audit trail refactor. There is currently no API path for a parent/guardian to sign a waiver on behalf of a minor through the portal. The only path for minors is paper waivers via staff (`POST /v1/bookings/{uuid}/waivers/paper`).

## What needs to happen

Build `POST /v1/portal/waivers/child/begin` following the same 4-step discrete pattern as the adult flow:

| Step | Endpoint | Notes |
|------|----------|-------|
| 1. Begin | `POST /v1/portal/waivers/child/begin` | `BeginChildWaiverBody`: adds `participant_dob` (required), `guardian_relationship` (required). `is_minor = true`. |
| 2. Consent | `POST /v1/portal/waivers/{uuid}/consent` | Same endpoint as adult — consent is signer-level, not participant-level |
| 3. Confirm | `POST /v1/portal/waivers/{uuid}/confirm` | Same endpoint as adult |
| 4. Sign | `POST /v1/portal/waivers/{uuid}/sign` | Same endpoint as adult — guardian signs on behalf of minor |

The consent/confirm/sign steps reuse the existing adult endpoints since they operate on the waiver UUID regardless of `is_minor`. Only the begin step needs a new endpoint and DTO.

## Validation at begin

- `participant_dob` required and must indicate a minor (age < 18) — reuse existing `validate_minor_dob()`
- `guardian_relationship` required — `parent` or `legal_guardian`
- Address + emergency contact same as adult begin

## Scope boundary

- Age-out sweeper (minor turns 18, waiver needs re-evaluation) is a separate concern — do not build here
- Booking-time age gate (verify age at check-in) is a separate concern — do not build here
