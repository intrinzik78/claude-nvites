# DISPATCH: Waiver review needs group-level breakdown for split bookings

**Date:** 2026-03-15
**From:** handoff
**To:** surface-command-center (next session)
**Priority:** Low — only affects split bookings, which are the exception case

---

## Issue

The WaiverReview and WaiverSection currently show a booking-level aggregate: "X of Y waivers" where Y = `booking.guest_count`. The workflow waiver gate checks `waiver_count == headcount` per **check-in group**, not per booking.

For unsplit bookings (1 group = 1 booking), these are identical. For split bookings, each group has its own headcount and waiver count. The booking-level "3 of 10" doesn't tell the operator which group has coverage.

## What needs to happen

When a booking has multiple workflow instances (split), the waiver review page should group waivers by check-in group with per-group summary headers:

```
Group A (8/12 waivers)
  [waiver rows...]

Group B (3/8 waivers)
  [waiver rows...]
```

## Prerequisites

- Need a way to associate waivers to check-in groups (currently waivers attach to bookings via `waiver_collection`, not to groups)
- May need a server endpoint that returns waivers grouped by check-in group, or a way to derive the grouping client-side
- Check `command-center.json` `waiver_redistribution` open question: "When a split happens after some waivers are already submitted, how do waivers redistribute across groups?"

## Current state

- `WaiverReview.svelte` accepts `guestCount` prop (unused currently, reserved for this)
- `waiverList.svelte.ts` uses `guestCount` for the heuristic summary
- The server endpoint `GET /v1/bookings/{uuid}/waivers` returns a flat list with no group association
