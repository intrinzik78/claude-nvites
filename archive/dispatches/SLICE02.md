# SLICE 02: Queue Booking Creation Path

**Date:** 2026-03-16
**From:** dev design session
**To:** server worktree
**Prerequisite:** SLICE 01 (BookingSource enum, nullable guest_email/person_id, migration applied)

---

## Goal

When staff activates a queue entry, the system creates a booking with `booking_source=Queue`. The workflow parents to the booking, not the queue entry. Waivers can now attach to walk-up visits via the existing `waiver_collection.booking_id` FK.

After this slice, the server supports the full activation→booking→workflow path. The command center still uses the old activation response shape — Phase 3/4 updates the UI.

## Reference

- `docs/FEASIBILITY_WALKUP_BOOKING_CONVERGENCE.md` — Sections 2, 3, 4d–4h
- `docs/RUST_STYLE_GUIDE.md` — code conventions
- `server/api/src/api/queue_entries/queue_entry_activate.rs` — current handler (read it first)

## Tasks

### 1. Migration: queue_entry.booking_id + queue_entry.email

New migration in `server/migrations/`:

```sql
-- Link queue entry to its booking (audit trail, set at activation)
ALTER TABLE queue_entry
  ADD COLUMN booking_id int DEFAULT NULL AFTER headcount,
  ADD CONSTRAINT fk_queue_entry_booking
    FOREIGN KEY (booking_id) REFERENCES booking(id)
    ON DELETE SET NULL ON UPDATE CASCADE;

-- Optional email for queue entries (call-ahead has email; staff walk-ups may not)
ALTER TABLE queue_entry
  ADD COLUMN email varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL AFTER contact;
```

**Notes:**
- `booking_id` is nullable — only set after activation creates a booking.
- `email` is nullable — call-ahead entries get email from QueuePending confirmation flow; staff-created walk-ups may not have it.
- `ON DELETE SET NULL` — if a booking is somehow deleted, the queue entry survives. Defensive.

### 2. QueueEntry type changes

**File:** `server/api/src/types/queue_entries/queue_entry.rs`

- Add `email: Option<String>` field to `QueueEntry` struct
- Add `booking_id: Option<i32>` field to `QueueEntry` struct
- Add getters for both
- Update `DatabaseHelper`: add `email: Option<String>`, `booking_id: Option<i32>`
- Update `QUEUE_ENTRY_COLS` constant
- Update `DatabaseHelper::transform()` — direct field pass-through (no enum conversion needed)
- Add `QueueEntry::set_booking_id(id, booking_id, db)` — UPDATE query for linking after activation

### 3. QueueEntryDto update

**File:** `api-contracts/src/queue_entries.rs`

Add to `QueueEntryDto`:
- `pub email: Option<String>`
- `pub booking_id: Option<i32>`

Update `From<&QueueEntry> for QueueEntryDto` to include both fields.

**This is a contract change.** Additive — new optional fields don't break existing consumers.

### 4. CreateQueueEntryBody update

**File:** `api-contracts/src/queue_entries.rs`

Add optional email field:
```rust
/// Optional. Valid email address, max 254 characters.
pub email: Option<String>,
```

Update the queue entry creation handler (`queue_entries_post.rs`) and `NewQueueEntry` to accept and persist the email field.

### 5. QueuePending → QueueEntry: carry email forward

**File:** `server/api/src/types/queue_entries/queue_pending.rs`

In `QueuePending::confirm()`, the INSERT into `queue_entry` currently doesn't set email. Update to include `email = pending.email()` in the INSERT. Call-ahead entries will now have email on the queue_entry row.

### 6. NewQueueBooking

**File:** `server/api/src/types/bookings/booking.rs`

New struct:

```rust
pub struct NewQueueBooking {
    pub product_id: i32,
    pub guest_name: String,
    pub guest_email: Option<String>,
    pub guest_phone: Option<String>,
    pub guest_count: u16,
    pub person_id: Option<i64>,
    pub notes: Option<String>,
}
```

`NewQueueBooking::into_db(self, product: &Product, db: &DatabaseConnection) -> Result<Booking>`:
- **No capacity gating** — no `consumed_capacity()` check, no transaction needed for capacity
- Sets `start_at = Utc::now()`
- Sets `end_at = start_at + product.duration_minutes`
- Sets `booking_status = Confirmed` (guest is physically present)
- Sets `price_cents = product.price_cents()`
- Sets `booking_source_id = 2` (Queue)
- Generates UUID via `Uuid::web_safe_with_nums`
- `guest_email` and `person_id` passed through as-is (both nullable)

**Key difference from `NewBooking::into_db()`:** No FOR UPDATE capacity check, no transaction wrapping for capacity, starts at Confirmed instead of Pending.

### 7. Rewrite queue_entry_activate.rs

**File:** `server/api/src/api/queue_entries/queue_entry_activate.rs`

Current flow:
1. Validate entry exists, transition valid, product active, headcount bounds
2. `QueueEntry::update_activation()`
3. Create checkin workflow with `parent_entity_type="queue_entry"`
4. Return QueueEntryDto

New flow:
1. Validate entry exists, transition valid, product active, headcount bounds — **unchanged**
2. Resolve person: if `entry.email()` is Some → `Person::find_or_create(email, name, phone, db)` → get `person_id`
3. Create booking: `NewQueueBooking { ... }.into_db(&product, db)`
4. `QueueEntry::update_activation(id, product_id, headcount, db)` — **unchanged**
5. `QueueEntry::set_booking_id(id, booking.id(), db)` — link queue entry to booking
6. Create checkin workflow with `parent_entity_type="booking"`, `booking.uuid()` — **changed from "queue_entry"**
7. Return response

**Transaction scope:** Steps 3-5 should ideally be atomic. If booking creation succeeds but queue entry update fails, we have an orphaned booking. Two approaches:
- Wrap 3-5 in a transaction (cleanest, requires `NewQueueBooking::into_db_tx` variant that takes `&mut Transaction`)
- Accept the risk — orphaned bookings are harmless (no waivers attached yet, no workflow). Staff retries activation.

Recommendation: **Wrap in a transaction** if it's straightforward to add a `into_db_tx` variant. Otherwise accept the risk and add a TODO for Phase 5.

**Response shape:** For now, return the existing `QueueEntryDto` response (the command center expects this). The QueueEntryDto now includes `booking_id` which the command center will use in Phase 3/4. Do NOT change the response envelope shape in this slice — that's Phase 3.

### 8. Name splitting for Person::find_or_create

`Person::find_or_create` takes `f_name: Option<String>, l_name: Option<String>`. Queue entries have a single `name: String` field.

Split strategy (same as `bookings_post.rs`): first space separates first name from last name. If no space, entire string is first name, last name is None. Look at how `bookings_post.rs` does this and follow the same pattern.

### 9. Error enum

No new client-facing errors needed. Person::find_or_create and NewQueueBooking::into_db use existing error variants. If `find_or_create` fails, the activation still succeeds (booking just won't have person_id). Treat person linking as best-effort, not blocking.

Wait — re-read that. If email is provided and find_or_create fails, should we fail the activation? Two options:
- **Fail:** Person linking is integral to the booking. If it fails, something is wrong.
- **Best-effort:** Log the error, create booking without person_id. The enrichment path can fix it later.

Recommendation: **Fail.** `find_or_create` only fails on DB errors, not on bad input. A DB error during activation should surface, not be silently swallowed. The booking and queue entry updates are in a transaction — they roll back cleanly.

### 10. Tests

- Unit test: `NewQueueBooking::into_db` returns a Booking with `booking_source=Queue`, `status=Confirmed`, correct start_at/end_at, correct price_cents. No capacity check exercised.
- Unit test: `NewQueueBooking` with `guest_email=None` and `person_id=None` — creates booking with both fields NULL.
- Unit test: `NewQueueBooking` with `guest_email=Some(...)` and `person_id=Some(...)` — creates booking with both populated.
- Verify `QueueEntry::set_booking_id` updates correctly.
- Existing queue entry tests must still pass.
- Existing booking tests must still pass.
- Existing workflow integration tests must still pass.

### 11. Build pipeline

```
cd server && cargo xtask build-all
```

Must pass. api-contracts changed (QueueEntryDto, CreateQueueEntryBody).

### 12. Review

Run `/review-rs` on all changed files.

## What NOT to do

- Do not change the activation endpoint response envelope — command center expects QueueEntryDto. Phase 3 updates the response.
- Do not modify command center code.
- Do not build `Booking::enrich_guest_identity()` — that's Phase 5.
- Do not build parent waiver before child waiver — that's independent work.
- Do not add booking_source filtering to any list/query endpoints — that's Phase 4.

## Done criteria

- Migration runs cleanly against local DB
- `NewQueueBooking::into_db()` creates a booking with source=Queue, status=Confirmed, no capacity check
- `queue_entry_activate.rs` creates a booking at activation and parents the workflow to the booking
- Queue entry gets `booking_id` set after activation
- Call-ahead confirmation carries email to queue_entry row
- `cargo xtask build-all` passes
- All existing tests pass
- New tests cover NewQueueBooking creation (with and without email/person)
- `/review-rs` passes on changed files
