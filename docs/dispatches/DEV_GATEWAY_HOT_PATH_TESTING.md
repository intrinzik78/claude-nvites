# Dispatch: Expand gateway hot path test coverage

**Date:** 2026-03-29
**Workstream:** dev

## Problem

The redirect gateway is the hot path and its test coverage is minimal — unit tests only cover `is_valid_code()`, shard distribution, and basic cache operations. The `lookup_by_code` → `CampaignStatus::is_redirectable()` mapping has no test coverage. The handler's branching logic (cache hit vs DB fallback, active vs inactive, write-through on cold path only) is untested.

## Suggested Solution

1. **Integration test for `lookup_by_code`** — verify that all four `CampaignStatus` values (Draft, Paused, Ended, Active) map correctly to `LinkStatus::Inactive` / `LinkStatus::Active`. Requires a running MySQL instance.
2. **Unit tests for handler branching** — if the handler can be tested with a mock `AppState` (in-memory cache + stub DB), add tests for: cache hit → redirect, cache miss + active DB entry → write-through + redirect, cache miss + inactive DB entry → 404, cache miss + no DB row → 404, invalid code → 404.
3. **Verify write-through only fires on cold path** — test that a cache hit does not trigger a write lock.

## Reasoning

This is the highest-traffic endpoint. The `CampaignStatus` → `LinkStatus` mapping is correct by inspection but one wrong match arm silently breaks redirects for an entire campaign status. The write-through placement (cold path only) was a performance-critical fix that could regress without a test.

## Confidence

**High** — the coverage gap is real and the hot path warrants it.
