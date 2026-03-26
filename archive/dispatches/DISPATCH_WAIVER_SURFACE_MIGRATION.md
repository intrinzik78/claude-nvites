# DISPATCH: Waiver Surface Migration (UUID Consumer Identifiers)

**Date:** 2026-03-15
**Target:** surface-website branch (covers both website and command-center)
**Depends on:** Consumer waiver identifiers → UUID only (DEC-128), SDK waiver wrappers commit

---

## Before implementing

The surface-website agent may have already addressed these issues as part of the discrete waiver flow build. Before making any changes:

1. Run `pnpm run check` in the surface to see if TypeScript reports errors on the files listed below
2. If the files have already been rewritten or deleted, archive this dispatch — it's already resolved
3. Only implement the migration guide below for files that still reference the old shapes

## Problem

Server contract changes removed `id` from `WaiverDto` and renamed `waiver_ids` → `waiver_uuids` on `AttachWaiverToBookingBody`. The SDK was updated (dead wrappers removed, discrete flow wrappers added), but surface code still references the old shapes. TypeScript compile errors will guide the migration.

## Affected files

### surface-website (6 breakages)

**`src/routes/(public)/waiver/_components/WaiverFlow.svelte`**
- L84: `{#each signedWaivers as waiver (waiver.id)}` — key binding uses removed field
- L151: `{#each signedWaivers as waiver (waiver.id)}` — same
- L152: `<input type="hidden" name="waiver_id" value={waiver.id} />` — form value uses removed field

**`src/routes/portal/waivers/_components/WaiverAttachForm.svelte`**
- L56: `value={waiver.id}` — form input uses removed field

**`src/routes/(public)/waiver/+page.server.ts`**
- L90-91, L100-101: Calls `api.createWaiver()` / `api.createChildWaiver()` — methods removed from SDK
- L138: `formData.getAll('waiver_id').map((v) => Number(v))` — reads old form field name
- L150: `await api.attachWaiversToBooking({ booking_uuid, waiver_ids })` — uses old field name

**`src/routes/portal/waivers/+page.server.ts`**
- L27: `formData.getAll('waiver_id').map((v) => Number(v))` — reads old form field name
- L39: `await api.attachWaiversToBooking({ booking_uuid, waiver_ids })` — uses old field name

### surface-command-center (3 breakages)

**`src/lib/components/WaiverSection.svelte`**
- L45: `{#each vm.waivers as waiver (waiver.id)}` — key binding. Staff endpoint now returns `StaffWaiverDto` which HAS `id`, but the TypeScript type used here is likely `WaiverDto` (wrong type for staff context).
- L63: `onclick={() => vm.acceptWaiver(waiver.id)}` — passes id to accept flow

**`src/lib/components/waiverList.svelte.ts`**
- L72: `pendingWaivers.map((w) => w.id)` — maps waiver ids for accept body

## Migration guide

### WaiverDto → uuid keying (website)
- Replace `waiver.id` with `waiver.uuid` in all Svelte `{#each}` key expressions
- Replace `<input name="waiver_id" value={waiver.id}>` with `<input name="waiver_uuid" value={waiver.uuid}>`
- In server actions: `formData.getAll('waiver_uuid')` returns strings (no Number() cast needed)
- `api.attachWaiversToBooking({ booking_uuid, waiver_uuids })` — field is `waiver_uuids: string[]`

### Dead API calls → discrete flow (website)
- Replace `api.createWaiver(body)` with the 4-step discrete flow:
  1. `api.beginWaiver(body)` → returns `WaiverDto`
  2. `api.consentWaiver(uuid)` → void
  3. `api.confirmWaiver(uuid)` → void
  4. `api.signWaiver(uuid, { signature_data })` → returns `WaiverDto`
- `BeginWaiverBody` uses `document_uuid` (not `document_id`)

### StaffWaiverDto (command-center)
- Staff endpoints (`GET /v1/bookings/{uuid}/waivers`) now return `StaffWaiverDto` which includes `id`
- Import `StaffWaiverDto` instead of `WaiverDto` for staff contexts
- `waiver.id` access is valid on `StaffWaiverDto` — just need the correct type
- `AcceptWaiversBody.waiver_ids` is unchanged (staff path, integer IDs are fine per DEC-128)

## NOT changed
- `AcceptWaiversBody` — still uses `waiver_ids: Vec<i32>`, staff gets `id` from `StaffWaiverDto`
- `WaiverAuditTrailDto` — still uses `waiver_id: i32`, staff-only
- Audit endpoint path still uses integer `waiver_id` in URL — staff path, fine
