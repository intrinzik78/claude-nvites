# Command Center 3-Panel Wiring Plan

## Context

The command center is the staff operational cockpit. It needs a 3-panel primary view where each panel is a filtered view of workflow instances running the v2 checkin workflow. The infrastructure exists (workflow engine, SDK, Tauri commands, UI components) but isn't wired together. Digital queue is deferred — this plan covers **bookings + walk-ups only**.

### The v2 Checkin Workflow (10 steps)

| Step | Type | Phase | Gate/Trigger |
|------|------|-------|-------------|
| `ci_accept` | auto | intake | `accepted == true` |
| `ci_prep` | manual | pre_arrival | — |
| `ci_fill` | manual | pre_arrival | — |
| `ci_arrive` | manual | check_in | — |
| `ci_checkin` | manual | check_in | — |
| `ci_waivers` | gate | check_in | `waiver_count >= headcount` |
| `ci_payment` | auto | check_in | `payment_confirmed == true` |
| `ci_safety` | manual | service | — |
| `ci_playing` | manual | service | — |
| `ci_complete` | manual | service | — |

### Three Entry Paths (same workflow, different initial context)

- **Online booking**: `{ accepted: true, payment_confirmed: true, headcount: N }` → normalization skips both auto-gates → lands at `ci_prep`
- **Walk-up**: `{ accepted: true, payment_confirmed: false, headcount: N }` → skips `ci_accept` → blocks at `ci_payment` until POS confirms
- **Digital queue** (DEFERRED): `{ accepted: false }` → blocks at `ci_accept`

### Panel Layout

| Panel | Content | Filter |
|-------|---------|--------|
| **Left (57fr)** | Prepaid bookings with workflow progress | `parent_entity_type = 'booking'` |
| **Right upper (57fr)** | Activated walk-ups with workflow progress | `parent_entity_type = 'queue_entry'`, active instances |
| **Right lower (43fr)** | Queue CRUD (existing panel, unchanged) | Queue entries by status |

### Context Updates

`waiver_count` and `payment_confirmed` are updated automatically by other systems (waiver submission endpoint, POS) via `PATCH /v1/workflow-instances/{id}/context`. Those integrations are **separate work items** — not in this plan. For now, staff can manually trigger context updates through the CheckInFlow UI as a fallback.

---

## QC Protocol

**Antipattern: moving to the next slice without running QC checks.**

Every slice that touches Rust code (server, sdk-rust, src-tauri) must pass `/review` before proceeding. Every slice that touches TypeScript/Svelte (surface-command-center frontend) must pass `/review-ts` before proceeding. Slices touching both get both reviews.

| Slice | Rust (`/review`) | TS/Svelte (`/review-ts`) | Build gate |
|-------|-------------------|--------------------------|------------|
| 1 | src-tauri | commands.ts | `cargo xtask build-all` + `cargo check` (src-tauri) |
| 2 | server handlers | — | `cargo xtask build-all` + `cargo test` |
| 3 | — | new VM + commands.ts | `npm run check` |
| 4 | — | CheckInFlow + VM | `npm run check` |
| 5 | — | BookingsTrack + page | `npm run check` |
| 6 | — | WalkUpTrack + page | `npm run check` |
| 7 | — | all panels + page | `npm run check` |

---

## Slice 1: Apply v2 Migration + Fix Tauri Instance Listing

**What**: Run the two pending migrations. Fix the Tauri `list_workflow_instances` command to pass filter params through to the SDK instead of fetching everything.

**Why**: Everything downstream depends on v2 workflow existing and efficient instance listing.

**Files**:
- Apply `server/migrations/20260227120000_replace_checkin_workflow.sql`
- Apply `server/migrations/20260227120001_instance_status_step_index.sql`
- Edit `surface-command-center/src-tauri/src/commands/workflows.rs` — pass `status`, `parent_entity_type`, `parent_entity_id` to SDK's `list_instances()` instead of post-fetch filtering
- Edit `surface-command-center/src/lib/api/commands.ts` — add optional `status` param to `listWorkflowInstances`

**Risks**:
- Existing v1 instances in dev data are pinned to v1 definition (now Archived). They continue working but have different step IDs. Acceptable — they'll complete naturally.
- Tauri command signature change is backwards-compatible (new params are optional).

**Verify**: `cd server && cargo xtask build-all` passes. `cargo check` in `src-tauri`. DB query: `SELECT id, workflow_key, version, status_id FROM workflow_definition` shows v2 with status_id=1 (Published).

**QC gate**: `/review` (src-tauri Rust changes). `/review-ts` (commands.ts changes). Must pass before Slice 2.

---

## Slice 2: Server-Side Auto-Creation of Workflow Instances

**What**: Add workflow instance creation to two server handlers:
1. **`bookings_status_patch.rs`**: On `Pending → Confirmed`, create instance with `{ accepted: true, payment_confirmed: true, headcount: guest_count, waiver_count: 0, photos_taken: false }`. On `Confirmed → Cancelled`, cancel the active instance.
2. **`queue_entry_activate.rs`**: On `arrived → active`, create instance with `{ accepted: true, payment_confirmed: false, headcount, waiver_count: 0, photos_taken: false }`.

**Why**: The 3-panel view needs instances to exist before staff clicks into a specific entity. Server-side creation is the clean path.

**Files**:
- `server/api/src/api/bookings/bookings_status_patch.rs` — after status update, create/cancel instance
- `server/api/src/api/queue_entries/queue_entry_activate.rs` — after activation, create instance
- New helper: `server/api/src/types/workflow/checkin_service.rs` — shared logic: find-or-create instance for parent entity, with idempotency guard (check for existing active instance before creating)

**Existing patterns to reuse**:
- `WorkflowInstance::create()` in `server/api/src/types/workflow/instance.rs`
- `WorkflowEngine::normalize()` in `server/api/src/types/workflow/engine.rs` — called after creation to auto-advance past satisfied gates
- `WorkflowInstance::filtered()` — to check for existing instances

**Risks**:
- **Idempotency**: Handler called twice → booking confirmed but instance already exists. Guard: check for active instance before creating. If exists, skip.
- **Transaction boundaries**: Instance creation is a separate query after status update. If creation fails, booking is confirmed with no instance. Fallback: `checkInFlow.svelte.ts` `loadOrCreate` creates on demand (existing behavior, kept as safety net).
- **Cancellation cascade**: Confirmed → Cancelled must also cancel the workflow instance. Find active instance by `parent_entity_type=booking, parent_entity_id=uuid`, set status to Cancelled.

**Verify**: `cargo xtask build-all` + `cargo test`. Manual: confirm a booking via API → `SELECT * FROM workflow_instance WHERE parent_entity_id = '{uuid}'` shows instance at `ci_prep`.

**QC gate**: `/review` (server Rust changes). Must pass before Slice 3.

---

## Slice 3: Command Center Instances ViewModel

**What**: New `commandCenterInstances.svelte.ts` ViewModel that fetches all active workflow instances and partitions them for the two panels (bookings vs queue entries). Also caches the v2 workflow definition for step rendering.

**Why**: Both panels need the same data source. Single VM avoids double-fetching and ensures consistent state.

**Files**:
- New: `surface-command-center/src/lib/components/commandCenterInstances.svelte.ts`
- Edit: `surface-command-center/src/lib/api/commands.ts` — add `listActiveInstances()` helper that calls `listWorkflowInstances` with `status: 'Active'`

**Shape**:
```typescript
createCommandCenterInstancesViewModel() {
  // State
  allInstances: WorkflowInstanceDto[]
  definition: WorkflowDefinitionDto | null
  loading, error

  // Derived
  bookingInstances: $derived(filter parent_entity_type === 'booking')
  queueInstances: $derived(filter parent_entity_type === 'queue_entry')

  // Methods
  fetch() — parallel: list active instances + get definition (from first instance's workflow_id, cached)
  refreshAfterMutation() — re-fetch, callable from any panel after advance/cancel/context-update
}
```

**Pattern**: Follow `queuePanel.svelte.ts` — `$state` + `$derived`, 30s polling, error/loading states.

**Risks**:
- **No instances yet**: Fresh day with no confirmed bookings → empty lists. Panels show empty states. Natural.
- **Definition fetch**: Need the v2 definition ID. Options: (a) get from first instance's `workflow_id`, (b) list definitions and find `checkin` published. Go with (a), fallback to (b) if no instances.
- **Completed instances filtered out**: Only Active status fetched. Staff sees completed bookings in the booking list (left panel still has bookingListVM), but not in the workflow view.

**Verify**: TS compiles (`npm run check`). Manual: with instances in DB, verify `bookingInstances` and `queueInstances` partition correctly.

**QC gate**: `/review-ts` (new VM + commands.ts changes). Must pass before Slice 5.

---

## Slice 4: Update CheckInFlow for v2 Steps

**What**: Remove hardcoded `CHECKIN_STEP_FIELDS` map (v1 step IDs) from `CheckInFlow.svelte`. Make it work generically with any workflow definition. Handle auto/gate step types in the UI. Generalize to work with both bookings and queue entries.

**Why**: The hardcoded map references v1 IDs (`verify_booking`, `collect_waivers`) that don't exist in v2. Auto steps (`ci_accept`, `ci_payment`) can't be manually advanced — the UI must reflect this.

**Files**:
- `surface-command-center/src/lib/components/CheckInFlow.svelte` — remove `CHECKIN_STEP_FIELDS`; derive field visibility from `context_schema` + step type; render auto steps as status indicators (not advance buttons); render gate steps with blocking message
- `surface-command-center/src/lib/components/checkInFlow.svelte.ts` — update `loadOrCreate` initial context to include v2 fields; prefer finding existing instance (server-created); handle auto-step Rejected result gracefully

**Key UI changes**:
- **Manual steps**: Show "Complete Step" button (existing behavior)
- **Auto steps** (`ci_accept`, `ci_payment`): Show waiting indicator ("Waiting for payment confirmation"), no advance button. When context is updated externally, instance auto-advances — next poll shows progress.
- **Gate steps** (`ci_waivers`): Show advance button + condition status ("3 of 5 waivers collected"). On advance, if blocked, show message from `AdvanceResult::Blocked`.
- **Field rendering**: For current step, show context fields relevant to that step's condition (parse condition string for field names). For manual steps, show `input` source fields. Use existing `StepContextFields.svelte`.

**Generalization for queue entries**: Extract entity-agnostic interface:
```typescript
interface CheckInEntity {
  entityType: 'booking' | 'queue_entry';
  entityId: string;
  entityName: string;
  headcount: number;
}
```
`CheckInFlow` accepts this instead of `BookingDto`. Both `BookingsTrack` and `WalkUpTrack` adapt their entity into this shape.

**Risks**:
- **V1 backward compatibility**: Any v1 instances still active render correctly — the dynamic approach reads from the definition, not hardcoded IDs. V1 steps are all manual, so no auto/gate UI needed.
- **Auto-step advance rejection**: Engine returns `Rejected` for auto steps. Currently the error displays as "Rejected: ...". With the UI hiding the advance button for auto steps, this path is unreachable. But keep the error handling as defense.

**Verify**: Frontend compiles (`npm run check`). Manual: open a booking with v2 instance → steps render with v2 labels → auto steps show status indicators → gate step shows condition.

**QC gate**: `/review-ts` (CheckInFlow + VM changes). Must pass before Slice 5/6.

---

## Slice 5: Wire Left Panel (Bookings) to Workflow Instances

**What**: Update `BookingsTrack` to show workflow progress inline on each booking. When the central VM has a matching instance for a booking UUID, show a SequenceBar. Clicking a booking with an active instance opens the CheckInFlow directly.

**Why**: The left panel needs to show operational state, not just booking metadata.

**Files**:
- `surface-command-center/src/routes/(app)/command-center/_components/BookingsTrack.svelte` — accept `bookingInstances` and `definition` from central VM; match instances to bookings by `parent_entity_id === booking.uuid`; show SequenceBar per booking; update `startCheckIn` to pass to generalized CheckInFlow
- `surface-command-center/src/lib/components/BookingList.svelte` — add optional `instanceMap` prop; render SequenceBar inline per row
- `surface-command-center/src/routes/(app)/command-center/+page.svelte` — create central VM; pass `bookingInstances` and `definition` to BookingsTrack

**Risks**:
- **No instance for a booking**: Not all bookings have instances (only Confirmed ones do). Show booking as normal (no SequenceBar). "Start Check-In" button triggers `loadOrCreate` fallback.
- **Instance-to-booking join**: Join by `parent_entity_id === booking.uuid`. The instance stores the UUID as a string. Type match should be exact.

**Verify**: `npm run check`. Manual: confirm booking → refresh → booking row shows SequenceBar at `ci_prep`. Click → opens CheckInFlow. Advance through steps → SequenceBar updates.

**QC gate**: `/review-ts` (BookingsTrack + BookingList + page changes). Must pass before Slice 7.

---

## Slice 6: Build Right Upper Panel (Walk-Up Track)

**What**: New `WalkUpTrack.svelte` component replacing the placeholder. Shows activated queue entries with their workflow progress. Clicking expands to CheckInFlow.

**Why**: Walk-ups that have been activated and assigned a product need operational visibility alongside bookings.

**Files**:
- New: `surface-command-center/src/routes/(app)/command-center/_components/WalkUpTrack.svelte`
- `surface-command-center/src/routes/(app)/command-center/+page.svelte` — wire WalkUpTrack into `rightUpper` snippet

**Data joining**: Workflow instances have `parent_entity_id` (queue entry ID as string) but not the entry's name or party size. The WalkUpTrack needs queue entry data alongside instance data. Two approaches:
- (a) WalkUpTrack accepts both `queueInstances` from central VM and `entries` from queuePanelVM, joins client-side by `parent_entity_id === String(entry.id)`
- (b) Instance context has `headcount` already. The queue entry name can be fetched separately.

Go with (a) — reuse existing queuePanelVM data.

**Component structure** (follows BookingsTrack pattern):
- List view: rows with name, party size, SequenceBar, StatusBadge
- Detail view: CheckInFlow with generalized CheckInEntity interface

**Risks**:
- **Queue entry data lag**: queuePanelVM and central instances VM poll independently. A freshly activated entry might appear in the instances list before the queue list refreshes (or vice versa). Tolerate gracefully — show "Loading..." for unmatched instances. Next poll resolves.
- **Activated but no instance**: If activation happened before Slice 2 was deployed, the queue entry is active with no instance. Show without SequenceBar, let staff trigger `loadOrCreate`.

**Verify**: `npm run check`. Manual: create queue entry → arrive → activate → right upper shows entry with SequenceBar. Click → CheckInFlow. Advance → progress updates.

**QC gate**: `/review-ts` (WalkUpTrack + page changes). Must pass before Slice 7.

---

## Slice 7: Integration Polish + Refresh Coordination

**What**: Wire the coordinator page with all three data sources. Coordinate refresh after mutations. Ensure day lock applies to workflow actions. Empty/error states per panel.

**Files**:
- `surface-command-center/src/routes/(app)/command-center/+page.svelte` — final coordinator wiring: create central VM, pass partitioned data to all panels, provide `refreshAfterMutation` callback
- All panel components — call `refreshAfterMutation()` after any advance/cancel/context-update
- `DayLockBanner` integration — disable advance/cancel buttons when `locked === true`
- Empty states per panel: "No bookings for today", "No active walk-ups", "Queue is clear"

**Risks**:
- **Polling coordination**: Three data sources (bookings, queue entries, instances) poll independently. Mutation in one may not reflect in others until next tick. Mitigation: `refreshAfterMutation()` triggers all three to re-fetch. Slightly chatty but consistent.
- **Day lock**: Currently only BookingSearch and DatePicker use it. Workflow advance buttons must also check. Read `locked` from `getDayLockContext()` in CheckInFlow.

**Verify**: Full end-to-end:
1. Login → Command Center loads → all three panels render (possibly empty)
2. Create queue entry → arrive → activate → appears in right upper with SequenceBar
3. Confirm a booking → appears in left panel with SequenceBar at ci_prep
4. Advance booking through steps → SequenceBar progresses → gate blocks at ci_waivers → manually update waiver_count → advance past gate → auto-advances past ci_payment → service phase → complete
5. Navigate to past date → DayLockBanner shows → advance buttons disabled
6. Kill server → error badges appear per panel

**QC gate**: `/review-ts` (final integration pass across all panels). This is the last gate before the feature is shippable.

---

## Red Team

### Cross-Cutting Concerns

1. **V1→V2 transition**: V1 instances still active will render correctly (definition loaded by `workflow_id`, not latest published). V1 step labels differ from v2 but the dynamic approach handles both. Temporary state.

2. **Duplicate instance guard**: If server auto-creation (Slice 2) and `loadOrCreate` fallback (existing) both fire for the same entity, could create duplicate active instances. **Mitigation**: `checkin_service.rs` checks for existing active instance before creating. `loadOrCreate` also checks first. Belt and suspenders.

3. **Auto-step UX**: When `ci_accept` or `ci_payment` auto-fires on creation (because context is pre-satisfied), the instance lands at the next manual step. Staff never sees the auto step. SequenceBar shows it as passed (green pill). Correct behavior.

4. **waiver_count / payment_confirmed updates**: These come from external systems (waiver endpoint, POS) calling `PATCH /v1/workflow-instances/{id}/context`. Those integrations are **not in this plan** — they are separate slices on the server workstream. For now, staff can manually update context through StepContextFields UI. The auto-step will fire as soon as the value satisfies the condition, regardless of who set it.

5. **Booking cancellation cascade** (Slice 2): When `Confirmed → Cancelled`, the active workflow instance must also be cancelled. Otherwise it lingers as an orphan in the operational panel.

### Ordering Dependencies

```
Slice 1 (migration + Tauri)
  ↓
Slice 2 (server auto-creation)
  ↓
Slice 3 (central VM)  ←→  Slice 4 (CheckInFlow v2)  [parallel]
  ↓                          ↓
Slice 5 (left panel)  ←→  Slice 6 (right upper)      [parallel]
  ↓                          ↓
  └──────→ Slice 7 (integration) ←──────┘
```

Slices 3+4 can be parallel. Slices 5+6 can be parallel (after 3+4). Slice 7 requires all prior.

### What Could Go Wrong

1. **Migration + frontend mismatch**: If v2 migration runs but CheckInFlow still has v1 hardcoded map, new bookings get v2 instances that render with empty step fields. **Gate**: Slice 4 must ship alongside or before Slice 1 goes to production. For dev, run Slice 1 first and accept temporary breakage.

2. **Orphaned instances on booking cancellation**: If Slice 2 creates instances but doesn't handle cancellation cascade, cancelled bookings show in the operational panel. **Gate**: cancellation cascade is part of Slice 2, not deferred.

3. **Instance-to-entity join misses**: The join between workflow instances and bookings/queue entries relies on string matching (`parent_entity_id`). If booking UUIDs or queue entry IDs are stored differently (e.g., int vs string), the join silently fails. **Mitigation**: verify format in Slice 3 with real DB data.

## Deferred Work (not in this plan)

- **Digital queue** (website → queue entry with `OnlineCallAhead` priority → right lower panel as acceptance inbox)
- **Waiver submission → workflow context sync** (waiver endpoint updates `waiver_count` on instance)
- **POS → payment confirmation sync** (POS updates `payment_confirmed` on instance)
- **Check-in group entity** (from command-center.json — split mechanics, group statuses)
- **Completed instances view** (toggle/filter for recently completed check-ins)
