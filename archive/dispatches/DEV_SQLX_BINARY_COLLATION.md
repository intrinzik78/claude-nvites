# Dispatch: Audit sqlx compatibility with utf8mb4_bin CHAR columns

**Date:** 2026-03-30
**Workstream:** dev

## Problem

sqlx decodes `CHAR(n) ... COLLATE utf8mb4_bin` columns as `BINARY`, not `VARCHAR`. Rust `String` fields in `FromRow` structs fail at runtime with `ColumnDecode: mismatched types; Rust type String (as SQL type VARCHAR) is not compatible with SQL type BINARY`. This was discovered during gateway hot path testing — all three `CacheLinkHelper` queries (`load_recent`, `lookup_by_code`, `recently_active_codes`) crashed when hitting real data.

The workaround applied in `cached_link.rs` is `CAST(sl.code AS CHAR) AS code` in every SELECT. This works but is fragile — every new query against a binary-collated CHAR column must remember the CAST or it will crash at runtime with no compile-time warning.

## Suggested Exploration

1. **Grep the schema for `utf8mb4_bin`** — identify all columns affected. `short_link.code` and `redirect_event.code` are confirmed. There may be others.

2. **Evaluate remedies:**
   - **Column-level fix:** `ALTER TABLE ... MODIFY COLUMN code CHAR(8) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci` — removes the problem at the source. Tradeoff: `utf8mb4_bin` gives case-sensitive, byte-exact comparison (important for short codes where `aBcD` ≠ `abcd`). Switching to `_general_ci` makes code lookups case-insensitive, which is wrong for base62 codes. `utf8mb4_0900_as_cs` (accent-sensitive, case-sensitive) may preserve correctness while being sqlx-compatible — needs testing.
   - **Query-level fix:** Keep `CAST(code AS CHAR) AS code` in every query. Correct but requires discipline. A missed CAST is a runtime crash with no compile-time signal.
   - **Rust-level fix:** Use `Vec<u8>` in `FromRow` structs and convert to String. Ugly, breaks the type abstraction, and forces every consumer to handle bytes.
   - **sqlx configuration:** Check if there's a connection-level setting or sqlx feature flag that changes binary-collation decoding behavior. (Low confidence this exists, but worth 10 minutes.)

3. **Decide and document** in DECISIONS.md which remedy to adopt project-wide.

## Reasoning

The current CAST workaround is correct but invisible to the compiler. A new developer (or Claude in a future session) writing a query against `short_link.code` will get a `String` field in their FromRow struct, it will compile, and it will crash at runtime. This is the kind of bug that recurs until the root cause is addressed.

## Confidence

**High** on the problem. **Medium** on the best remedy — the collation change needs testing to confirm sqlx compatibility and that case-sensitive comparison is preserved.
