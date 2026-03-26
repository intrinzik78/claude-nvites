# SLICE 04: WalkUpTrack Refactor — Queue-Sourced Bookings

**Date:** 2026-03-16
**From:** dev design session
**To:** surface-command-center worktree
**Prerequisite:** SLICE 03 (types aligned, sdk-rust compiles, email field wired)

---

## Goal

Switch WalkUpTrack from showing active queue entries to showing queue-sourced bookings. After this slice, the booking convergence is complete: activation creates a booking (SLICE 02), and the command center displays it as a booking with full waiver/workflow support (this slice).

## Reference

- `docs/FEASIBILITY_WALKUP_BOOKING_CONVERGENCE.md` — Sections 6c–6g
- Current files to read first:
  - `src/routes/(app)/command-center/_components/WalkUpTrack.svelte`
  - `src/routes/(app)/command-center/_components/BookingsTrack.svelte`
  - `src/routes/(app)/command-center/_components/CommandCenterGrid.svelte`
  - `src/lib/components/commandCenterInstances.svelte.ts`
  - `src/lib/components/queuePanel.svelte.ts`

## Context: The Data Flow Change

**Before (current):**
- `fetchBookingInstances('booking')` → BookingsTrack (all booking workflows)
- `fetchQueueInstances('queue_entry')` → WalkUpTrack (all queue entry workflows)
- QueuePanel shows non-active queue entries

**After (SLICE 02 server change):**
- New activations create workflows with `parent_entity_type='booking'`
- `fetchQueueInstances('queue_entry')` returns nothing for new activations
- All workflows are now `parent_entity_type='booking'`
- WalkUpTrack must get its data from bookings, not queue entries

**After (this slice):**
- One booking fetch by date → split into online (`source='booking'`) and queue (`source='queue'`)
- One instance fetch (`parent_entity_type='booking'`) → instance groups matched to bookings by UUID
- BookingsTrack shows online bookings + their workflow instances
- WalkUpTrack shows queue-sourced bookings + their workflow instances
- QueuePanel shows non-activated queue entries (Waiting, Arrived, Skipped) — unchanged

## Tasks

### 1. Rethink the instance viewmodel

**File:** `src/lib/components/commandCenterInstances.svelte.ts`

Current: Two separate fetches — `fetchBookingInstances('booking')` and `fetchQueueInstances('queue_entry')`.

After SLICE 02, the queue_entry fetch returns nothing for new activations. Replace with a single fetch:

```typescript
async function fetchAllInstances(status: InstanceStatus = 'Active') {
    lastStatus = status;
    const instances = await listWorkflowInstances('booking', undefined, status);
    allInstancesRaw = instances;
    await ensureDefinition(instances);
}
```

Then split into two groups based on a set of known queue-sourced booking UUIDs (provided by the parent component):

```typescript
// The parent passes a Set<string> of queue-sourced booking UUIDs
let queueBookingUuids: Set<string> = $state(new Set());

const bookingInstanceGroups = $derived.by(() => {
    const groups = new Map<string, WorkflowInstanceDto[]>();
    for (const inst of allInstancesRaw) {
        if (inst.status === 'Split') continue;
        if (queueBookingUuids.has(inst.parent_entity_id)) continue; // skip queue-sourced
        const list = groups.get(inst.parent_entity_id) ?? [];
        list.push(inst);
        groups.set(inst.parent_entity_id, list);
    }
    return groups;
});

const queueInstanceGroups = $derived.by(() => {
    const groups = new Map<string, WorkflowInstanceDto[]>();
    for (const inst of allInstancesRaw) {
        if (inst.status === 'Split') continue;
        if (!queueBookingUuids.has(inst.parent_entity_id)) continue; // only queue-sourced
        const list = groups.get(inst.parent_entity_id) ?? [];
        list.push(inst);
        groups.set(inst.parent_entity_id, list);
    }
    return groups;
});
```

The `queueBookingUuids` set is derived from the booking list: `bookings.filter(b => b.booking_source === 'queue').map(b => b.uuid)`.

**Alternative approach:** Don't split in the viewmodel. Fetch all instances, group by parent_entity_id. Let the consuming components filter. Simpler viewmodel, filtering pushed to the components. Either approach works — use whichever produces cleaner code.

### 2. Update CommandCenterGrid to provide queue-sourced bookings

**File:** `src/routes/(app)/command-center/_components/CommandCenterGrid.svelte`

The grid orchestrates data fetching. It already fetches bookings by date for BookingsTrack. Now split them:

```typescript
const onlineBookings = $derived(allBookings.filter(b => b.booking_source === 'booking'));
const queueBookings = $derived(allBookings.filter(b => b.booking_source === 'queue'));
```

Pass `queueBookings` to WalkUpTrack. Pass `onlineBookings` to BookingsTrack (or keep passing all and let BookingsTrack filter — depends on how BookingsTrack uses the data).

Build the `queueBookingUuids` set and pass it to the instances viewmodel for group splitting.

### 3. Refactor WalkUpTrack

**File:** `src/routes/(app)/command-center/_components/WalkUpTrack.svelte`

**This is the largest change.** Currently consumes `QueueEntryDto[]`. Needs to consume `BookingDto[]`.

Change the Props interface:
```typescript
interface Props {
    bookings: BookingDto[];                                    // was: entries: QueueEntryDto[]
    products?: ProductDto[];
    queueInstanceGroups?: Map<string, WorkflowInstanceDto[]>;  // keyed by booking UUID now
    definition?: WorkflowDefinitionDto | null;
    error?: string;
    onfetchinstances?: (status: InstanceStatus) => void;
}
```

Update internal logic:
- **Data key:** `booking.uuid` instead of `String(entry.id)`
- **Display name:** `booking.guest_name` instead of `entry.name`
- **Headcount:** `booking.guest_count` instead of `entry.headcount ?? entry.party_size`
- **Time display:** `booking.start_at` instead of `entry.arrived_at ?? entry.created_at`
- **Product lookup:** `booking.product_id` (always set) instead of `entry.product_id` (nullable)
- **Instance lookup:** `instanceMap.get(booking.uuid)` instead of `instanceMap.get(String(entry.id))`
- **CheckInEntity construction:**
  ```typescript
  checkinEntity = {
      entityType: 'booking',        // was 'queue_entry'
      entityId: booking.uuid,       // was String(entry.id)
      entityName: booking.guest_name,
      headcount: booking.guest_count,
      instanceId
  };
  ```

**Filtering:**
- Active view: `bookings.filter(b => b.status === 'confirmed')` (confirmed = in-progress for walk-ups)
- Completed view: `bookings.filter(b => b.status === 'completed')`
- Or: filter by whether the booking has active/completed workflow instances

**Status badge:** The WalkUpTrack currently uses `StatusBadge` with `domain="queue"`. Switch to `domain="booking"` since we're showing BookingDto now.

### 4. Waiver support in WalkUpTrack

**This comes for free.** The existing `getBookingWaivers(uuid)` and `acceptBookingWaivers(uuid, waiverIds)` commands work with any booking UUID. Queue-sourced bookings have UUIDs. The CheckInFlow component already supports waivers via the `waiverVM` prop.

Check if WalkUpTrack passes `waiverVM` to CheckInFlow. If not (BookingsTrack does, WalkUpTrack might not), add it. This gives walk-up checkins the same waiver review capability as online booking checkins.

### 5. QueuePanel: filter out activated entries

**File:** `src/routes/(app)/command-center/_components/QueuePanel.svelte` (or its viewmodel)

QueuePanel should show only non-activated queue entries: Waiting, Arrived, Skipped. Currently it shows all non-complete entries. After convergence, activated entries have `booking_id` set and status='active'. They should no longer appear in QueuePanel since they're represented in WalkUpTrack as bookings.

Filter: `entries.filter(e => e.status !== 'active' && e.status !== 'complete')`

Or equivalently: show only Waiting, Arrived, Skipped.

This might already be the case — verify. If QueuePanel already filters to non-active, no change needed.

### 6. Remove legacy queue_entry instance fetching

**File:** `src/lib/components/commandCenterInstances.svelte.ts`

The `fetchQueueInstances('queue_entry')` call returns nothing for new activations. Remove it or keep it for backward compatibility with any queue entries activated before SLICE 02.

**Recommendation:** Keep it for one release cycle. Old queue entries activated before SLICE 02 still have `parent_entity_type='queue_entry'` workflows. Once those complete (within a day, since queue entries are day-of), the fetch can be removed. Add a TODO comment.

### 7. Optional: Booking source badge

Low priority. Add a visual indicator on booking cards showing source:
- Online bookings: no badge (default)
- Queue bookings: small "Walk-up" label or distinct accent

Can be a `StatusBadge` with a new `domain="booking_source"` or a simple conditional span. Only if time permits — functional without it.

### 8. Review

Run `/review-ts` on all changed files.

## What NOT to do

- Do not change server code — SLICE 02 is complete.
- Do not build `Booking::enrich_guest_identity()` — that's Phase 5 server work.
- Do not change the booking creation or activation endpoint behavior.
- Do not modify the waiver components — they work as-is with booking UUIDs.

## Done criteria

- WalkUpTrack shows queue-sourced bookings instead of queue entries
- WalkUpTrack checkin creates CheckInEntity with `entityType: 'booking'`
- Waiver review accessible from WalkUpTrack checkin flow
- Instance viewmodel fetches all booking-parented workflows and splits by source
- QueuePanel shows only non-activated entries (Waiting, Arrived, Skipped)
- Epoch poller triggers refresh for both BookingsTrack and WalkUpTrack
- BookingsTrack continues working (no regression)
- App compiles and runs (`npm run check`, `cargo check`)
- `/review-ts` passes on changed files

## End State

After SLICE 04, the full convergence is live:

```
Queue Entry (Waiting → Arrived → [activation]) → Booking (source=Queue, Confirmed)
                                                     ↳ Workflow (parent_entity_type="booking")
                                                     ↳ Waivers (waiver_collection.booking_id)
                                                     ↳ WalkUpTrack display
```

QueuePanel is the pre-booking holding area. WalkUpTrack is the post-booking operational view. BookingsTrack shows online bookings. All bookings are bookings.
