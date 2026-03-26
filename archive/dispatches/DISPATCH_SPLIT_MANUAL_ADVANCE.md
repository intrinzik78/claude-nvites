# DISPATCH: Split children are now manual-advance only

**Date:** 2026-03-15
**From:** server session (sync_waiver_count fix)
**Target:** surface-command-center
**Priority:** Low — informational, no required changes

---

## What changed

Server now updates `waiver_count` context on split child workflow instances when waivers are accepted/attached. Previously, split children received no waiver_count updates (the gate was permanently stale).

However, split children will **not** auto-advance when the waiver gate condition is satisfied. Staff must manually advance split groups. This is by design — staff reviews waivers for correctness before advancing.

## Impact on command center

**No required changes.** The command center already uses manual advance buttons for split children, and waiver summary bars read from the waiver API (not instance context). The updated `waiver_count` in context is display data only.

## UX opportunity

When `waiver_count >= headcount` on a split child instance, the command center could surface a visual indicator (e.g., a "ready" badge or "approve and advance" button on the waiver review panel) so staff can one-click through when the counts match. This reduces friction while preserving the mandatory review step.

## Files for reference

- `server/api/src/types/workflow/checkin_service.rs` — sync_waiver_count (context-only, no normalize — split guard removed per Decision 1, 2026-03-15)
- `surface-command-center/src/lib/components/SplitPanel.svelte` — split UI, sets initial context
- `surface-command-center/src/lib/components/WaiverSection.svelte` — waiver summary display
