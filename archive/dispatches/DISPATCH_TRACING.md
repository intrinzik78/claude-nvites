# Dispatch: WorkflowError tracing lacks correlation context

**Date:** 2026-03-22
**From:** server session (AUDIT-013 follow-up)
**To:** server worktree
**Priority:** Low — diagnostics improvement, not a correctness or security issue

---

## Problem

The workflow error sanitization (AUDIT-013) logs internal detail via `tracing::warn!(detail = %we, ...)` in `to_api_error_message()`. This captures the error string but not the instance ID, definition ID, or parent entity context. Correlation requires joining with the TracingLogger request span (which includes the URL path containing the instance ID).

This works but is fragile — background paths (sweeper, monitor) that might surface these errors in the future wouldn't have a request span to join against.

## Verified state (2026-03-22)

Original dispatch claimed 26 construction sites — actual count is **27 in domain-logic files, 54 total** (12 additional in API handler files, scoped out — handlers have request-span correlation).

| Variant | Files | Sites | In map_err | Sanitized? |
|---|---|---|---|---|
| StepNotFound | engine, checkin_service | 2 | 0 | Yes (2003) |
| InvalidCondition | condition, engine | 6 | 0 | Yes (2004) |
| SchemaViolation | definition, context, instance, epoch_guard | 18 | 10 | Yes (2005) |
| EpochMismatch | epoch_guard | 1 | 0 | Yes (2014) |

- Sanitization choke point (`error.rs` `to_api_error_message()`) logs `detail = %we` for 4 variants (2003, 2004, 2005, 2014)
- `to_api_error_message()` takes `&self` (the `Error` enum) — no access to instance/definition IDs
- API handler files (`instances_*.rs`, `workflows/types.rs`) also construct WorkflowErrors but have request-span context — not in scope

## Decisions

- **Option 1 chosen**: structured tracing at construction sites (not enriched error types)
- **Scope**: only the 4 sanitized variants, only in domain-logic files (API handlers already have request-span correlation)
- **Field conventions**: `workflow_instance_id`, `workflow_definition_id`, `step_id` — use whichever are available in the enclosing function's scope
- **SchemaViolation splitting**: out of scope — separate concern, not blocking tracing work
- **Choke-point cleanup**: downgrade `error.rs` sanitization tracing from `warn`/`info` to `debug` after construction-site tracing is in place

## Slices

### Phase 1: Mechanical variants + choke-point cleanup

EpochMismatch (1 site), StepNotFound (2 sites), InvalidCondition (4 sites via engine.rs — 2 direct + 2 inspect_err on condition::evaluate propagation). Establishes field conventions.

condition.rs (4 construction sites) was **not touched** — pure functions with no workflow context. The 2 `compare()` errors are caught by `inspect_err` at engine.rs propagation points. The 2 `parse()` errors fire only during definition loading (via definition.rs) — covered in Phase 2.

Then downgrade choke-point tracing in `error.rs` for these 3 variants to `debug`.

**Two-tier tracing contract:** `warn`/`info` at construction site (rich context), `debug` at choke-point (redundant). SchemaViolation remains at `warn` at the choke-point since it has no construction-site tracing yet (Phase 2).

**Field conventions established:**
- `workflow_instance_id` (i32), `workflow_definition_id` (i32), `step_id` (%Display)
- Use whichever are available in the enclosing function's scope
- `info` for expected concurrency (EpochMismatch), `warn` for schema bugs (StepNotFound, InvalidCondition)

**Files touched:**
- `server/api/src/types/workflow/epoch_guard.rs` — EpochMismatch (1 site, tracing::info)
- `server/api/src/types/workflow/engine.rs` — StepNotFound (1 site), InvalidCondition (2 direct + 2 inspect_err)
- `server/api/src/types/workflow/checkin_service.rs` — StepNotFound (1 site)
- `server/api/src/enums/error.rs` — choke-point downgrade (3 variants: warn→debug, info→debug)

**Status:** [x] complete

### Phase 2: SchemaViolation (separate pass)

18 sites across 4 files. 10 are in `map_err` closures (definition.rs, instance.rs) where IDs may not be captured. Needs a pattern decision: capture IDs into closures, trace after `?` propagation, or restructure.

**Files touched:**
- `server/api/src/types/workflow/definition.rs` — 10 sites (7 in map_err)
- `server/api/src/types/workflow/instance.rs` — 4 sites (3 in map_err)
- `server/api/src/types/workflow/epoch_guard.rs` — 3 sites (0 in map_err)
- `server/api/src/types/workflow/context.rs` — 1 site (0 in map_err)
- `server/api/src/enums/error.rs` — choke-point downgrade (SchemaViolation)

**Before implementation:**
- Decide `map_err` tracing pattern — definition.rs closures are in deeply nested method chains where the enclosing function may not have instance IDs (definition.rs works with definitions, not instances). The `inspect_err` pattern from Phase 1 won't transfer directly because error types flow through `From` conversions. Explore definition.rs's call graph first.
- **Gap from Phase 1:** 2 `InvalidCondition` construction sites in `condition.rs` (lines 22, 57 — `parse()` and `parse_op()`) propagate through definition.rs as InvalidCondition, not SchemaViolation. These need coverage in this phase since they're reachable via definition loading, not engine execution.

**Status:** [ ] not started

## Files

- `server/api/src/enums/error.rs` — current sanitization + tracing (lines 670–711)
- `server/api/src/types/workflow/engine.rs` — StepNotFound, InvalidCondition construction
- `server/api/src/types/workflow/definition.rs` — SchemaViolation construction (10 sites, 7 in map_err)
- `server/api/src/types/workflow/condition.rs` — InvalidCondition construction (4 sites)
- `server/api/src/types/workflow/context.rs` — SchemaViolation construction (1 site)
- `server/api/src/types/workflow/epoch_guard.rs` — SchemaViolation (3 sites), EpochMismatch (1 site)
- `server/api/src/types/workflow/instance.rs` — SchemaViolation construction (4 sites, 3 in map_err)
- `server/api/src/types/workflow/checkin_service.rs` — StepNotFound construction (1 site)
