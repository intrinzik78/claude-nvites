# DISPATCH: Waiver endpoint 404 from command center

**Date:** 2026-03-15
**From:** surface-command-center agent
**To:** server agent
**Priority:** Blocking — the command center waiver review UI is wired and rendering, but the API call fails with 404.

---

## Problem

The command center's WaiverSection calls `GET /v1/bookings/{uuid}/waivers` via Tauri IPC → sdk-rust → server. The server returns **404 Not Found**.

Screenshot evidence: `docs/screenshots/waiver-center.png` — the WaiverSection renders "Waivers 0 of 4" with error text "404 Not Found" below it. The check-in workflow is active and at the "Waivers Complete" gate step for booking "Derek Thompson · 4 guests".

## What we know

### The full call chain

1. `CheckInFlow.svelte` `$effect` calls `waiverVM.load(entity.entityId, entity.headcount)`
2. `waiverList.svelte.ts` calls `getBookingWaivers(uuid)` (Tauri invoke)
3. `src-tauri/src/commands/waivers.rs` calls `client.waivers().get_booking_waivers(&uuid)`
4. `sdk-rust` sends `GET /v1/bookings/{uuid}/waivers`
5. Server handler `booking_waivers_get.rs` calls `Booking::by_uuid(&uuid, db)` → returns `None` → 404

### The UUID is valid for workflows

The same `entity.entityId` (booking UUID) successfully creates and loads workflow instances via `parent_entity_id`. The workflow is active at the "Waivers Complete" step. So the UUID exists in the workflow system.

### The 404 source in server code

`server/api/src/api/waivers/booking_waivers_get.rs`:
```rust
let booking = match Booking::by_uuid(&uuid, db).await {
    Ok(Some(b)) => b,
    Ok(None) => {
        return Error::BookingNotFound.to_http_response();  // ← this fires
    }
    Err(e) => return e.to_http_response(),
};
```

## What we changed (surface-command-center side)

All changes are on the surface/SDK side — no server handler or migration changes.

1. **sdk-rust**: Changed `get_booking_waivers` return type from `Vec<WaiverDto>` to `Vec<StaffWaiverDto>` (the server already returns StaffWaiverDto; the SDK was silently dropping the `id` field)
2. **Tauri command**: Matched the SDK type change
3. **TS types**: Added missing fields to `WaiverDto` (uuid, emergency contact, address, hashes)
4. **Frontend**: New `WaiverReview.svelte` drill-down component, wired `WaiverSection` into `CheckInFlow` and `BookingDetail`

None of these changes affect the server request — the path `GET /v1/bookings/{uuid}/waivers` and the UUID value are unchanged.

## Hypotheses (ranked by confidence)

### 1. `Booking::by_uuid` looks up a different column than what workflow `parent_entity_id` stores (HIGH confidence)

Workflow instances store `parent_entity_id` as the booking identifier. The waiver endpoint uses `Booking::by_uuid()`. If these resolve against different columns (e.g., workflow uses an integer ID cast to string while `by_uuid` looks for a UUID-format column), the lookup would fail.

**To verify:** Check `Booking::by_uuid()` implementation — what column does it query? Compare that to how `parent_entity_id` is populated when a workflow instance is created for a booking. Also check what `BookingDto.uuid` actually contains on the frontend (is it the UUID column value or the integer ID?).

### 2. Server binary doesn't include the waiver route (MEDIUM confidence)

If the running server was compiled before the waiver endpoints were registered in the router, the request would 404 at the routing layer (not at `Booking::by_uuid`). The error format "404 Not Found" could be either a router miss or a handler-level BookingNotFound.

**To verify:** Check the server's route registration — is `booking_waivers_get` mounted? Restart the server with a fresh `cargo xtask build-all` build.

### 3. Seed script created waivers but didn't attach them to the booking via `waiver_collection` / `waiver_document_map` (LOW confidence for the 404 — this would cause empty results, not 404)

This would explain "0 of 4" but not the 404 itself. The 404 fires before the waiver query — it fails at the booking lookup step.

## Proposed investigation

1. **Check `Booking::by_uuid()` implementation** — what column and table does it query?
2. **Check what value `BookingDto.uuid` contains** — is it a UUID-format string or something else?
3. **Check workflow instance creation** — when `createWorkflowInstance` is called with `parentEntityId = booking.uuid`, what value is stored?
4. **Verify the waiver route is registered** in the server's router configuration
5. **Rebuild and restart the server** — `cargo xtask build-all && cargo run` (or however the dev server is started)

## What the command center needs from the server

The `GET /v1/bookings/{uuid}/waivers` endpoint must resolve the same UUID that `BookingDto.uuid` contains on the frontend. Once this works, the full waiver review flow is ready: list → accept → drill-down detail view with participant name, age, minor status, and emergency contact.
