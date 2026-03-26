# Dispatch: WorkflowError variants leak internal identifiers to HTTP responses

**Date:** 2026-03-21
**From:** server session (AUDIT-013)
**To:** server worktree
**Priority:** Medium — not blocking launch, but must be resolved before any workflow endpoint is public-facing (waiver workflows)

---

## Problem

Four `WorkflowError` variants pass internal strings directly into HTTP response bodies via `we.to_string()` in `to_api_error_message()` (error.rs lines 670–683):

- `StepNotFound(String)` → leaks step IDs, e.g. `"step not found: checkin_step_3"`
- `InvalidCondition(String)` → leaks condition parse errors, field names
- `SchemaViolation(String)` → leaks DB/JSON errors, row counts, parent instance IDs
- `EpochMismatch { expected, actual }` → leaks server-side epoch integers

Error codes 2003, 2004, 2005, 2014 are stable and correct. The problem is the `reason` string — it contains developer-diagnostic detail that should not reach any client (public or staff).

## Proposed Solution

**Confidence: High**

Replace the `we.to_string()` reason strings with human-written operational messages. Three layers:

1. **HTTP response** — operational language staff can act on or report clearly. No internal variable names, step IDs, row counts, or server state. These messages should answer "what happened" in terms the ops team understands, not "what broke" in code terms. The error codes (2003–2014) remain unchanged for dev-team correlation.

2. **Structured log at error level** — log the full original `we.to_string()` with internal detail before returning the sanitized response. This is where dev/you diagnose. The log line should include enough context to correlate (instance ID, definition ID, etc.).

3. **Error codes preserved** — clients and dev team can always reference the numeric code regardless of message text changes.

### Key insight from discussion

The ops team cannot diagnose workflow engine failures — they can only report them. So the HTTP response message should help them *describe* the problem to dev, not *debug* it. "Check-in workflow failed" is more useful at the counter than "step not found: checkin_step_3". The diagnostic detail belongs exclusively in logs.

This is a **global solution** — sanitize in `to_api_error_message()` once, and every future workflow endpoint (staff or public) gets safe defaults without the developer thinking about it.

## Design work required

Each variant needs a human-written operational message. These are different failure modes with different meanings at the counter:

- `StepNotFound` — a workflow step the definition references doesn't exist. Likely a definition authoring error.
- `InvalidCondition` — a gate/auto condition couldn't be parsed or evaluated. Definition authoring or context mismatch.
- `SchemaViolation` — broader structural failures: missing parent instances, JSON parse errors, epoch increment failures.
- `EpochMismatch` — concurrent modification detected. Retry may resolve.

The messages need to make sense to ops staff reading them in the command center UI. Ask the operator (Joshua) what language maps to each failure mode in practice.

## Files

- `server/api/src/enums/error.rs` — lines 670–683, `to_api_error_message()` match arms for `WorkflowError`
- `server/api/src/enums/workflow/workflow_error.rs` — variant definitions and `Display` impl
- All call sites that construct these variants (engine.rs, definition.rs, instance.rs, condition.rs, context.rs, epoch_guard.rs, checkin_service.rs) — verify the internal strings are logged before the error propagates to the handler layer

## Before implementation

- Decide on operational messages for each variant (requires operator input)
- Verify that all handler paths that surface these errors have tracing instrumentation — the internal detail must land in logs before it's stripped from the response
- Check whether any command center UI code pattern-matches on the reason string (unlikely but verify)
