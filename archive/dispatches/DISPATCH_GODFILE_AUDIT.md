# DISPATCH: Audit domain type files for god-file risk

**Date:** 2026-03-15
**From:** dev session (waiver architecture review)
**To:** server (next available session)
**Priority:** Low — preventive, not blocking

---

## Context

`waiver.rs` reached 2,267 lines before decomposition. The file size was the primary source of fragility — every session touched it, every change risked breaking unrelated functionality, and no agent or human could hold the full context. The decomposition into 6 concern files (state machine, queries, hashing, audit, document, paper) resolved this.

The same pattern may exist in other domain type files. If any file crosses ~500 lines of non-test code, it's a candidate for the same decomposition approach.

## Task

Run a line-count audit across all files in `server/api/src/types/` (recursive). For each file over 500 total lines:

1. Report the line count
2. Estimate test vs. non-test split (look for `#[cfg(test)]` module position)
3. List the distinct concerns in the file (queries, state machine, validation, DTO conversion, etc.)
4. Flag whether it's a decomposition candidate

The decomposition pattern is proven: Option A from DISPATCH_WAIVER_DECOMPOSITION.md (separate `impl` blocks in sibling files, `pub(super)` field visibility, re-exports via `mod.rs`). No public API changes needed.

## What this is NOT

- Not a refactoring task. Do not decompose anything — report only.
- Not urgent. Run this when there's a natural gap in server work.

## Files for reference

- `server/api/src/types/waivers/` — the completed decomposition, as a reference for the pattern
- `archive/docs/DISPATCH_WAIVER_DECOMPOSITION.md` — the plan that guided it
