# SLICE 03: Command Center Types + Queue Create Email

**Date:** 2026-03-16
**From:** dev design session
**To:** surface-command-center worktree
**Prerequisite:** SLICE 02 integrated into dev. All worktrees at dev.

---

## Goal

Update the command center's type definitions to match the server changes from SLICE 01+02, and wire the optional email field through queue entry creation. After this slice, the command center compiles and works — the WalkUpTrack still shows queue entries (unchanged), but the types are ready for the SLICE 04 refactor.

## Reference

- `docs/FEASIBILITY_WALKUP_BOOKING_CONVERGENCE.md` — Section 6a–6b
- SLICE 01 server changes: BookingSource enum, BookingDto.booking_source, BookingDto.guest_email nullable
- SLICE 02 server changes: QueueEntryDto.email, QueueEntryDto.booking_id, CreateQueueEntryBody.email

## Tasks

### 1. Verify sdk-rust compiles

The Tauri backend depends on `uwz_rust_sdk` which depends on `api-contracts`. Since api-contracts changed (BookingSource, QueueEntryDto fields), verify:

```
cd sdk-rust && cargo check
```

If sdk-rust re-exports api-contracts types directly, this should just work. If it has hand-written wrappers that need updating, fix them.

### 2. Update Svelte types

**File:** `src/lib/types.ts`

Update `BookingDto`:
```typescript
export type BookingSource = 'booking' | 'queue';

export interface BookingDto {
	uuid: string;
	product_id: number;
	guest_name: string;
	guest_email: string | null;     // changed: was string
	guest_phone: string | null;
	guest_count: number;
	status: BookingStatus;
	booking_source: BookingSource;  // new
	start_at: string;
	end_at: string;
	price_cents: number;
	created_at: string;
}
```

Update `QueueEntryDto`:
```typescript
export interface QueueEntryDto {
	id: number;
	name: string;
	contact: string;
	email: string | null;           // new
	party_size: number;
	priority_tier: PriorityTier;
	status: QueueEntryStatus;
	product_id: number | null;
	headcount: number | null;
	booking_id: number | null;      // new
	date: string;
	notes: string | null;
	expected_at: string | null;
	arrived_at: string | null;
	created_at: string;
	updated_at: string;
}
```

### 3. Update Tauri command: create_queue_entry

**File:** `src-tauri/src/commands/queue.rs`

The `create_queue_entry` command needs to accept and pass the optional `email` parameter:
- Add `email: Option<String>` parameter to the function signature
- Include it in the `CreateQueueEntryBody` construction

The Tauri command registration in `lib.rs` does not need to change (parameters are auto-extracted).

### 4. Update Svelte command: createQueueEntry

**File:** `src/lib/api/commands.ts`

Add `email` parameter:
```typescript
export function createQueueEntry(
	name: string,
	contact: string,
	partySize: number,
	date: string,
	notes?: string,
	expectedAt?: string,
	email?: string           // new
): Promise<QueueEntryDto> {
	return invoke<QueueEntryDto>('create_queue_entry', {
		name, contact, partySize, date, notes, expectedAt, email
	});
}
```

### 5. QueueCreateModal: add email input

**File:** `src/lib/components/QueueCreateModal.svelte`

Add an optional email input field to the modal. Staff can enter guest email when creating a walk-up queue entry. Field is optional — if left blank, `email` is undefined/null.

Position the email field near the contact field (they're related). Label: "Email (optional)". Standard text input with email type for browser validation hints.

### 6. Fix any guest_email consumers

Search for references to `guest_email` or `.guest_email` in Svelte components. Since `BookingDto.guest_email` is now `string | null`, any display code that assumes it's a string needs a null check. Likely affected:
- `BookingDetail.svelte` — if it displays guest_email
- `BookingList.svelte` — if it shows email in the list

Use `booking.guest_email ?? '—'` or conditional rendering. Don't overcomplicate it — all existing bookings have email populated.

### 7. Build and verify

```
cd src-tauri && cargo check
```

And from the surface-command-center root:
```
npm run check
```

Both must pass. The app should function identically to before — no behavioral changes, just type alignment.

## What NOT to do

- Do not refactor WalkUpTrack — that's SLICE 04.
- Do not change the activation flow in the UI — server already creates the booking.
- Do not change the instance viewmodel — that's SLICE 04.
- Do not add booking_source filtering or display — that's SLICE 04.

## Done criteria

- `sdk-rust` compiles (`cargo check`)
- Tauri backend compiles (`cargo check` in src-tauri)
- Svelte type check passes (`npm run check`)
- QueueCreateModal has optional email field
- `createQueueEntry` passes email to Tauri backend
- BookingDto and QueueEntryDto types match server contract
- App runs and behaves identically (no visual changes)
