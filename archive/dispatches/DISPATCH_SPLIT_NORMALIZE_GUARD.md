# DISPATCH: Split children need normalize guard at 3 remaining call sites

**Date:** 2026-03-15
**From:** server session (sync_waiver_count fix)
**Target:** server
**Priority:** Critical — monitor path can auto-advance split children via timer, bypassing manual-only guarantee

---

## Context

`sync_waiver_count` in `checkin_service.rs` no longer calls `normalize()` at all — for any instance, primary or split child (DISPATCH_WAIVER_DESIGN_DECISIONS.md Decision 1, executed 2026-03-15). The principle: **split children should never auto-advance. Staff reviews and manually advances split groups.** Normalize should only run on split children as a direct result of explicit advance/skip/reposition intent.

Three other call sites still run normalize unconditionally on split children.

## Sites that need the guard

### 1. Monitor (CRITICAL)

`server/api/src/types/workflow/monitor.rs` ~line 101

`process_instance()` calls `WorkflowEngine::normalize()` unconditionally on all due instances. If a split child has an auto-duration step that becomes due, the monitor will auto-advance it — bypassing manual-only control.

**Fix:** Skip normalize for instances where `split_from.is_some()`. The monitor should still process the due event (clear due_at, etc.) but not fold auto-advances.

### 2. instances_context.rs

`server/api/src/api/workflow_instances/instances_context.rs` ~line 112

Staff PATCH-es context → normalize evaluates gates → could auto-advance a split child. Updating context is not advance intent. Same rationale as sync_waiver_count.

**Fix:** Same guard pattern: `if inst.split_from.is_some() { mutation } else { normalize... }`.

### 3. instances_confirm_payment.rs

`server/api/src/api/workflow_instances/instances_confirm_payment.rs` ~line 104

Staff confirms payment → normalize evaluates `payment_confirmed` gate → could auto-advance a split child. Payment confirmation is not advance intent.

**Fix:** Same guard pattern.

## NOT affected (explicit staff intent — normalize is correct)

- `instances_advance.rs` — IS the manual advance. Guarding would prevent staff from advancing split children.
- `instances_position.rs` — IS manual reposition. Same reasoning.
- `instances_skip.rs` — IS manual skip. Same reasoning.
- `instances_split.rs` — Already has its own normalization logic at child creation.
- `instances_post.rs` — New instances are never split children.

## Reference pattern

The `split_from` guard was previously in `checkin_service.rs` `sync_waiver_count` but was removed when that function dropped normalize entirely (2026-03-15). The guard pattern for the 3 sites above:

```rust
// skip normalize for split children — staff advances manually
let final_mutation = if inst.split_from.is_some() {
    mutation
} else {
    let updated = mutation.clone().apply_to(inst.clone());
    match WorkflowEngine::normalize(def, &updated, now) {
        Ok(Some(norm)) => mutation.merge(norm),
        Ok(None) => mutation,
        Err(e) => { ... mutation }
    }
};
```
