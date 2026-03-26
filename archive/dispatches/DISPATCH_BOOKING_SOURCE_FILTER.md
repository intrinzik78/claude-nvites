# Dispatch: Add booking_source filter to workflow instances endpoint

**Date:** 2026-03-17
**From:** surface-command-center (SLICE 04)
**To:** server worktree

---

## Request

Add optional `booking_source` query param to `GET /v1/workflows/instances`.

Currently the command center fetches all booking-parented instances twice (once per track at potentially different statuses), then splits them client-side by matching against a set of queue-sourced booking UUIDs. This works but doubles the API calls when the two tracks are at different status filters.

## What exists today

```
GET /v1/workflows/instances?parent_entity_type=booking&status=Active
```

Returns all booking-parented instances regardless of whether the parent booking is source=booking or source=queue.

## What's needed

```
GET /v1/workflows/instances?parent_entity_type=booking&status=Active&booking_source=queue
```

The server joins through `workflow_instances.parent_entity_id` → `bookings.uuid` → `bookings.booking_source` and filters.

## Frontend impact

Once available, `commandCenterInstances.svelte.ts` collapses from two independent fetch slots to one fetch per track with server-side filtering. The `filterInstanceGroups` splitting logic in `+page.svelte` becomes unnecessary.

## Not urgent

The two-fetch model works. This is a clean-up optimization, not a blocker.
