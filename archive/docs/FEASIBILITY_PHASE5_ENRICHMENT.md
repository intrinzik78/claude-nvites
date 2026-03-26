# Feasibility Study: Phase 5 — Enrichment + Polish

**Date:** 2026-03-17
**Prerequisite:** Phases 1–4 complete (booking convergence shipped)
**Status:** Pre-implementation analysis

---

## Context

Queue-sourced bookings may have `guest_email = NULL` and `person_id = NULL` at creation. The progressive enrichment model says: populate when available, through natural operational touchpoints. Phase 5 builds the enrichment path.

Three work items, in priority order:
1. **Person enrichment at waiver attach** — backfill booking identity when a guest signs waivers
2. **Parent waiver before child waiver** — independent ESIGN improvement, increases organizer capture ~50% → ~85%
3. **Command center polish** — BookingSource badge, optional UI refinements

---

## 1. Person Enrichment at Waiver Attach

### How the waiver flow works today

Waivers are signed by **authenticated users** who have a person record (email required for registration). The waiver stores `signer_user_id` (FK to `person.id`), not the email directly. Three paths attach waivers to bookings:

- **Portal attach** (`portal_waivers_attach_post.rs`) — authenticated guest attaches their signed waivers to a booking via share code or UUID
- **Staff accept** (`booking_waivers_accept_post.rs`) — staff accepts pending waivers for a booking
- **Paper waiver** (`booking_waivers_paper_post.rs`) — staff records a paper waiver for a booking

All three call `sync_waiver_count(booking.uuid(), db)` after commit — the centralized workflow integration point.

### The enrichment opportunity

At **portal attach** time, we have:
- The booking (with possibly `guest_email = NULL` or populated, `person_id = NULL`)
- The authenticated user's person record (has email, name)
- The booking's `guest_email` (if set at activation from queue entry email or staff input)

**Trigger:** When a waiver is attached to a booking that has `person_id = NULL` AND the signer's email matches `booking.guest_email`, link the signer's person to the booking.

**Why email match, not first-attach-wins:** The first person to attach waivers may not be the organizer. A guest could receive the share code before the parent/organizer signs. First-attach-wins creates a race condition in the operational flow. Email match is exact and deterministic — only the person whose email matches what staff entered (or what the call-ahead captured) gets linked.

**When enrichment does NOT fire:**
- `booking.guest_email` is NULL (no email was captured at any point) — nothing to match against
- `booking.person_id` is already set (already enriched or set at activation) — idempotent guard
- Signer's email doesn't match `booking.guest_email` — not the organizer

### Known edge cases (all acceptable)

1. **Staff typo on email** — no match, no enrichment. Booking stays un-linked.
2. **Organizer uses different email than staff entered** — no match, no enrichment.
3. **Different family member registers with the organizer's email** — wrong person linked. Vanishingly rare (people don't share emails for account creation). Business impact: CRM inaccuracy, not operational failure. Waivers still signed, booking still functional.

All three fall within the ~10-15% un-enriched gap already accepted in the design session.

### Server changes

**New function** in `server/api/src/types/bookings/booking.rs`:

```rust
impl Booking {
    /// Backfill person_id for a booking where guest_email was set but person
    /// was not linked at creation time. No-op if person_id is already set.
    pub async fn enrich_person_link(
        id: i32,
        person_id: i64,
        connection: &DatabaseConnection,
    ) -> Result<()> {
        sqlx::query(
            "UPDATE booking SET person_id = ?, updated_at = CURRENT_TIMESTAMP \
             WHERE id = ? AND person_id IS NULL"
        )
        .bind(person_id)
        .bind(id)
        .execute(&connection.pool)
        .await?;
        Ok(())
    }
}
```

Key: `WHERE person_id IS NULL` — idempotent. If person_id is already set, the UPDATE matches zero rows. No error, no overwrite. Does NOT update `guest_email` — that was set at activation or by staff. The enrichment only links the person record.

**Trigger location** in `portal_waivers_attach_post.rs`:

After the existing waiver attachment logic and before `sync_waiver_count`, add:

```rust
// Enrich booking person link if email matches but person not yet linked
if booking.person_id().is_none() {
    if let Some(booking_email) = booking.guest_email() {
        if let Ok(person) = Person::by_id(user.id(), db).await {
            if person.email().eq_ignore_ascii_case(booking_email) {
                let _ = Booking::enrich_person_link(
                    booking.id(),
                    person.id(),
                    db
                ).await;
            }
        }
    }
}
```

Best-effort: if enrichment fails, waiver attachment still succeeds. The booking just stays un-linked.

**Not triggered from staff accept or paper waiver paths.** Those are staff actions — the staff member's identity is not the guest's identity.

### Blast radius

| Area | Impact |
|------|--------|
| `booking.rs` | New function (5 lines) |
| `portal_waivers_attach_post.rs` | ~10 lines added after existing logic |
| api-contracts | None |
| Command center | None |
| Website | None |

**Confidence: 92%.** The function is trivial. The trigger location is clean. Email match is deterministic. The only uncertainty: does `portal_waivers_attach_post` have access to `Person::by_id`? The exploration confirms `user.id()` is available from `AuthContext`, and `Person::by_id(id, db)` exists.

---

## 2. Parent Waiver Before Child Waiver

### Current behavior

`portal_waivers_begin_child_post.rs` allows an authenticated adult to begin a child waiver. The adult does NOT need their own completed waiver first. This means a parent can sign waivers for all their children without ever signing one themselves — the organizer's email is never captured for the booking.

### Proposed change

Before allowing a child waiver begin, verify the adult has at least one **accepted** waiver attached to the same booking. If not, return a specific error prompting them to complete their own waiver first.

### Why this matters

- **ESIGN compliance:** A parent/guardian authorizing a minor's waiver should have their own identity on file.
- **Organizer capture:** Forces the parent to sign → triggers enrichment from Item 1 → booking gets person_id. Raises capture from ~50% to ~85%.
- **Independently correct** regardless of the enrichment goal.

### Server changes

In `portal_waivers_begin_child_post.rs`, before creating the child waiver:

```rust
// Verify adult has their own accepted waiver for this booking
let adult_waivers = Waiver::find_accepted_by_signer_and_booking(
    user.id(),
    booking.id(),
    db
).await?;

if adult_waivers.is_empty() {
    return Error::WaiverAdultRequired.to_http_response();
}
```

**New query** on `Waiver`:
```rust
pub async fn find_accepted_by_signer_and_booking(
    signer_user_id: i32,
    booking_id: i32,
    db: &DatabaseConnection,
) -> Result<Vec<Waiver>> { ... }
```

Joins through `waiver_document_map` → `waiver_collection` → `booking` to find the signer's accepted waivers for a specific booking.

**New error variant:** `WaiverAdultRequired` — client-facing, mapped in `to_api_error_message()`, bumps `EXPECTED_CLIENT_FACING_COUNT`.

### Website changes

**File:** `surface-website/src/routes/(public)/waiver/+page.svelte` (or the child waiver begin route)

Handle the new error: display a message like "Please complete your own waiver before signing for a minor." This is a UX message, not a code change — the error response triggers the display.

Check the waiver page flow to see if there's already error handling for begin-child failures. If so, the new error variant gets caught by existing error display. If not, add minimal error handling.

### Blast radius

| Area | Impact |
|------|--------|
| `portal_waivers_begin_child_post.rs` | ~10 lines guard clause |
| `waiver.rs` (types) | New query function |
| `error.rs` | New variant + mapping + sentinel bump |
| `surface-website` | Error message display (minimal) |
| Command center | None |
| api-contracts | None (error is server-only) |

**Confidence: 85%.** The query path exists (waivers → collection → booking). The main uncertainty: does the child waiver begin handler have the booking context? The adult begins the child waiver from a share code or booking UUID, so yes — the booking is resolved in the handler. Need to verify the exact handler signature.

---

## 3. Command Center Polish

### BookingSource badge (optional)

Add a visual indicator on walk-up bookings in the WalkUpTrack or BookingsTrack. Options:
- Small "Walk-up" label next to the booking name
- Distinct accent color for queue-sourced bookings
- StatusBadge with new `domain="booking_source"`: booking (unlit), queue (accent)

**Effort:** Low. One component change + statusBadge.svelte.ts update.
**Priority:** Lowest. Functional without it — the tracks already separate by source.

### Portal verification

Verify that queue-sourced bookings with `person_id` set appear in the portal's "My Bookings" view. This should work automatically since `portal_bookings_get.rs` queries by `person_id`. Once enrichment (Item 1) links a person to a queue-sourced booking, it appears in their portal.

**Effort:** Verification only, not implementation. Run the portal with a test account that has both online and queue-sourced bookings.

---

## Implementation Sequence

### ~~Slice A: Server — Enrichment Function + Trigger~~
- ~~`Booking::enrich_person_link()` function~~
- ~~Trigger in `portal_waivers_attach_post.rs`~~
- ~~`cargo xtask build-all`~~
- ~~`/review-rs` + `/security`~~

### ~~Slice B: Server — Parent Waiver Guard~~
- ~~`Waiver::has_signed_adult_waiver()` query (booking-agnostic — see deviations below)~~
- ~~Guard clause in `portal_waivers_begin_child_post.rs`~~
- ~~`WaiverAdultRequired` error variant + mapping + sentinel bump (4021, count 105)~~
- ~~`cargo xtask build-all`~~
- ~~`/review-rs` + `/security`~~

### ~~Slice C: Website — Error Handling~~
- ~~Handle `WaiverAdultRequired` error in the waiver page flow~~
- ~~Display user-friendly message~~
- ~~Verify portal shows queue-sourced bookings after enrichment~~

Slices A and B are independent and can run in parallel on the server worktree. Slice C depends on B and needs a dispatch for the surface-website agent.

---

## Deviations from feasibility study (Slices A & B)

1. **Function name:** `enrich_person_link` (not `enrich_guest_identity`) — clearer about what's being linked.

2. **Parent waiver guard is booking-agnostic.** The feasibility doc proposed `find_accepted_by_signer_and_booking()` (booking-scoped), but `BeginChildWaiverBody` has no `booking_uuid` field and the handler has no booking context. Adding it would be a contract change. Shipped `has_signed_adult_waiver(signer_user_id)` instead — checks for ANY signed (Pending/Accepted) adult waiver. Achieves ESIGN goal (parent identity on file) and enrichment goal (fires at attach time regardless).

3. **Guard checks Pending OR Accepted**, not just Accepted. Requiring staff-accepted status would block the parent from starting child waivers until staff acts — bad UX for families filling out waivers at home before their visit.

4. **~5% enrichment gap accepted.** Staff-entered queue entries without email produce bookings with both `person_id = NULL` and `guest_email = NULL`. Enrichment can't fire (nothing to match). Operational flow unaffected. Closable later via first-attach-wins fallback if the data warrants it.

---

## Decisions confirmed

1. **Email-match enrichment** — the signer's email must match `booking.guest_email` for person linkage. No first-attach-wins. No name heuristics.

2. **Parent waiver guard applies to ALL bookings** — not just queue-sourced. Independently good ESIGN practice.

3. **BookingSource badge** — deferred. Functional without it.
