# Restore User Epoch Triggers (Lost During Monorepo Migration)

**Date:** 2026-03-28
**Workstream:** server
**Recipient:** server agent
**Source:** Supplemental security audit, item 2.9
**Priority:** High — first line of session defense is currently non-functional

---

## Problem

The `user_epoch_events` table and the epoch polling/comparison infrastructure exist and work correctly on the read side. However, the SQL triggers that populate the table were lost during the migration from bare-metal MySQL to Docker-based local development (monorepo migration). The triggers were not included in the `mysqldump` that became the initial schema migration (`20260320000000_initial_schema.sql`), likely due to Cloud SQL export stripping them or `--skip-triggers`.

**Impact:** Permission changes, status changes, and role changes are never propagated to live sessions. A suspended user retains full access until their session's 10-day hard expiry. The epoch comparison (`current_epoch < next_epoch`) is always `0 < 0 = false`, so the re-fetch branch never fires.

## Defense-in-Depth Context

| Layer | Mechanism | Latency | Current State |
|-------|-----------|---------|---------------|
| 1 | Epoch triggers → background poller → per-request epoch_check → User re-fetch | Sub-second | **BROKEN** — triggers missing |
| 2 | 8-hour session row existence check (refresh path) | 6.4–9.6 hours | Working — catches session row deletion |
| 3 | Server restart clears in-memory session cache | Manual | Working |

Layer 2 checks session *existence*, not user state — it catches admin session revocation (row deletion) but not permission/status changes. Layer 1 is the only path that propagates authorization state changes to live sessions. Restoring it is the fix.

## Scope

New migration adding `AFTER UPDATE` triggers on the following tables/columns:

| Table | Column(s) | Why |
|-------|-----------|-----|
| `user` | `user_status_id` | Suspend/ban must propagate immediately |
| `user` | `user_type_id` | Entity type affects system behavior |
| `username` | `username` | Stale username in cached session → stale audit trails |
| `user_permissions` | `upper`, `lower` | Permission revocation is the other critical security case |

Each trigger should:
1. `UPDATE user SET epoch = epoch + 1 WHERE id = <affected_user_id>`
2. `INSERT INTO user_epoch_events (user_id, epoch) VALUES (<affected_user_id>, NEW.epoch)` — using the epoch value after the increment

The epoch polling infrastructure (`UserEpochController`) then picks up the new `MAX(id)` from `user_epoch_events`, fetches the change list, and `epoch_check` on the next request re-fetches the User from DB.

## Implementation Notes

- Single migration file with all triggers. Use `DELIMITER $$` / `CREATE TRIGGER ... END$$` syntax for MySQL 8.4 compatibility.
- The `user` table triggers can be a single `AFTER UPDATE` trigger that checks `IF OLD.user_status_id != NEW.user_status_id OR OLD.user_type_id != NEW.user_type_id`.
- The `username` and `user_permissions` triggers need to resolve the `user_id` — check the FK relationship to determine the join.
- Test: update a user's status via the admin endpoint, then verify `user_epoch_events` has a new row and the in-memory session reflects the change on the next request.
- Verify triggers exist in the local Docker DB after `sqlx migrate run` and in CI.

## Not In Scope

- `user_account_verification.is_verified` — the verification flow already transitions `user.user_status_id` (Unverified → Enabled), which fires the `user` trigger. The `is_verified` flag is an audit record, not authorization state.
- Layer 2 refresh changes — the 8-hour session row existence check works as designed for session revocation.
