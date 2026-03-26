# DISPATCH: Walk-up / booking convergence — design decision needed

**Date:** 2026-03-15
**From:** dev session (waiver architecture review)
**To:** dev (clean session, design-first)
**Priority:** High — blocks walk-up waiver attachment and queue→walk-up promotion

---

## Background

During a forensic review of the waiver system, we identified that walk-ups and bookings are nearly identical domain entities differentiated only by payment and arrival timing. This has immediate implications for the waiver system (FK dependency) and longer-term implications for the data model.

This dispatch captures the full reasoning chain so a clean session can pick it up without re-deriving.

## The problem

Waivers must attach to walk-up groups. The current `waiver_collection` table has a `booking_id` FK. If walk-ups are not bookings, this FK doesn't work for them. The walk-up domain type does not exist yet — queue entries exist and promote to walk-ups, but the promotion path is not built.

## What we know (verified)

**Walk-ups and bookings share almost every field and operational flow.** Confidence: 90%.

Differences (verified against `queue_entry.rs` and `booking.rs`):
- **Payment:** Walk-ups can never prepay. Bookings can.
- **Arrival timing:** Bookings require 12+ hours advance notice. Same-day arrivals are queue entries that the facility can deny if booked out. Bookings are guaranteed and resource-gated on the server.
- **Product binding:** Queue entries optionally bind product at activation. Bookings require product at creation.
- **Person binding:** Queue entries optionally bind person. Bookings require person.
- **Lifespan:** Queue entries are day-of, physically deletable (DEC-074). Bookings are historical, never deleted.
- **Time precision:** Queue entries have date + optional floor-of-hour hint. Bookings have exact UTC start/end.

**Both feed into the same workflow engine.** The workflow `parent_entity_type` discriminator already handles this: "booking" or "queue_entry". The checkin workflow is shared.

**Waivers are booking-scoped.** `waiver_collection.booking_id` is a direct FK to `booking.id`. The waiver system is entirely split-ignorant and booking-ignorant beyond this FK.

## Three options identified

### Option 1: Convert walk-ups to bookings at promotion time

Queue entry confirms → system creates a Booking row with walk-up-specific defaults (no prepayment, same-day start, etc.). Waivers attach via existing `booking_id` FK.

**Pros:** Zero waiver schema change. Walk-ups get all booking infrastructure (UUID, history, status machine) for free. Single entity for ops/reporting.
**Cons:** "Booking" semantically implies advance reservation. A walk-up booking with no prepayment and same-day timing is a conceptual stretch. Booking creation currently involves resource/capacity gating — walk-ups would need to bypass or adapt this.

### Option 2: Generalize the FK

Change `waiver_collection.booking_id` to `entity_id` + `entity_type` (like the workflow `parent_entity_type` pattern). Walk-ups become their own domain type with their own table.

**Pros:** Clean separation. Each entity type owns its semantics.
**Cons:** Polymorphic FK is a schema-level change affecting api-contracts (contract change). Loses referential integrity (no FK constraint possible on a polymorphic column). Adds complexity to every waiver query that joins through `waiver_collection`.

### Option 3: Walk-ups ARE bookings with a `booking_source` discriminator

Add a `booking_source` enum (e.g., `Online`, `WalkUp`, `CallAhead`) to the booking table. Walk-ups are bookings created through a different channel with different defaults. Payment, timing, and capacity rules vary by source.

**Pros:** Single table, single FK, single query path. Reporting is unified. The discriminator makes the channel explicit without splitting the type. Aligns with the user's observation: "they are the same thing, only differentiated by payment and arrival methods."
**Cons:** Booking validation must branch on source (walk-ups skip capacity gating, don't require prepayment, don't require 12h advance). Risk of conditional logic accumulating in booking handlers.

**Current lean: Option 3.** Confidence: 70%. Not verified against booking schema constraints or handler validation logic.

## What to do in the next session

This is a **design session, not a coding session.** Follow the pattern that worked for the waiver architecture review:

1. **Load context:**
   - This dispatch
   - `server/api/src/types/bookings/booking.rs` — full booking type, all fields, all methods
   - `server/api/src/types/queue_entries/queue_entry.rs` — full queue entry type
   - `server/api/src/types/queue_entries/queue_pending.rs` — promotion flow (confirm → queue entry)
   - `server/api/src/types/waivers/waiver_collection.rs` — the booking_id FK
   - `api-contracts/src/bookings.rs` — booking DTOs
   - `api-contracts/src/queue_entries.rs` — queue entry DTOs
   - `docs/Architecture.md` — principles
   - `docs/DECISIONS.md` — DEC-074 (queue entry deletion), any booking-related DECs

2. **Verify Option 3 feasibility:**
   - Can a booking be created without capacity/resource gating? What validation would need to branch?
   - What fields on booking are required that a walk-up wouldn't have at creation time? (e.g., `start_at`, `end_at`, `price_cents`)
   - Would the booking status machine work for walk-ups? (Pending→Confirmed makes sense? Or should walk-ups skip to Confirmed?)
   - Does the workflow `parent_entity_type` need to change if walk-ups become bookings?

3. **Red-team all three options.** Present tradeoffs to the user. Assign confidence levels. The user welcomes reasoned pushback.

4. **If a decision is reached:** Write it as a dispatch with implementation steps. Do not code in the design session.

## Hard constraints

- **Do not build the walk-up → waiver path until this FK question is resolved.** It's a schema-level decision that affects api-contracts (contract change).
- **Do not resolve this in a session focused on other work.** This deserves dedicated reasoning time.
- Any option that touches `waiver_collection` schema is a migration + contract change. Plan accordingly.

## Decision history

- DEC-074: Queue entries are ephemeral, physically deletable
- DEC-128: Consumer-facing paths use UUID, staff paths use ID
- DEC-134: Waiver gate advancement is always manual
- Walk-ups don't exist as a domain type yet — this is greenfield design
