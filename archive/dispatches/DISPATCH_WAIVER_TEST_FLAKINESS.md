# Fix Waiver Integration Test Flakiness

**Date:** 2026-03-24
**Workstream:** server
**Priority:** Low — not blocking, but erodes CI trust

## Problem

`test_confirm_idempotent` (and potentially other waiver integration tests) fails intermittently under concurrent test execution but passes in isolation. Same class of bug as the sweeper tests fixed in this session: concurrent tests share the same MySQL database and interfere with each other's data.

## Fix Pattern

The sweeper fix provides the template:

1. Wrap test data setup (waiver creation + dependent rows) in a single DB transaction so records are atomically visible
2. Remove assertions on global counts (e.g., "at least N rows affected") — assert on the specific test record's state instead
3. Ensure cleanup handles all created rows

## Files

- `server/api/src/types/waivers/integration_tests.rs` — investigate `test_confirm_idempotent` and scan sibling tests for the same pattern
- Reference: `server/api/src/types/bookings/integration_tests.rs` — `setup_stale_booking_with_payment()` for the atomic setup pattern

## Confidence

High. Exact same root cause and fix pattern as the sweeper tests.
