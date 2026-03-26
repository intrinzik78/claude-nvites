# DISPATCH: Waiver system design decisions from architecture review

**Date:** 2026-03-15
**From:** dev session (architecture review of waiver system complexity)
**To:** server, surface-command-center, crosscutting (next sessions)
**Priority:** High — captures decisions that simplify the waiver system and correct prior design assumptions

---

## Background

After multiple waiver sessions with repeated breakage and rework, we performed a full forensic analysis of the waiver system: 5,000+ lines of waiver code, 23 dispatches/archives, 7 migrations, and the full integration surface. The goal was to identify why the system felt fragile and what would let us confidently finish it.

**Root cause identified:** The system's complexity is proportionate to its requirements (ESIGN compliance, minor/guardian support, staff acceptance, paper waivers, document integrity, workflow integration). The fragility comes from two sources:

1. `waiver.rs` is a 2,267-line god file mixing state machine, queries, hashing, audit trail, and verification. Every session touches it, every change risks breaking something else. (Addressed by DISPATCH_WAIVER_DECOMPOSITION.md.)
2. Design assumptions about auto-advancement and split booking integration were incorrect, leading to over-engineered integration code.

This dispatch captures the design decisions that simplify the system going forward.

---

## Decision 1: Waiver gate advancement is always manual

**Confidence: 100% (user decision)**

Auto-advance on waiver count was a design mistake. Waiver records must be inspected by staff before advancing past a waiver gate. This applies to ALL workflow instances — primary, split parent, and split children alike.

**Implications:**
- `sync_waiver_count()` in `checkin_service.rs` should update the `waiver_count` context field for display purposes only. It must NEVER call `WorkflowEngine::normalize()` on any instance. The count is informational — the operator inspects waivers and manually advances.
- This eliminates the `is_active_primary()` filtering question entirely. All active instances for a booking should receive the count update. The only question is "does the UI show the count?" — not "should the engine auto-advance?"
- The normalize guard sites identified in DISPATCH_SPLIT_NORMALIZE_GUARD.md remain relevant for non-waiver auto-steps (timer-based, payment gates) on split children. That dispatch is not superseded — it addresses a different concern (split children + any gate) vs. this one (waiver gates + all instances).

**What to change:**
- `checkin_service.rs` `sync_waiver_count()`: Remove the normalize branch entirely. Update context on all active instances (drop the `is_active_primary()` filter), but never normalize. This is a simplification, not a new feature.

**Workflow definition verification (MANDATORY before making code changes):**

The production checkin workflow definition is seeded in `server/migrations/20260227120000_replace_checkin_workflow.sql`. As of 2026-03-15, the waiver step (`ci_waivers`) uses `"type": "gate"` — gates are manual-only and `normalize()` never auto-advances them. This means no workflow definition data change should be needed.

However, the agent MUST verify the following with high confidence before proceeding:
1. That `ci_waivers` is still `"type": "gate"` (not `"type": "auto"`) in the current migration chain. Check all migrations that touch `workflow_definition` for any subsequent changes.
2. That no other seeded or runtime-created workflow definition uses `waiver_count` in an `auto`-type step condition.
3. That `normalize()` in `engine.rs` truly skips gate steps — read the code, confirm the `StepType::Auto` match arm is the only path that advances.
4. That the integration test `test_sync_waiver_count` in `workflow/integration_tests.rs` creates a test-only auto-condition step (not reflective of production data) and should be updated to match the new manual-only decision.

**If any of the above cannot be verified with high confidence, STOP and state what could not be confirmed.** Do not proceed with code changes on assumptions about the workflow engine's behavior.

**What this kills:**
- The race condition between `sync_waiver_count` normalize and API handler EpochGuard serialization — gone, because sync no longer normalizes.
- The "per-group waiver attribution" dispatch concept — unnecessary, because auto-advance doesn't happen.
- The `test_sync_waiver_count` test that proves auto-advance on waiver count — this test should be rewritten to verify that context updates happen but no advancement occurs.

---

## Decision 2: Splits are cosmetic/operational, not data model concerns

**Confidence: 100% on cosmetic nature, 70% on data storage implications (user's stated confidence)**

Splitting groups is an operational tool so that arrived guests don't wait on unarrived guests. Splits are not a data storage or group tracking flow. At close of day, ops and execs would never look at split breakdowns again. Splits could be collapsed back into the parent booking if desired.

**Implications:**
- Waivers correctly attach to the booking as a whole, not to individual split groups. The current schema (`waiver_collection.booking_id`) is correct.
- The "group-level waiver breakdown for split bookings" dispatch (handoff 2026-03-15) was solving the wrong problem. Per-group waiver attribution is unnecessary. The command center should show booking-level waiver coverage ("8 of 10 waivers accepted") and the operator knows which guests are in which group because they're physically present.
- The `WaiverCollectionSummaryDto` is correctly scoped to the booking. No per-instance waiver summary needed.

**Open question:** Should we formally mark the group-level breakdown dispatch as superseded? It lives in `handoffs/crosscutting/2026-03-15-waiver-group-aggregate.md` (or similar). Recommend adding a note at the top: "Superseded by DISPATCH_WAIVER_DESIGN_DECISIONS.md Decision 2 — splits are cosmetic, waivers are booking-scoped."

---

## Decision 3: Walk-ups need waivers, and walk-ups are almost identical to bookings

**Confidence: 90% on similarity, open question on unification**

Walk-ups (promoted from queue entries) and bookings share almost every field and operational flow. They are differentiated only by:
- **Payment:** Walk-ups can never prepay. Bookings can.
- **Arrival timing:** Bookings require 12+ hours advance notice. Same-day arrivals are queue entries. Bookings are guaranteed and resource-gated on the server.

Queue entries promote to walk-ups, which need waivers. But `waiver_collection` has a `booking_id` FK — if walk-ups aren't bookings, this FK doesn't work for them.

**Open questions (do NOT resolve in next session — capture for future design):**
1. Should walk-ups be converted to bookings at promotion time? This would make the waiver FK work naturally, but "booking" semantically implies advance reservation.
2. If walk-ups remain a separate entity, should `waiver_collection.booking_id` be generalized (e.g., `entity_id` + `entity_type`, like the workflow `parent_entity_type` pattern)?
3. Is there a simpler option: walk-ups ARE bookings with a `booking_source` discriminator (e.g., `Online`, `WalkUp`, `CallAhead`)?

**Current state:** Walk-ups don't exist as a domain type yet. Queue entries exist. The promotion path (queue entry → walk-up) is not yet built. This is a future design decision, not a current blocker.

**Warning:** Do not build the walk-up → waiver path until this FK question is resolved. It's a schema-level decision that affects api-contracts (contract change).

---

## Decision 4: waiver.rs decomposition is unconditionally correct

**Confidence: 100%**

The 2,267-line god file is the primary source of waiver system fragility. Decomposition is independent of all other design questions (splits, walk-ups, auto-advance). It's purely organizational — same code, same behavior, smaller files, clearer responsibilities.

See DISPATCH_WAIVER_DECOMPOSITION.md for the decomposition plan.

---

## What existing dispatches are affected

| Dispatch | Status |
|----------|--------|
| DISPATCH_SPLIT_MANUAL_ADVANCE.md | **Partially superseded.** Its scope was split children only. Decision 1 broadens: waiver gates are manual for ALL instances. The dispatch's UX opportunity (ready badge) remains valid. |
| DISPATCH_SPLIT_NORMALIZE_GUARD.md | **Still valid.** The 3 guard sites are about split children + any gate type (timers, payment). Decision 1 only removes normalize from the waiver sync path specifically. |
| DISPATCH_WAIVER_ACCEPT_GROUP_FLASH.md | **Still valid.** The UI flash bug is independent of these decisions. |
| Handoff: waiver group-level breakdown | **Superseded by Decision 2.** Splits are cosmetic; per-group waiver attribution is unnecessary. |

---

## Files to load for implementation

When picking up the sync_waiver_count simplification (Decision 1):
- `server/api/src/types/workflow/checkin_service.rs` — sync_waiver_count function
- `server/api/src/types/workflow/instance.rs` — is_active_primary() definition
- `server/api/src/types/workflow/monitor.rs` — normalize guard context (DISPATCH_SPLIT_NORMALIZE_GUARD.md)
- `docs/DISPATCH_SPLIT_NORMALIZE_GUARD.md` — the 3 guard sites
- `docs/DISPATCH_SPLIT_MANUAL_ADVANCE.md` — prior context

When picking up walk-up design (Decision 3, future):
- `server/api/src/types/queue_entries/queue_entry.rs` — current queue entry type
- `server/api/src/types/queue_entries/queue_pending.rs` — promotion flow
- `server/api/src/types/bookings/booking.rs` — booking type for comparison
- `server/api/src/types/waivers/waiver_collection.rs` — the booking_id FK
- `docs/Architecture.md` — principles and mental model
