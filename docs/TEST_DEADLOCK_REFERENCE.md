# Dispatch: Serializing Integration Tests Against Shared MySQL to Eliminate InnoDB Deadlock Flakiness

**Date:** 2026-03-28
**Workstream:** dev

## Problem

Integration tests that run against a shared MySQL database (InnoDB engine) can develop intermittent deadlock failures when the codebase uses pessimistic locking patterns (`SELECT ... FOR UPDATE`). The failure rate is typically around 30% of runs — enough to erode confidence in the test suite without being consistent enough to diagnose easily.

The flakiness does not arise from tests sharing data. Tests that use unique IDs, unique emails, and completely disjoint rows still deadlock. The failure mode is a conflict between **lock patterns**, not between **rows**. InnoDB under REPEATABLE READ isolation acquires next-key locks on every row it *examines* during a query, not just the rows it modifies. A sweeper operation (e.g., `DELETE FROM table WHERE status = X AND expires_at < NOW()`) must scan and lock the entire relevant index range — including rows held by unrelated concurrent transactions.

The sequence:

1. Test A begins a transaction, locks row X with `SELECT ... FOR UPDATE`
2. Test B runs a global `DELETE ... WHERE condition`, scanning the same index range and needing a lock on row X
3. InnoDB detects a circular lock dependency and kills one transaction with error 1213
4. The killed transaction's test panics on `.expect()` or propagates an error; the test framework reports a failure
5. On re-run, timing changes, the collision does not occur, and the test passes

This is Rust's default `cargo test` behavior: integration tests run in parallel across threads. The parallelism is the direct enabler of the deadlock.

## Reasoning

- **Unique test data does not isolate lock ranges.** InnoDB gap and next-key locking operate on index ranges. A global scan locks the entire range relevant to its `WHERE` clause, regardless of which specific rows belong to which test.
- **Deadlock retry logic masks the problem intermittently.** Production code often wraps DB calls in retry loops for exactly this reason. When retries succeed, the test passes. When the deadline or retry budget is exhausted, it fails. The test appears non-deterministically flaky.
- **The failing test rotates between runs.** Because the collision depends on OS thread scheduling, different tests are the victim on different runs. This makes it appear like random environmental noise, not a structural bug.
- **MySQL error 1213 is the diagnostic signal.** If the stack trace contains `1213` (ER_LOCK_DEADLOCK), the problem is confirmed. Without that trace, developers often chase the wrong hypothesis (bad test data, DB state contamination, timeout misconfiguration).
- **The FOR UPDATE locks are correct.** They exist because the production code is correct — row-level pessimistic locks prevent concurrent booking conflicts, overbooking, or double-processing. Removing them to fix tests would degrade production correctness.

## Detection Checklist

Flag this problem in any codebase that satisfies all five conditions:

1. Integration tests run against a real database (not mocked or in-memory)
2. The codebase uses `SELECT ... FOR UPDATE` or other explicit row-locking patterns
3. There are sweeper, cleanup, or expiry functions that do global `DELETE` or `UPDATE` scans over status/time conditions
4. Integration tests run in parallel (the default for Rust, Go, Jest, pytest-xdist, etc.)
5. Stack traces include MySQL error 1213, or test failures are intermittent and pass on re-run

If all five are true, the codebase has this problem.

## Proposed Solution

Serialize integration tests that touch the shared database. Unit tests remain parallel — only tests that issue real DB calls need serialization.

In Rust, add `serial_test` as a dev-dependency and annotate each integration test:

```toml
[dev-dependencies]
serial_test = "3"
```

```rust
#[tokio::test]
#[serial_test::serial]
async fn test_booking_lock() { ... }
```

Performance impact is negligible. Integration tests are IO-bound — the bottleneck is database round-trips, not CPU. Serialization removes the retry overhead and re-run time caused by deadlock failures.

## Confidence

**High** — InnoDB next-key locking under REPEATABLE READ is well-documented MySQL behavior. The detection checklist provides a clear yes/no gate. `serial_test` is the standard Rust solution for this class of problem.
