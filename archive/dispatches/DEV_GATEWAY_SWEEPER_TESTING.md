# Dispatch: Integration tests for gateway warm-start and sweeper

**Date:** 2026-03-30
**Workstream:** dev

## Problem

The gateway module was significantly restructured this session: `CachedLink` split from `LinkCache`, `load_active` replaced with `load_recent` (warm-start from `redirect_event`), new `recently_active_codes` query, and a `LinkCacheSweeper` background task. Existing unit tests cover `LinkCache` operations and `is_valid_code`, but the new DB-dependent code has zero test coverage:

- `load_recent` — warm-start query joining `redirect_event` → `short_link` → `campaign`
- `recently_active_codes` — index-only scan of `redirect_event` for the sweeper
- `lookup_by_code` — single-link DB fallback (pre-existing, also untested)

These are integration tests — they require a running MySQL instance with seeded data.

## Suggested Solution

1. **Seed test data:** Insert `short_link`, `campaign`, and `redirect_event` rows covering: active campaign with recent activity, active campaign with no recent activity (stale), inactive campaign (Paused/Ended) with recent activity, code with no campaign (standalone link edge case from `DEV_STANDALONE_LINK_NARROWING`).

2. **Test `load_recent`:** Verify it returns only codes with recent activity AND active campaigns. Verify stale codes and inactive campaigns are excluded.

3. **Test `recently_active_codes`:** Verify it returns all distinct codes with activity in the window. Verify codes outside the window are excluded.

4. **Test `lookup_by_code`:** Verify Active/Inactive status mapping from `CampaignStatus`. Verify `None` for nonexistent codes.

5. **Consider the existing `DEV_GATEWAY_HOT_PATH_TESTING` dispatch** — it covers handler-level branching (cache hit/miss, write-through placement). These new tests are complementary, not overlapping. Both dispatches should be addressed together.

## Reasoning

The restructuring changed the warm-start strategy from "load everything" to "load the working set." The correctness of the working set depends on the JOIN between `redirect_event` and `short_link` with the campaign status filter. A wrong JOIN condition silently loads the wrong set of links. The sweeper's `recently_active_codes` query determines what stays cached — a bug here silently evicts active codes.

## Confidence

**High** — the coverage gap is real and the queries are complex enough to warrant tests.
