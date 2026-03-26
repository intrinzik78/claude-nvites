# DISPATCH: sync_waiver_count skips split child instances

**Date:** 2026-03-15
**From:** surface-command-center waiver group aggregate work
**To:** server (next session)
**Priority:** Medium — split bookings show stale waiver counts

---

## Issue

`sync_waiver_count` in `server/api/src/types/workflow/checkin_service.rs:115` only updates instances where `is_active_primary()` returns true. This method filters to `status == Active && split_from.is_none()`.

After a split, the parent instance gets status `Split` (filtered out) and the two child instances have `split_from.is_some()` (also filtered out). Neither parent nor children get their `waiver_count` context updated when new waivers are submitted.

The split handler in the frontend (`SplitPanel.svelte`) sets initial values (`waiver_count: readyCount` for Group A, `waiver_count: 0` for Group B) but these are static snapshots at split time. Any waivers submitted after the split never propagate to either child instance's context.

## Impact

- The waiver gate (`waiver_count >= headcount`) on split child instances uses stale data
- The command center's new per-group waiver summary bars (added in this session) will display stale counts for split children
- The gate may never auto-advance even when enough waivers are collected

## What needs to happen

`sync_waiver_count` needs to update split child instances (`split_from.is_some() && status == Active`).

Open question: since waivers attach to bookings (not groups), all active children under the same booking would get the same booking-level accepted count. This is technically correct for the gate (total accepted >= this group's headcount) but semantically imprecise. True per-group attribution requires a `group_instance_id` column on the waiver model — a larger change.

## Frontend cleanup (do alongside server fix)

`WaiverReview.svelte` group breakdown rows show redundant headcount — the Badge already displays `"3 of 8"` and the trailing text repeats `"8 guests"`. Drop the trailing guest count text once the server fix makes group numbers accurate and worth reading closely.

**File:** `surface-command-center/src/lib/components/WaiverReview.svelte` — remove the `<span class="text-xs text-zinc-500">` guest count element from each group row.

## Files

- `server/api/src/types/workflow/checkin_service.rs` — `sync_waiver_count` function
- `server/api/src/types/workflow/instance.rs` — `is_active_primary()` definition
- `surface-command-center/src/lib/components/WaiverReview.svelte` — redundant guest count in group rows
