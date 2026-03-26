# Crosscutting: Queue Call-Ahead Arrival Time

**Date:** 2026-03-11
**Origin:** surface-website — `/queue` call-ahead form
**Scope:** api-contracts, server, surface-website, surface-command-center (display only)

---

## Problem

The public `/queue` call-ahead form collects name, email, party size, and optional notes. It does not collect an estimated arrival time. The `queue_entry` table already has an `expected_at TIME NULL` column (migration `20260227130000`), and the staff-only `POST /v1/queue` endpoint accepts it — but the public call-ahead path (`POST /v1/queue/call-ahead` → `queue_pending` → confirm → promote to `queue_entry`) has no support for it at any layer.

**Result:** Staff can set `expected_at` when creating walk-up entries via the command center. Customers calling ahead cannot communicate when they plan to arrive. The command center displays `expected_at` on queue entries, but it's always NULL for call-ahead guests.

---

## Current State: What Exists

### Operating Hours Infrastructure (fully built, read-only)

**Tables:**

| Table | Key Columns | Data |
|-------|------------|------|
| `booking_operating_hours` | `day_of_week` (0=Sun–6=Sat), `open_time`, `close_time` | 7 rows seeded — Sun/Sat 10:00–18:00, Mon–Fri 09:00–17:00, Fri 09:00–20:00 |
| `booking_schedule_override` | `override_date`, `is_closed`, `open_time`, `close_time`, `reason` | 0 rows (empty — no blackouts configured) |

**Types (server-internal only, NOT in api-contracts):**
- `OperatingHours` — `::all()`, `::by_day(dow)`
- `ScheduleOverride` — `::by_date(date)`, `::by_range(start, end)`

**Business logic:**
- `availability_get.rs` — `GET /v1/bookings/availability?product_id=X&date=Y` (public, no auth). Resolves operating window (override-first → weekly fallback), generates time slots based on product duration and resource capacity. Returns `Vec<TimeSlot>` in UTC.
- `bookings_post.rs` — validates booking start time falls within operating window.

**Timezone:**
- `TIMEZONE_OFFSET` in `.env` → `utc_offset_minutes: i32` on `Settings` (env-only, not DB-persisted per DEC-020).
- Default: `-300` (UTC-5, Central/CDT).
- `availability_get.rs` and `bookings_post.rs` both use it to convert between local and UTC.
- Operating hours in DB are stored as **local time** (not UTC). The availability engine converts to UTC for API responses.

### What Does NOT Exist

1. **No public API to read operating hours.** `OperatingHours` and `ScheduleOverride` are server-internal types — not in `api-contracts`, not exposed via any GET endpoint. The only public consumer is `GET /v1/bookings/availability`, which uses them internally to compute slots.

2. **No `expected_at` on `CallAheadBody`.** The api-contract type has 4 fields: `name`, `email`, `party_size`, `notes`.

3. **No `expected_at` on `queue_pending` table or type.** The staging table that holds unconfirmed call-ahead submissions doesn't have the column.

4. **No management endpoints for hours/overrides.** Hours are managed via Workbench (direct DB), not through the API.

---

## Proposed Solution

### Phase 1: Pipeline (server + api-contracts)

Wire `expected_at` through the call-ahead flow so it persists from submission to `queue_entry`:

| Layer | Change |
|-------|--------|
| **Migration** | `ALTER TABLE queue_pending ADD COLUMN expected_at TIME NULL AFTER notes;` |
| **api-contracts** | Add `pub expected_at: Option<NaiveTime>` to `CallAheadBody` |
| **QueuePending type** | Add field to struct, `DatabaseHelper`, `From` impl, getter. Add to `COLS`. Add parameter to `upsert()` (INSERT + ON DUPLICATE KEY UPDATE). |
| **QueuePending::confirm()** | Include `expected_at` in the INSERT into `queue_entry` |
| **call_ahead_post.rs** | Pass `body.expected_at` through to `QueuePending::upsert()` |
| **Build pipeline** | `cargo xtask build-all` → regenerates `openapi.json` → `sdk-ts` types updated |

**Confidence: HIGH.** Every change is mechanical — adding an optional field through an existing pipeline. No new endpoints, no new tables, no architectural decisions. The column already exists on the destination table (`queue_entry.expected_at`).

### Phase 2: New Endpoint — `GET /v1/queue/hours` (public)

Expose operating hours to surfaces so the frontend can offer time selection constrained to real business hours. This is a **new public endpoint** that returns today's (or a given date's) operating window, respecting overrides.

| Layer | Change |
|-------|--------|
| **api-contracts** | New `OperatingWindow` DTO: `{ open_time: NaiveTime, close_time: NaiveTime, is_closed: bool }` |
| **Handler** | `GET /v1/queue/hours?date=YYYY-MM-DD` — public, no auth. Override-first → weekly fallback (same logic as `availability_get.rs` lines 48–67, extracted to shared helper). |
| **Route registration** | Add to route collection |
| **Build pipeline** | Regenerate OpenAPI + SDK |

**Why a dedicated endpoint instead of reusing `/v1/bookings/availability`?**
- Availability requires `product_id` and returns capacity-aware booking slots. Queue call-ahead has no product — it's "when are you showing up," not "what time slot can I book."
- The queue form needs operating window boundaries (open/close), not slot granularity.
- Keeping them separate avoids coupling queue UX to booking product configuration.

**Confidence: HIGH.** The data and query methods already exist (`OperatingHours::by_day`, `ScheduleOverride::by_date`). This is a thin read endpoint over existing infrastructure. The override-first resolution logic is already proven in `availability_get.rs`.

### Phase 3: Frontend — time selector on `/queue` form (surface-website)

| Layer | Change |
|-------|--------|
| **+page.server.ts** | On GET: call `GET /v1/queue/hours?date=today` to get operating window. Return `open_time`, `close_time`, `is_closed` to the page. On POST: parse `expected_at` from form data, normalize to `HH:MM:SS`, pass to SDK. |
| **CallAheadForm.svelte** | Add optional time selector. Generate 30-minute increment options between open and close times. Display in 12-hour AM/PM format. If venue is closed today, show message, disable form or hide time field. |
| **Props** | Add `expected_at?: string` for form repopulation on error. Add `open_time`, `close_time`, `is_closed` for selector generation. |
| **Label** | "Estimated Arrival (Central Time)" — hardcoded timezone label for v1 |

**Confidence: MEDIUM.** The selector UX has design choices (30-min vs 15-min increments, "flexible" option, what to show if venue is closed). These are solvable but need deliberate decisions.

### Phase 4 (deferred): surface-command-center display

Not in scope for this work. The command center already reads and displays `expected_at` from `QueueEntryDto`. Once Phase 1 lands, call-ahead entries will have the value populated and it will appear automatically.

### Phase 5 (deferred): Timezone label from config

The "Central Time" label is hardcoded in Phase 3. A future crosscutting change could expose a human-readable timezone name (e.g., `TIMEZONE_LABEL=Central Time` in `.env` → available to surfaces). This affects every surface that displays times and should not be solved in a queue-specific PR.

### Phase 6 (deferred): Link-click email verification

Separate feature. Different endpoint, URL-safe token scheme, email template changes. No interaction with arrival time.

---

## Red Team

### RT-1: `deny_unknown_fields` deployment ordering — CRITICAL
`CallAheadBody` has `#[serde(deny_unknown_fields)]`. If the website frontend deploys before the server, the new frontend sends `expected_at` to an old server → **entire form breaks** (400 on every submission, not just the new field).

**Mitigation:** Server must deploy before or atomically with frontend. Document in deploy notes. The reverse direction is safe — old frontend against new server just sends `None`.

### RT-2: Time format mismatch — HIGH
HTML `<input type="time">` (or a custom select) produces `HH:MM`. Chrono `NaiveTime` serde expects `HH:MM:SS`. Raw passthrough → deserialization failure → 400 error.

**Mitigation:** Form action in `+page.server.ts` normalizes `HH:MM` → `HH:MM:SS` before passing to SDK. This is the BFF layer's job — it already does type conversion for `party_size`.

### RT-3: Upsert must update `expected_at` — HIGH
`QueuePending::upsert()` uses `ON DUPLICATE KEY UPDATE`. If `expected_at` is omitted from the UPDATE clause, resubmission with a different time (or no time) keeps stale data.

**Mitigation:** Add `expected_at = VALUES(expected_at)` to the UPDATE clause. Explicit in the plan.

### RT-4: `confirm()` must carry `expected_at` — HIGH (silent failure)
If `QueuePending::confirm()` doesn't include `expected_at` in the INSERT into `queue_entry`, the field silently drops to NULL. No error, no signal — the whole feature appears to work but doesn't.

**Mitigation:** Explicit in the plan. Test: after confirm, SELECT the new `queue_entry` row and assert `expected_at` matches the pending record.

### RT-5: Operating hours not seeded via migration
The 7 rows in `booking_operating_hours` exist in the live DB but there's no seed migration — they were inserted via Workbench. If someone runs migrations on a fresh database, the table is empty and `GET /v1/queue/hours` returns "closed" for every day.

**Mitigation:** Not a regression (same state as today). But Phase 2 makes this more visible. Consider a seed migration for operating hours or handle empty hours gracefully in the endpoint (return a clear "hours not configured" vs. "closed").

### RT-6: Schedule overrides table is empty
No blackout dates are configured. The system supports them but none are entered. `GET /v1/queue/hours` will always fall through to weekly hours.

**Assessment:** Working as designed. The override path is tested in `availability_get.rs`. When overrides are added (via Workbench), they'll take effect automatically. No action needed.

### RT-7: Timezone label is a lie during DST transitions
"Central Time" can be CST (UTC-6) or CDT (UTC-5). The `.env` has a static offset (`-300` = UTC-5). If the offset isn't updated for DST, the label is technically wrong for part of the year, and more importantly, the server computes the wrong local date/time.

**Assessment:** This is a pre-existing system-wide issue (affects bookings, queue date computation, availability). Not introduced by this work, not solvable here. The `.env` offset is the single source of truth — surfaces should reference it, not invent their own. Noted for Phase 5 / crosscutting.

### RT-8: What if the venue is closed today?
Customer loads `/queue`, form action fetches hours, venue is closed (override or no hours for today's DOW). What should the form do?

**Recommendation:** Show the form but disable/hide the time selector. The queue is "call-ahead" — the customer might be calling ahead for tomorrow or might still want to get in line even if hours show closed (early closure override but venue still processing guests). The name/email/party-size form should remain functional. Time selection becomes "not applicable today" rather than blocking the entire flow. Exact UX is a surface-website decision.

### RT-9: No server-side validation of `expected_at` against hours
The staff endpoint (`POST /v1/queue`) doesn't validate `expected_at` against operating hours either. Should the call-ahead path?

**Assessment:** No. Parity with existing behavior. `expected_at` is an *estimate* — "I think I'll be there around 2pm." Rejecting it because the venue closes at 5pm and the customer said 5:30pm would be hostile UX. The value is informational, not a booking commitment. If validation is wanted, add it to both paths simultaneously in a future PR.

### RT-10: Reuse of override-first resolution logic
Phase 2 duplicates the override-first → weekly-fallback logic from `availability_get.rs` lines 48–67. Two copies = drift risk.

**Mitigation:** Extract to a shared helper function (e.g., `resolve_operating_window(date, db) -> Result<Option<(NaiveTime, NaiveTime)>>`) used by both `availability_get.rs` and the new `queue/hours` endpoint. This is a small refactor with clear boundaries.

---

## Phasing Summary

| Phase | Scope | Depends On | Confidence |
|-------|-------|-----------|------------|
| 1 | Pipeline: `expected_at` through call-ahead flow | — | HIGH |
| 2 | New endpoint: `GET /v1/queue/hours` | — | HIGH |
| 3 | Frontend: time selector on `/queue` form | Phase 1 + 2 | MEDIUM |
| 4 | Command center display | Phase 1 (may already work) | — (deferred) |
| 5 | Timezone label from config | — | — (deferred, crosscutting) |
| 6 | Link-click email verification | — | — (deferred, separate feature) |

Phases 1 and 2 are independent and can be built in parallel.
Phase 3 requires both 1 and 2 to be merged.
Phases 4–6 are deferred and tracked separately.

---

## Files Touched (Phases 1–3)

### Phase 1
- `server/migrations/YYYYMMDDHHMMSS_queue_pending_add_expected_at.sql` (new)
- `api-contracts/src/queue_entries.rs` (contract change)
- `server/api/src/types/queue_entries/queue_pending.rs`
- `server/api/src/api/queue_entries/call_ahead_post.rs`

### Phase 2
- `api-contracts/src/queue_entries.rs` or new file (new DTO)
- `server/api/src/api/queue_entries/queue_hours_get.rs` (new handler)
- `server/api/src/api/queue_entries/mod.rs` (register handler)
- `server/api/src/types/route_collection.rs` (route)
- Shared helper extracted from `server/api/src/api/bookings/availability_get.rs`

### Phase 3
- `surface-website/src/routes/(public)/queue/+page.server.ts`
- `surface-website/src/routes/(public)/queue/_components/CallAheadForm.svelte`
- `sdk-ts/` (regenerated)

### Contract changes (requires justification per build gate)
- `CallAheadBody` gains `expected_at: Option<NaiveTime>` — completing an incomplete pipeline; the field already exists on the destination table and the staff create body.
- New `OperatingWindow` DTO — exposes existing internal data to surfaces for hours-aware UX.


### Unsaid thoughts shared a session end
The extract-shared-helper question (RT-10) is the most architecturally consequential piece. The operating-window resolution logic in availability_get.rs
is currently inline. When Phase 2 adds a second consumer, the temptation will be to copy-paste. Whoever picks this up on dev should extract first, then
build the new endpoint on top — not the reverse. Refactor-then-extend is easier to review than extend-then-refactor.

Operating hours aren't seeded via migration (RT-5). They exist in your local DB and presumably production, but a fresh sqlx migrate run produces an empty
booking_operating_hours table. This has been silently fine because the only consumer (availability_get.rs) gracefully returns empty slots. But Phase 2
makes "no hours configured" a user-visible state on the queue page. The crosscutting session should decide: seed migration, or graceful "hours
unavailable" UX, or both.

The console.error on line 33 of the queue +page.server.ts should become tracing or structured logging when this file is touched. Not a blocker, just
opportunistic cleanup that aligns with DEC-118.

One thing I didn't put in the document: the CallAheadBody contract change and the new OperatingWindow DTO are two separate contract changes. They could
land in separate PRs if you want to keep the blast radius tight — Phase 1 (pipeline) is purely additive and low-risk; Phase 2 (new endpoint + DTO) is
where the actual design decisions live. Splitting them means Phase 1 can merge fast while Phase 2 gets more scrutiny.
