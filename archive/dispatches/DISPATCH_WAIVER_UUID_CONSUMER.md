# DISPATCH: Consumer-Facing Waiver Identifiers → UUID Only

**Date:** 2026-03-14
**Target:** server branch
**Severity:** Design debt — functional but violates DEC-128

---

## Problem

Consumer-facing waiver flows expose integer IDs (`waiver.id`) to portal users. `WaiverDto` returns both `id: i32` and `uuid: String`. The `AttachWaiverToBookingBody` accepts `waiver_ids: Vec<i32>`. Per DEC-128, consumer paths should use non-guessable UUIDs exclusively — integer IDs are for staff paths only.

## What needs to change

### 1. WaiverDto — stop exposing `id` to consumers

The portal returns `WaiverDto` from begin, sign, and list endpoints. Consumers receive and store the integer ID, then pass it back to the attach endpoint. Options:

- **Option A:** Remove `id` from `WaiverDto` entirely. Staff endpoints that need it can use a separate `StaffWaiverDto`.
- **Option B:** Keep `id` on `WaiverDto` but gate it with `#[serde(skip_serializing_if)]` based on context. Harder to implement cleanly.

Option A is cleaner. Staff endpoints already have access to the `Waiver` domain type — a dedicated `StaffWaiverDto` (or reuse of the existing internal type) avoids leaking internal IDs to consumers.

### 2. AttachWaiverToBookingBody — accept UUIDs

Change `waiver_ids: Vec<i32>` to `waiver_uuids: Vec<String>`. The handler resolves UUIDs to IDs internally via `Waiver::find_by_uuids_and_signer()` (new method, mirrors existing `find_by_ids_and_signer` but queries by UUID).

### 3. AcceptWaiversBody — evaluate

`AcceptWaiversBody` also uses `waiver_ids: Vec<i32>`, but it's a staff-only endpoint (`/bookings/{uuid}/waivers/accept`). Per DEC-128, staff paths may use integer IDs. This one is fine as-is.

## Contract impact

- `WaiverDto` field removal/rename — **breaking contract change**
- `AttachWaiverToBookingBody` field rename — **breaking contract change**
- SDK regeneration + hand-written wrapper updates required
- Surface code must switch from `waiver.id` to `waiver.uuid`

## Scope boundary

- This dispatch covers the server + api-contracts changes only
- Surface updates (website, command center) are follow-on work
- The existing `id` field on `WaiverDto` for staff contexts is a separate design decision
