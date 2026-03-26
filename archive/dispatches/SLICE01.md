# SLICE 01: Schema + Server Types (Booking Source Convergence)

**Date:** 2026-03-16
**From:** dev design session
**To:** server worktree
**Prerequisite:** None. This slice is purely additive — no behavioral changes.

---

## Goal

Add `booking_source` discriminator to the booking table and Rust types. All existing bookings default to `Booking`. No creation paths change. No handlers change. The system behaves identically after this slice — it just has a new column and enum ready for Phase 2.

## Reference

- `docs/FEASIBILITY_WALKUP_BOOKING_CONVERGENCE.md` — full design context (Sections 4a–4d)
- `docs/RUST_STYLE_GUIDE.md` — code conventions

## Tasks

### 1. Migration

Create a new migration in `server/migrations/`. Contents:

```sql
-- Booking source lookup table (DEC-023 pattern)
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

-- Align person_id constraint with Rust type (already Option<i64>)
ALTER TABLE booking
  MODIFY COLUMN person_id int DEFAULT NULL;
```

**Notes:**
- `DEFAULT 1` means all existing rows get `booking_source_id = 1` (Booking). No backfill.
- `guest_email` nullable prepares for Phase 2 (queue-sourced bookings without email).
- `person_id` nullable aligns the DB constraint with the Rust type which is already `Option<i64>`.

### 2. BookingSource enum in api-contracts

**File:** `api-contracts/src/bookings.rs`

Add new enum:

```rust
#[repr(u8)]
#[derive(Copy, Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
#[cfg_attr(feature = "openapi", derive(utoipa::ToSchema))]
pub enum BookingSource {
    Booking = 1,
    Queue = 2,
}

impl BookingSource {
    pub fn from_u8(value: u8) -> Option<Self> {
        Some(match value {
            1 => Self::Booking,
            2 => Self::Queue,
            _ => return None,
        })
    }
}

impl fmt::Display for BookingSource {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let s = match self {
            Self::Booking => "booking",
            Self::Queue => "queue",
        };
        f.write_str(s)
    }
}
```

Add unit tests: `from_u8` bounds check, `Display` all variants, serde roundtrip, reject unknown.

### 3. BookingDto update

**File:** `api-contracts/src/bookings.rs`

Update `BookingDto`:
- Add `pub booking_source: BookingSource`
- Change `pub guest_email: String` → `pub guest_email: Option<String>`

**This is a contract change.** Existing consumers that read `guest_email` must handle `Option`. Surface-website portal doesn't display email directly — no breakage expected. Verify after build.

### 4. Booking type changes

**File:** `server/api/src/types/bookings/booking.rs`

- Add `booking_source: BookingSource` field to `Booking` struct
- Change `guest_email: String` → `guest_email: Option<String>`
- Add getter: `pub fn booking_source(&self) -> BookingSource`
- Update getter: `pub fn guest_email(&self) -> Option<&str>` (was `&str`)
- Update `DatabaseHelper`: add `booking_source_id: i8`, change `guest_email` to `Option<String>`
- Update `BOOKING_COLS` constant: add `booking_source_id`
- Update `DatabaseHelper::transform()`: convert `booking_source_id` → `BookingSource` via `from_u8`
- Update `From<&Booking> for BookingDto`: include `booking_source`, pass `guest_email` as `Option`

### 5. Error enum

**File:** `server/api/src/enums/error.rs`

Add variant: `BookingSourceOutOfBounds(u8)` — for invalid `booking_source_id` from DB.
**Not client-facing.** Falls through to `None` in `to_api_error_message()` → generic 500. An invalid discriminant from the DB is data corruption, not a user error. Follows the same pattern as `BookingStatusOutOfBounds`. Do NOT add a client-facing mapping or bump `EXPECTED_CLIENT_FACING_COUNT`.

### 6. NewBooking update

**File:** `server/api/src/types/bookings/booking.rs`

Update `NewBooking::into_db()` INSERT statement to include `booking_source_id = 1` (Booking). No other changes to the online booking creation path.

### 7. Downstream fixups from nullable guest_email

The `guest_email` type change from `String` to `Option<String>` has three downstream impacts:

**a. `bookings_post.rs` — send_confirmation.** `booking.guest_email()` returns `Option<&str>` now. The online path always has email (validated at handler boundary), but the code passes `guest_email()` directly to `postmark::types::Email.to_address: &'a str`. Fix: unwrap with early return via `Error::BookingGuestEmailInvalid` if None. No panics.

**b. `NewBooking::into_db()` — Booking construction.** Line ~487 sets `guest_email: self.guest_email`. Since `Booking.guest_email` is now `Option<String>`, this becomes `guest_email: Some(self.guest_email)`. `NewBooking.guest_email` stays `String` (online bookings always require email).

**c. Tests.** ~7 test sites construct `DatabaseHelper` with `guest_email: String::from(...)` → change to `Some(String::from(...))`. Assertions on `booking.guest_email()` and `dto.guest_email` assert against `Option`/`Some(...)`.

### 8. Compile + existing tests

All existing booking-related tests must pass with the above fixups. Integration test INSERTs don't specify `booking_source_id` — `DEFAULT 1` covers them. `guest_email` is always provided in integration test INSERTs — no changes needed there.

`Booking::by_email()` query semantics are correct as-is: `WHERE guest_email = ?` naturally excludes NULLs. Queue-sourced bookings without email won't appear in email lookups. Correct behavior.

### 9. Build pipeline

```
cd server && cargo xtask build-all
```

Must pass. This verifies: api-contracts → schema-emitter → dist/openapi.json → server → sdk-ts types.

### 10. Review

Run `/review-rs` on all changed files before considering this slice complete.

## What NOT to do

- Do not create `NewQueueBooking` — that's Phase 2.
- Do not modify `queue_entry_activate.rs` — that's Phase 2.
- Do not modify any command center code — that's Phase 3/4.
- Do not add `queue_entry.booking_id` column — that's Phase 2.
- Do not add `enrich_guest_identity()` — that's Phase 5.

## Done criteria

- Migration runs cleanly against local DB
- `cargo xtask build-all` passes
- All existing tests pass (with updated test helpers for nullable guest_email)
- New BookingSource enum has unit tests (from_u8, Display, serde roundtrip)
- `/review-rs` passes on changed files
- `dist/openapi.json` includes `BookingSource` schema and updated `BookingDto`
