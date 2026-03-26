# DISPATCH: Waiver accept clears group summaries momentarily

**Date:** 2026-03-15
**From:** surface-command-center waiver group aggregate work
**To:** surface-command-center (next session)
**Priority:** Low — cosmetic flash, no data loss

---

## Issue

`acceptWaiver()` and `acceptAll()` in `waiverList.svelte.ts` call `load()` to refresh after mutation. `load()` resets `groupSummaries = []`, so per-group coverage bars disappear during the reload. The epoch poller eventually triggers a re-fetch from the parent component (which passes instances), restoring the summaries — but there's a visible flash where group summaries vanish and reappear.

## What needs to happen

Store the last-used instances list in the ViewModel. When `acceptWaiver`/`acceptAll` refresh, call `loadWithGroups()` with the stored instances instead of plain `load()`.

Sketch:
```typescript
let lastInstances: WorkflowInstanceDto[] = [];

async function loadWithGroups(bookingUuid, guests, instances) {
    lastInstances = instances;  // store for reuse
    await load(bookingUuid, guests);
    // ... build groupSummaries
}

async function acceptWaiver(waiverId) {
    // ...
    if (lastInstances.length > 1) {
        await loadWithGroups(currentBookingUuid, guestCount, lastInstances);
    } else {
        await load(currentBookingUuid, guestCount);
    }
}
```

## Files

- `surface-command-center/src/lib/components/waiverList.svelte.ts` — `acceptWaiver`, `acceptAll`, add `lastInstances` state
