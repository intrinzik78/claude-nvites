# Feasibility Study: Walk-Up / Booking Convergence (Option 3)

**Date:** 2026-03-16
**Decision:** Walk-ups are bookings with a `booking_source` discriminator.
**Status:** Decided. Refined through design session. No code changes yet.

---

## 1. The Decision

Add a `booking_source` enum to the booking table. Queue entry activation creates a booking. Waivers attach to the booking via the existing `waiver_collection.booking_id` FK. Queue entries remain the queue-management entity; bookings become the business-record entity.

**BookingSource values:** `Booking` (online, created via website/API) and `Queue` (created at queue entry activation, regardless of how the guest entered the queue). How the guest enters the queue (walk-up vs. call-ahead) is a queue concern tracked by `priority_tier`, not a booking concern.

**Confidence: 92%.** The data model is sound. The remaining work is implementation sequencing.

---

## 2. The Handoff Moment

Queue entry activation is the critical seam where two entities meet.

**Current flow:**
1. Queue entry created (Waiting)
2. Guest arrives (Arrived)
3. Staff activates with product + headcount (Active)
4. Checkin workflow created with `parent_entity_type="queue_entry"`
5. Checkin progresses (waivers, payment, photos)
6. Queue entry marked Complete

**Proposed flow:**
1. Queue entry created (Waiting) — unchanged
2. Guest arrives (Arrived) — unchanged
3. Staff activates with product + headcount:
   - Queue entry → Active (unchanged)
   - **NEW:** Booking created with `booking_source=Queue`, `status=Confirmed`
   - `guest_email` and `person_id` set if email is available, NULL if not
   - Checkin workflow created with `parent_entity_type="booking"` (changed from "queue_entry")
4. Checkin progresses — waivers attach to booking, payment tracked on booking
5. Person linkage happens when email becomes available (waiver signing, staff input, or never)
6. Queue entry marked Complete when checkin workflow completes
7. Booking marked Completed

**Two entities, two concerns:**
- Queue entry = queue management (position, arrival, activation status)
- Booking = business record (product, price, waivers, compliance, history)

This is a legitimate separation of concerns. The queue entry doesn't need to know about waivers. The booking doesn't need to know about queue position.

---

## 3. Progressive Enrichment Model

The core ops insight: **requiring a full guest profile at activation creates friction the guest sees no value in.** The booking doesn't need to be fully formed at creation — it needs to be *enough to be a waiver FK target.*

**What the booking needs at activation (all available):**
- `product_id` — from activation
- `guest_count` / `units_consumed` — from headcount
- `start_at` / `end_at` — now + product duration
- `price_cents` — from product
- `booking_source_id` — Queue
- `booking_status_id` — Confirmed
- `guest_name` — from queue entry
- `uuid` — generated

**What the booking accepts but doesn't require:**
- `guest_email` — nullable for queue-sourced bookings. Set when available.
- `person_id` — nullable (already `Option<i64>` in the Rust type). Set via `Person::find_or_create` when email becomes available.
- `guest_phone` — from queue entry `contact` field if it's a phone number.

**When email becomes available:**
1. **Call-ahead path:** Email captured at submission (QueuePending.email). Available at activation.
2. **Walk-up self-service (QR/website):** Same call-ahead flow. Email available.
3. **Staff-created walk-up:** Staff may collect email at queue creation or activation. Optional.
4. **Waiver signing:** ~85% of organizers sign a waiver (parents required before children — see Mitigation 1). Email captured at signing.
5. **Never:** ~10-15% of queue-sourced bookings may never get email. Acceptable.

**When email is provided**, the system calls `Person::find_or_create(email, name, ...)`:
- If guest is a returning customer → returns existing `person_id`. Cross-channel recognition.
- If new guest → creates person record. Links to booking.
- The booking's `guest_email` and `person_id` are updated together.

**`guest_email` is a snapshot.** It captures the email at the time it was provided, same as `price_cents` captures the price at booking time. If the person's account email changes later, old bookings retain the original. This is the existing behavior and it's correct.

### Person Record Integrity

No ghost person records are created. Every path to `Person::find_or_create` provides at least name + email. The paths:

| Scenario | Person created? | Data quality |
|----------|----------------|-------------|
| Online booking | Yes, at creation | Full (name, email, optional phone) |
| Queue + email at activation | Yes, at activation | Full (name from queue entry, email from staff/call-ahead) |
| Queue + email at waiver signing | Yes, at signing | Full (name, email, DOB, address from waiver form) |
| Queue + no email ever | No | Booking has `guest_name` only. `person_id = NULL`. |

The non-playing organizer who never signs a waiver exists only as a `guest_name` string on the booking row. No person record is created. This is the correct representation of someone the system knows by name but has no verified identity for.

### Mitigation 1: Parent Waiver Before Child Waiver

Require a parent/guardian to complete their own waiver before they can authorize a child's waiver. This is independently correct (ESIGN compliance for minor authorization) and captures the organizer's email as a side effect. Estimated to raise organizer email capture from ~50% to ~85%.

### Mitigation 2: Corporate Events Use Booking Path

Corporate events are pre-planned, budgeted, and need invoices. Staff creates them as online bookings (`booking_source=Booking`) during the phone call. The corporate organizer provides email for confirmation/invoice purposes. These don't go through the walk-up queue.

---

## 4. Server Changes

### 4a. Schema Migration

```sql
-- New lookup table (follows DEC-023 pattern)
CREATE TABLE booking_source (
  id tinyint NOT NULL,
  name varchar(32) NOT NULL,
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

INSERT INTO booking_source (id, name) VALUES
  (1, 'booking'),
  (2, 'queue');

-- Add booking_source column to booking table
ALTER TABLE booking
  ADD COLUMN booking_source_id tinyint NOT NULL DEFAULT 1 AFTER notes,
  ADD CONSTRAINT fk_booking_source
    FOREIGN KEY (booking_source_id) REFERENCES booking_source(id)
    ON DELETE RESTRICT ON UPDATE CASCADE;

-- Make guest_email nullable (queue-sourced bookings may not have email at creation)
ALTER TABLE booking
  MODIFY COLUMN guest_email varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL;

-- Make person_id nullable (already Option<i64> in Rust; align DB constraint)
ALTER TABLE booking
  MODIFY COLUMN person_id int DEFAULT NULL;

-- Link queue entry to its booking (audit trail)
ALTER TABLE queue_entry
  ADD COLUMN booking_id int DEFAULT NULL AFTER headcount,
  ADD CONSTRAINT fk_queue_entry_booking
    FOREIGN KEY (booking_id) REFERENCES booking(id)
    ON DELETE SET NULL ON UPDATE CASCADE;
```

**Notes:**
- `DEFAULT 1` (booking) — all existing bookings are online bookings. No backfill needed.
- `guest_email` nullable — online booking creation path still validates and requires email. Queue path allows NULL.
- `person_id` nullable — migration aligns DB with existing Rust type (`Option<i64>`).
- `queue_entry.booking_id` — explicit link for audit trail. Staff can trace queue entry → booking → waivers → workflow.

### 4b. New Enum: BookingSource

**api-contracts/src/bookings.rs** — new enum:

```rust
#[repr(u8)]
#[derive(Copy, Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
#[cfg_attr(feature = "openapi", derive(utoipa::ToSchema))]
pub enum BookingSource {
    Booking = 1,
    Queue = 2,
}
```

**This is a contract change.** `api-contracts` is shared by server and SDK generators.

### 4c. BookingDto Update

Add to `BookingDto` in api-contracts:
- `booking_source: BookingSource`
- `guest_email: Option<String>` (changed from `String` — nullable for queue-sourced)

Existing consumers that display `guest_email` must handle `None`. Surface-website BookingCard doesn't display email directly — no change needed there.

### 4d. Booking Type Changes

**server/api/src/types/bookings/booking.rs:**
- Add `booking_source: BookingSource` field to `Booking` struct
- Change `guest_email: String` → `guest_email: Option<String>`
- Add getters
- Update `DatabaseHelper` to include `booking_source_id`, change `guest_email` to `Option<String>`
- Update `BOOKING_COLS` constant
- Update `DatabaseHelper::transform()` to convert booking_source_id → enum
- Update `From<&Booking> for BookingDto` to include booking_source

**NewBooking::into_db()** — unchanged for online bookings. Add `booking_source_id = 1` (Booking) to the INSERT. Continue to require guest_email.

**New struct: `NewQueueBooking`**
```rust
pub struct NewQueueBooking {
    pub product_id: i32,
    pub guest_name: String,
    pub guest_email: Option<String>,   // nullable — may not be available
    pub guest_phone: Option<String>,
    pub guest_count: u16,
    pub person_id: Option<i64>,        // set if email available → find_or_create
    pub notes: Option<String>,
}
```

`NewQueueBooking::into_db()`:
- **No capacity gating** (ops team already made the call)
- Sets `start_at = Utc::now()`, `end_at = start_at + product.duration_minutes`
- Sets `booking_status = Confirmed` (guest is physically present)
- Sets `price_cents` from product
- Sets `booking_source_id = 2` (Queue)
- Generates UUID
- If `guest_email` is Some → `Person::find_or_create` → set `person_id`
- If `guest_email` is None → `person_id = NULL`

Separate struct from `NewBooking` because the invariants differ: no capacity check, no email requirement, Confirmed instead of Pending.

### 4e. Booking Email + Person Enrichment

New function for post-creation enrichment:

```rust
impl Booking {
    pub async fn enrich_guest_identity(
        id: i32,
        guest_email: &str,
        person_id: i64,
        connection: &DatabaseConnection,
    ) -> Result<()> { ... }
}
```

Called when email becomes available after booking creation (waiver signing, staff input). Updates `guest_email` and `person_id` on the booking row.

### 4f. Queue Entry Activation Handler Change

**server/api/src/api/queue_entries/queue_entry_activate.rs** — current:
1. Validates product exists and is active
2. Validates headcount bounds
3. `QueueEntry::update_activation(id, product_id, headcount, db)`
4. Creates checkin workflow with `parent_entity_type="queue_entry"`
5. Returns updated QueueEntryDto

Proposed:
1. Validates product exists and is active — unchanged
2. Validates headcount bounds — unchanged
3. Resolve email: check queue entry for email / person_id. Optional.
4. If email available → `Person::find_or_create(email, name, ...)` → get person_id
5. `NewQueueBooking { ... }.into_db(&product, db)` — create booking
6. `QueueEntry::update_activation(id, product_id, headcount, db)` — mark active
7. `QueueEntry::set_booking_id(id, booking.id(), db)` — link
8. Creates checkin workflow with `parent_entity_type="booking"`, `booking.uuid()` (changed from "queue_entry")
9. Returns response with both QueueEntryDto and BookingDto

**Transaction scope:** Steps 5-7 should be atomic. If booking creation fails, queue entry activation rolls back.

### 4g. Error Enum Additions

New variants in `server/api/src/enums/error.rs`:
- `BookingSourceOutOfBounds(u8)` — invalid booking_source_id from DB

`QueueEntryEmailRequired` is NOT needed — email is optional at activation. No blocking error.

Update `to_api_error_message()` mapping and bump `EXPECTED_CLIENT_FACING_COUNT`.

### 4h. Workflow Parent Entity Type

**Current behavior:**
- Booking confirmation → workflow with `parent_entity_type="booking"`
- Queue entry activation → workflow with `parent_entity_type="queue_entry"`

**New behavior:**
- Booking confirmation → workflow with `parent_entity_type="booking"` (unchanged)
- Queue entry activation → creates booking → workflow with `parent_entity_type="booking"` (changed)

**Impact on existing code:**
- `checkin_service.rs` `sync_waiver_count()` — already handles "booking" parent type. No change.
- `WorkflowInstance::by_parent("booking", uuid, db)` — works for queue-sourced bookings.
- `commandCenterInstances.svelte.ts` — fetches by parent_entity_type. WalkUpTrack currently fetches "queue_entry" instances. **Must change** (see Section 6).
- `EpochGuard` — bookings support epoch locking, queue entries don't. Queue-sourced bookings get epoch protection for free. Improvement.

### 4i. Availability / Capacity Queries

`Booking::booked_windows_for_type_on_date()` sums all Pending/Confirmed bookings for capacity calculation. Queue-sourced bookings (Confirmed) are included automatically.

**Correct behavior.** Once a walk-up is activated and a booking is created, those resources ARE consumed. The capacity query reflects this so the online booking system doesn't overbook.

### 4j. Build Pipeline

This touches `api-contracts` (BookingSource enum, BookingDto changes). Full pipeline:
```
cargo xtask build-all
```
(api-contracts → schema-emitter → dist/openapi.json → server → sdk-ts types)

---

## 5. Surface-Website Changes

**None.** The website consumes BookingDto without destructuring or field validation. New `booking_source` field is additive. `guest_email` becoming `Option<String>` is the only consideration — the website displays guest_email in the portal BookingCard, which would need to handle null. However, portal bookings are always for authenticated users (person_id set), and those users provided their email to authenticate — so their bookings will always have guest_email populated. No functional change needed.

SDK types auto-regenerate via `cargo xtask build-all`.

---

## 6. Surface-Command-Center Changes

### 6a. Types

Update BookingDto in `src/lib/types.ts`:
```typescript
booking_source: 'booking' | 'queue';
guest_email: string | null;  // changed from string
```

### 6b. QueueActivateModal

Current: Selects product + headcount, calls `activateQueueEntry(id, productId, headcount)`.

Change: Modal can optionally collect email if not already on the queue entry. The activation endpoint returns both the updated queue entry and the new booking.

**API command change:** `activateQueueEntry()` returns a combined response:
```typescript
interface ActivateQueueEntryResponse {
  queue_entry: QueueEntryDto;
  booking: BookingDto;
}
```

Single atomic endpoint. Server does both operations in one transaction.

### 6c. WalkUpTrack

**Current:** Fetches workflow instances with `parent_entity_type='queue_entry'`, displays active queue entries.

**After convergence:** Walk-up checkin workflows have `parent_entity_type='booking'`. WalkUpTrack must change data source.

**Approach: WalkUpTrack shows queue-sourced bookings.**
- Fetch bookings for today with `booking_source='queue'` filter
- Fetch workflow instances with `parent_entity_type='booking'`
- Filter to queue-sourced bookings by matching parent_entity_id to booking UUIDs
- Waiver status directly visible (booking UUID → waivers)

The QueuePanel (pre-activation entries: Waiting, Arrived, Skipped) continues to use QueueEntryDto. The handoff from QueuePanel to WalkUpTrack now represents the queue entry → booking promotion.

### 6d. BookingsTrack

Optional: Add `booking_source` badge to booking cards. Filter options could include source. Low-priority — functional without it.

### 6e. Checkin Workflow

**No changes.** CheckInFlow already supports `entityType: 'booking'`. The initial context for queue-sourced bookings:
```typescript
{
  accepted: true,
  payment_confirmed: false,  // walk-ups pay after playing
  headcount: entry.headcount,
  waiver_count: 0,
  photos_taken: false
}
```

The `payment_confirmed: false` distinction is correct — online bookings prepay, walk-ups don't.

### 6f. Waiver Attachment

**No changes to waiver components.** `getBookingWaivers(uuid)` and `acceptBookingWaivers(uuid, waiverIds)` work with any booking UUID. Queue-sourced bookings have UUIDs. Works out of the box.

### 6g. Person Enrichment Trigger

When a waiver is signed for a booking that has `person_id = NULL`, the system can check: does the waiver signer's email match the booking's `guest_name`? If likely the organizer, call `Booking::enrich_guest_identity()` to backfill `guest_email` and `person_id`. This is an enhancement, not a blocker — can be built in a later phase.

---

## 7. Blast Radius Summary

| Area | Impact | Effort |
|------|--------|--------|
| **DB schema** | New lookup table, new column on booking, nullable guest_email/person_id, optional column on queue_entry | Low |
| **api-contracts** | New BookingSource enum, BookingDto changes (source field, nullable email) | Low (contract change) |
| **server types** | Booking struct changes, NewQueueBooking, enrich_guest_identity | Medium |
| **server handlers** | queue_entry_activate.rs rewrite, bookings_post.rs minor | Medium |
| **server enums** | BookingSource, 1 new Error variant | Low |
| **server workflow** | parent_entity_type change at one call site | Low |
| **sdk-ts** | Auto-regenerated types | Zero (build pipeline) |
| **surface-website** | None | Zero |
| **surface-command-center** | WalkUpTrack refactor, QueueActivateModal update, types | High |

**Total scope:** Medium-large. Server changes are well-scoped. Command center WalkUpTrack refactor is the largest single piece.

---

## 8. Implementation Sequence

### Phase 1: Schema + Server Types
- Migration: booking_source lookup table, booking.booking_source_id column, nullable guest_email/person_id
- BookingSource enum in api-contracts
- Booking type updates (field, getter, DatabaseHelper, DTO conversion)
- Update NewBooking::into_db() to set booking_source_id=1 (Booking)
- `cargo xtask build-all` — verify pipeline

### Phase 2: Queue Booking Creation Path
- NewQueueBooking struct and into_db() (no capacity check, Confirmed status, nullable email/person)
- queue_entry_activate.rs: create booking at activation, link queue entry
- queue_entry.booking_id column migration
- New error variant
- Integration tests

### Phase 3: Command Center — Activation Flow
- QueueActivateModal: optional email collection, updated response handling
- activateQueueEntry command: combined response type
- Types update

### Phase 4: Command Center — WalkUpTrack Refactor
- WalkUpTrack data source: queue-sourced bookings instead of queue entries
- Workflow instance fetching: all instances parent to "booking" now
- Waiver display: works automatically via booking UUID

### Phase 5: Enrichment + Polish
- Booking::enrich_guest_identity() for post-creation person linkage
- Waiver-signing → person enrichment trigger (enhancement)
- Parent waiver before child waiver (Mitigation 1 — independent work item)
- BookingSource badge in command center (optional)
- Verify waiver flow end-to-end
- Verify portal shows queue-sourced bookings for authenticated users

---

## 9. What This Unblocks

- **Walk-up waiver attachment** — waivers FK to booking, walk-ups create bookings at activation
- **Queue → walk-up promotion** — activation IS the promotion
- **Unified reporting** — all visits are bookings, filterable by source
- **Unified workflow** — all checkins parent to bookings, epoch-protected
- **Returning customer recognition** — `Person::find_or_create` links walk-ups to existing customers
- **Portal visibility** — walk-up guests with email can see their booking in the portal
- **Progressive enrichment** — data captured naturally through operational flow, not forced at a friction point

---

## 10. Decisions Made During This Session

These should be promoted to `docs/DECISIONS.md` when implementation begins:

1. **Walk-ups are bookings.** `BookingSource` enum with `Booking` (online) and `Queue` (any queue path) discriminates origin. How the guest entered the queue (walk-up vs. call-ahead) is tracked by `priority_tier` on the queue entry, not by `booking_source` on the booking.

2. **Progressive enrichment.** Queue-sourced bookings allow `guest_email = NULL` and `person_id = NULL` at creation. Email and person linkage are populated when available (activation, waiver signing, staff input, or never). ~10-15% of queue-sourced bookings may never get person linkage. Acceptable.

3. **No ghost person records.** Person records are only created via `Person::find_or_create` when email is available. Bookings without email have `person_id = NULL`. No empty/partial person rows.

4. **Capacity gating is channel-specific.** Online bookings go through algorithmic capacity gating (`consumed_capacity()` + FOR UPDATE). Queue-sourced bookings skip capacity gating — the ops team's decision to activate IS the capacity judgment.

5. **Corporate events use the booking path.** Pre-planned corporate events are created as online bookings by staff, not routed through the walk-up queue. The organizer provides email for invoicing/confirmation.

6. **Parent waiver before child waiver.** Independent of convergence, but raises organizer email capture from ~50% to ~85% for family groups. Good ESIGN practice.
