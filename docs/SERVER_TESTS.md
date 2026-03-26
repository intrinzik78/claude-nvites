# DISPATCH: Integration Test — Queue→Booking→Workflow→Waiver Chain

**Date:** 2026-03-17
**From:** dev orchestration session
**To:** server worktree
**Priority:** Medium — no production risk (system not live), but validates the convergence end-to-end

---

## Gap

The walk-up/booking convergence (SLICE 01–04) is implemented and individually tested. Unit tests cover:
- `NewQueueBooking::into_db()` — booking created with source=Queue, status=Confirmed, no capacity check
- `BookingSource` enum — from_u8, serde roundtrip, bounds checking
- Workflow instance filtering by booking_source — subquery join correctness

What's missing: **an integration test that walks the full cross-boundary flow.** No test exercises:

1. Create a queue entry (with optional email)
2. Activate it → verify a booking is created with `booking_source=Queue`, `status=Confirmed`
3. Verify `queue_entry.booking_id` is set
4. Verify the checkin workflow is parented to `"booking"` with the booking's UUID (not `"queue_entry"` with the entry's ID)
5. Verify `waiver_collection` can be created against the booking's ID
6. Verify person linkage when email is available vs. NULL when not

This is the kind of flow where individual pieces pass but the seams between them break silently.

## Reasoning

The activation handler (`queue_entry_activate.rs`) does 5 things in a transaction: resolve person, create booking, update queue entry status, link booking_id, then create a workflow. A regression in any step's ordering or data passing would only surface in production. The existing workflow integration tests (`integration_tests.rs`) already test against real MySQL and have the infrastructure for this.

## Proposed Solution

Add to `server/api/src/types/workflow/integration_tests.rs` (or a new file if the god-file threshold is a concern):

**Test 1: `queue_activation_creates_booking_and_workflow`**
- Insert a queue entry with email
- Call the activation logic (or replicate the handler's steps against the DB)
- Assert: booking exists with `booking_source_id=2`, `booking_status_id=2` (Confirmed), correct product_id, guest_name from queue entry, guest_email from queue entry email, person_id set
- Assert: queue entry has `booking_id` pointing to the new booking
- Assert: workflow instance exists with `parent_entity_type="booking"`, `parent_entity_id=booking.uuid`

**Test 2: `queue_activation_without_email`**
- Insert a queue entry without email
- Activate
- Assert: booking has `guest_email=NULL`, `person_id=NULL`
- Assert: workflow still created and parented correctly

**Test 3: `waiver_attaches_to_queue_sourced_booking`**
- Activate a queue entry → booking created
- Create a `waiver_collection` with `booking_id = booking.id`
- Assert: FK constraint satisfied, collection created successfully

**Confidence: 90%.** The test infrastructure exists. The main question is whether to call the handler's logic directly or replicate the steps — calling the handler requires an Actix test harness, replicating the steps is simpler but tests the seams less perfectly. Replicating is probably the right tradeoff for V1.

## What NOT to do

- Do not refactor existing integration tests
- Do not add HTTP-level handler tests (Actix test harness is a larger lift)
- Do not test command center behavior — this is server-only
