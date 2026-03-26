# Dispatch: Waiver SDK + OpenAPI Gaps

**From:** surface-website
**To:** server
**Date:** 2026-03-11
**Priority:** Blocking (command center waiver UI depends on these)

## Situation

Building the customer waiver flow on surface-website. Portal SDK (customer-facing) is complete and unblocked. However, the **staff-facing waiver endpoints** have gaps that will block the command center from viewing/accepting waivers.

## Issues

### 1. OpenAPI spec bug — `getBookingWaivers` has no response schema

`GET /v1/bookings/{uuid}/waivers` returns 200 with `"description": "ok"` but **no content/schema**. The generated types show `content?: never`. The handler presumably returns `WaiverDto[]` or `WaiverCollectionSummaryDto` — the spec just doesn't declare it.

**Fix:** Add the response schema to the path annotation in `api-contracts/src/paths/waivers.rs`, then `cargo xtask build-all`.

**Confidence:** High — this is a straightforward annotation fix. The handler likely already returns the right data.

### 2. Three missing SDK wrappers in `sdk-ts/src/api/bookings.ts`

| Endpoint | Wrapper needed |
|---|---|
| `GET /v1/bookings/{uuid}/waivers` | `getBookingWaivers(uuid: string)` |
| `POST /v1/bookings/{uuid}/waivers/accept` | `acceptBookingWaivers(uuid: string, body: AcceptWaiversBody)` |
| `POST /v1/bookings/{uuid}/waivers/paper` | `recordPaperWaiver(uuid: string, body: RecordPaperWaiverBody)` |

**Fix:** Hand-written wrappers in `sdk-ts/src/api/bookings.ts` + barrel exports. Follow existing patterns in that file.

**Confidence:** High — mechanical work, same pattern as every other SDK wrapper.

### 3. Missing type exports from `sdk-ts/src/types/index.ts`

These exist in `generated.d.ts` but aren't re-exported:
- `AcceptWaiversBody`
- `RecordPaperWaiverBody`
- `WaiverCollectionSummaryDto`
- `WaiverCollectionStatus`
- `WaiverStatus`
- `SignerSummary`

## Getting Up to Speed

- `api-contracts/src/waivers.rs` — all waiver DTOs and request bodies
- `api-contracts/src/paths/waivers.rs` — OpenAPI path annotations (the spec bug lives here)
- `server/api/src/api/waivers/` — staff handler implementations
- `server/api/src/api/portal/portal_waivers_*.rs` — portal handlers (working, for reference)
- `sdk-ts/src/api/portal.ts` — working waiver wrappers (pattern to follow)
- `docs/DECISIONS.md` — DEC-075, 077, 079, 080, 085, 108 cover waiver decisions

## Open Question — Booking UUID Format

The original design doc (`archive/waiver-workflow.md`) specified `XXX-XXX` (3 uppercase + 3 digits, dash-separated) for human-friendly manual entry. The server generates 16-char `[A-Za-z0-9]{16}` with no dash. The `AttachWaiverToBookingBody` doc comment still says "XXX-XXX format" — stale.

This is a **UX decision, not a server bug** — the 16-char UUID works fine for QR/link flows but is impractical for manual entry. Flagging for awareness; surface-website will design around whatever format exists. If a short code is desired, that's a separate server feature.

## Order of Operations

1. Fix OpenAPI spec annotation (contract change — justify: completing an incomplete annotation, not changing behavior)
2. `cargo xtask build-all` to regenerate `dist/openapi.json`
3. Add SDK wrappers + type exports
4. `cd sdk-ts && npm run check && npm run test`
