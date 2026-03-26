# Workflow Engine — Fresh-Eyes Review

## What's Elegant (genuinely)

The `(definition, instance) → Mutation` core is the real deal. Pure functions, zero side effects, zero DB awareness. The engine is a match arm. That IS e=mc².

Five specific things to keep exactly as-is:
1. **StepType IS the polymorphism** — no strategy pattern, no visitor, just match arms
2. **Definition pinning** — instances pin to a specific version row, no drift
3. **AST at publish time** — runtime never parses strings
4. **Epoch delegation** — engine doesn't own concurrency, parent does
5. **Mutation struct** — all-Option fields, dynamic UPDATE, composable with normalize()

## Where the Elegance Breaks Down

### 1. Flags Are Just Context Fields (simplification opportunity)

Right now the engine has TWO parallel data stores on every instance:
- `context` (HashMap<String, ContextValue>) — for step-driving data
- `flags` (HashMap<String, bool>) — for independent toggles

And TWO parallel schemas on every definition:
- `context_schema` (Vec<ContextFieldDef>)
- `flags` (Vec<FlagDefinition>)

And the condition language has a special `flags.` prefix to reach across: `flags.gear_returned == true`.

This is a code smell. Flags are boolean context fields that happen to render as toggles. Merge them:

- Add `"display": "toggle"` (or `"category": "flag"`) to `ContextFieldDef`
- Remove the `flags` column from both tables
- Remove `FlagDefinition` struct
- Remove `toggle_flag` engine function — it's `update_context({ gear_returned: true })`
- Conditions reference everything uniformly: `gear_returned == true`, not `flags.gear_returned == true`

**Result**: One fewer JSON column on two tables. One fewer struct. One fewer engine function. Simpler condition language (no special namespace). The UI distinguishes toggles from inputs via schema annotation, not data architecture.

### 2. `position` Field is Redundant and Contradictory

The spec says: `"position": "number (display order only — not used for tracking)"`

The plan says: `advance_to_next` finds next step **by position order** from current step_id.

These contradict. If position drives advancement, it's not display-only. If it's display-only, advancement should use array order.

Steps are stored as a JSON array. The array order IS the canonical progression order. `step_id` provides stable identity. `position` adds nothing except a divergence risk — what if array order and position disagree?

**Recommendation**: Remove `position` from `StepDefinition`. Array index is the position. `advance_to_next` finds the current step_id in the array and returns index + 1. If you need display ordering that differs from progression order (can't imagine why), handle it in UI metadata.

### 3. Normalization Safety Cap is Under-specified

`normalize()` loops through consecutive auto steps with a cap of 10 transitions. But what happens when the cap is hit?

- Does the engine return an error? Then the entire mutation fails and the instance stays at its original step.
- Does it stop mid-pipeline? Then the instance rests on an auto step it shouldn't be on.
- Does it return a warning? Then the caller needs to handle it.

This must be explicit. Recommendation: cap hit → return a `NormalizationOverflow` error variant. The mutation is NOT applied. The definition is broken (10+ consecutive auto steps that all fire is a design error). Surface it to the admin, don't silently corrupt state.

Also: 10 is arbitrary. Should this be configurable per definition? Probably not — keep it simple. 10 is a sane safety valve. But document that definitions with >10 consecutive auto steps are rejected at publish time (validate this).

### 4. No `completed_by` / `cancelled_by`

`created_by` exists but there's no record of WHO completed or cancelled an instance. For an operational system where cancellation affects billing, you need to know which operator cancelled and when. Add `completed_by` and/or a generic `last_actor` field, or wait for the audit log (but that's P1 future, and this is P0 data).

### 5. `owner_type`/`owner_id` on Definitions — Pulling Its Weight?

Definitions have `owner_type` ("product", "asset_type") and `owner_id`. These are opaque, unvalidated strings. The `workflow_key` already uniquely identifies a definition family. What does owner provide that workflow_key doesn't?

If it's for filtering ("show me all workflows for product X"), consider whether a simple `tags` or naming convention on `workflow_key` achieves the same thing with less schema. If owner enables real access control (only the owner can edit), then it needs validation and FK enforcement, not opaque strings.

Not blocking — just questioning whether it earns its place in an e=mc² design.

## Stress-Testing Against Real Businesses

12 different businesses, their core workflow through this engine.

### Workflows That Fit Perfectly (linear, forward-moving)

| Business | Workflow | Why It Works |
|----------|----------|--------------|
| **Hair salon** | Appointment → Arrive → Consult → Wash → Cut → Style → Checkout | All manual, optional blowout step, auto-duration for color processing |
| **Food truck** | Ordered → Prepping → Cooking → Ready → Picked Up | Simple linear, all manual |
| **Auto repair** | Intake → Diagnosis → Estimate → Approval (gate) → Repair → QC (gate) → Pickup | Gates enforce customer sign-off and quality check |
| **Rental car** | Reserved → Prepped → Pickup → In Use (auto-duration) → Return → Inspection (gate) → Clean → Available | Auto-duration for rental period, gate for damage assessment |
| **Deployment pipeline** | Build → Tests (gate) → Stage → Integration (gate) → Approval → Production → Smoke (gate) → Done | Classic CI/CD — gates are pass/fail checks |
| **Lab sample** | Collected → Transport → Received → Processing (auto-duration) → QC (gate) → Released → Archived | Auto-duration for processing time, gate for QC |

### Workflows That Strain the Engine

| Business | Workflow | What Breaks | Severity |
|----------|----------|-------------|----------|
| **Restaurant kitchen** | Order with 5 dishes, each at different prep stages | Need parallel instances per dish, "order done" is computed across instances — engine can't express "all children complete" | **Manageable** — domain computes completion, same pattern as UWZ split groups |
| **Construction** | Foundation → (Electrical ∥ Plumbing ∥ HVAC) → Inspection → Drywall | Parallel branches. Can't model with linear engine. Need 3 instances + domain join. | **Bad fit** — construction needs a DAG |
| **Customer support** | Open → Triage → In Progress → Waiting on Customer → back to In Progress when customer responds | Cycles. `set_position` works but it's an operator override, not a defined flow. Very common pattern. | **Workable** — set_position handles it, but loses semantic meaning |
| **Legal review** | Draft → Review → Revisions → Review → Revisions → Final → Sign | Revision cycles. Each rejection is a manual set_position. | **Workable** — same as support, but more frequent cycling |
| **Insurance claim** | Filed → Investigate → Estimate → Approval gate → Payment | Gate: `amount <= authority_limit`. If amount exceeds limit, need escalation. Engine doesn't model escalation — you'd update context to change authority_limit or cancel and create new instance for higher authority. | **Clunky** — escalation patterns don't fit cleanly |
| **Medical clinic** | Check-in → Vitals → (Lab work ∥ X-ray) → Doctor → Checkout | Parallel diagnostics. Same as construction — needs multiple instances. | **Manageable** — split into sub-workflows, domain joins |

### The Pattern

The engine handles **linear, forward-moving operational pipelines** extremely well. It strains on:

1. **Parallel branches** (DAG workflows) — requires multiple instances + domain-level join
2. **Cycles** (revision/retry patterns) — requires `set_position` as manual override
3. **Conditional branching** (if VIP skip steps 2-3) — requires separate definitions per path

For UWZ specifically, all four example workflows are linear and forward-moving. The engine is correctly scoped for its domain. The "generality" is a bonus for other linear-pipeline businesses, not a promise of BPMN-level workflow modeling.

**This is the right trade-off.** Trying to add DAG support or cycle support would destroy the e=mc² simplicity. Better to be excellent at linear pipelines than mediocre at everything.

## Actual Bugs / Contradictions Found

1. **Spec vs plan contradiction on `position`** — spec says display-only, plan uses it for advancement logic
2. **Spec says context type is `number | boolean | string`; plan adds `Integer`** — the spec should be updated to include `integer` as a type, since the Integer/Number split was a red-team resolution
3. **Spec says `flags.gear_returned == true` in condition examples** — if flags are merged with context, this syntax disappears. If not merged, the condition parser needs special `flags.` prefix handling that isn't detailed in the condition grammar section
4. **Step_id uniqueness validation not mentioned** — publish-time validation checks conditions but doesn't explicitly check step_id uniqueness within a definition. Should be added.
5. **`current_step_id` pointing to nonexistent step** — what if DB is manually edited or definition is corrupted? The engine should return a structured `StepNotFound` error, not panic.

## Recommendations Summary

| # | Change | Type | Impact |
|---|--------|------|--------|
| 1 | Merge flags into context with schema annotation | **Simplification** | -1 column per table, -1 struct, -1 engine fn, simpler conditions |
| 2 | Remove `position` from StepDefinition, use array index | **Simplification** | Removes contradiction, eliminates divergence risk |
| 3 | Specify normalization overflow behavior explicitly | **Correctness** | Prevents undefined state on safety cap hit |
| 4 | Add `completed_by`/`cancelled_by` to instance | **Completeness** | Audit trail for terminal state transitions |
| 5 | Validate step_id uniqueness at publish time | **Correctness** | Prevents ambiguous step references |
| 6 | Handle `StepNotFound` gracefully in engine | **Correctness** | Structured error instead of panic on corrupt state |
| 7 | Update spec to include `integer` context type | **Consistency** | Spec and plan should agree |
| 8 | Decide on `owner_type`/`owner_id` — keep or remove | **Simplification** | Questionable value in e=mc² design |

Items 1 and 2 are the big e=mc² wins. The rest are correctness/completeness polish.

## Red Team of These Findings

Each recommendation attacked, counterattacked, and given a verdict.

### Finding 1 (Merge flags into context) — STRENGTHENED

**Attack:** Flags are intentionally cheap to toggle. `update_context` validates against schema — that adds overhead for the most common UI interaction (operator tapping a toggle).

**Counter:** Validating a boolean field is one HashMap lookup to verify the field exists + one type check. Nanoseconds. Not real overhead.

**Attack:** Separating flags creates a safety boundary. With merged context, the API endpoint for "toggle photos_taken" is the same as "update waiver_count." A frontend bug could corrupt step-driving data.

**Counter:** Field names differ. Schema validates types. Sending `waiver_count: true` fails type validation (expected integer). Type safety prevents cross-contamination.

**Attack:** The UI needs more work — it must read schema annotations to know what's a toggle vs. a data input.

**Counter:** The UI already reads context_schema. One additional field check is trivial. And it's MORE flexible.

**Critical discovery during red team:** The current design has a **latent bug**. The plan says `normalize()` runs after `update_context` but NOT after `toggle_flag`. But the spec says conditions CAN reference flags: `flags.gear_returned == true`. If an auto-condition step references a flag, toggling that flag SHOULD trigger normalization — but currently doesn't. Merging flags into context **fixes this bug** because all context mutations go through the same path that triggers normalization.

**Verdict: Finding STRENGTHENED.** Not just simpler — it's also more correct.

### Finding 2 (Remove `position`) — HOLDS

**Attack:** Array index is fragile. If JSON serialization round-trips reorder the array, step ordering breaks silently.

**Counter:** JSON arrays preserve order per spec. serde deserializes in order. MySQL stores as mediumtext string — order is preserved. No round-trip risk.

**Attack:** Sparse positioning (10, 20, 30) allows inserting position 15 without rewriting others.

**Counter:** Steps are immutable after publish. Editing is drafts-only, which rewrites the entire JSON blob regardless. Sparse positioning gains nothing.

**Attack:** What if display order should differ from advancement order?

**Counter:** Can't think of a case for a linear pipeline. If they ever need to differ, that would require a much bigger design change.

**Verdict: HOLDS.** The contradiction is real, array index is sufficient.

### Finding 3 (Normalization overflow) — HOLDS

**Attack:** `NormalizationOverflow` error means the operator can't advance past a broken section — they're stuck.

**Counter:** Correct. A definition with 10+ consecutive auto steps that all fire simultaneously IS broken. The admin must fix it. Rejecting the mutation and surfacing the error is the right behavior. Silently stopping mid-pipeline on a satisfied auto-condition step would leave the instance permanently stuck (monitor doesn't poll auto-condition steps, only auto-duration).

**Verdict: HOLDS.** Error is the correct behavior.

### Finding 4 (completed_by/cancelled_by) — HOLDS WITH CAVEAT

**Attack:** The P1 audit log will capture this with full event history. Adding columns now creates redundancy.

**Counter:** P1 is future. "Who cancelled this?" is P0 operational data. Querying a single column is O(1) vs. scanning an audit log.

**Attack:** `completed_by` is sometimes "system" (auto-monitor completes an instance), not always a user.

**Counter:** `created_by` already uses the same pattern (varchar, not FK). "system" as a value is established convention.

**Verdict: HOLDS, but note the audit log overlap.** When the audit log ships, these columns become denormalized shortcuts, not the source of truth. That's acceptable.

### Finding 5 (step_id uniqueness) — HOLDS

No meaningful attack. Two steps with the same step_id makes the second unreachable. Publish-time validation is the obvious place to catch it. Trivial to implement, zero cost.

**Verdict: HOLDS.** Obvious correctness check.

### Finding 6 (StepNotFound error) — HOLDS

**Attack:** When would this actually happen? Only if someone manually edits the database or there's a deserialization bug.

**Counter:** A structured error is 3 lines of code. The cost is near-zero, the benefit is a clear error message instead of a 500 panic in production.

**Verdict: HOLDS.** Cheap insurance.

### Finding 7 (integer context type) — HOLDS

No attack possible. The spec and plan should agree. Documentation sync.

**Verdict: HOLDS.** Trivial fix.

### Finding 8 (owner_type/owner_id) — **REVISED: I WAS WRONG**

**Attack on my finding:** `owner_type`/`owner_id` enables direct lookups: "list all workflow definitions for product 'paintball'." Without it, you'd parse workflow_key strings or add a tags system. With it, `WHERE owner_type = 'product' AND owner_id = ?` is a clean indexed query. The migration already has `ix_workflow_def_owner`.

For UWZ, each product (paintball, escape room) and each asset type has its own workflows. The admin UI needs "workflows for this entity" as a direct lookup. owner_type/owner_id delivers that.

The criticism that it's "unvalidated" applies equally to `parent_entity_type`/`parent_entity_id` on instances — that's the same pattern throughout the system.

**Verdict: REVISED.** owner_type/owner_id earns its place. I was too aggressive. Downgraded from "questionable" to "keep — consistent with other opaque type/id patterns in the system."

### Stress Test Section — NUANCE ADDED

**Attack on "bad fit" labels:** I labeled construction as a "bad fit." But if each trade (electrical, plumbing, HVAC) is its own workflow instance under a parent "project" entity, and the domain computes "when all trades complete, project moves to inspection" — that's the exact same pattern as UWZ's split groups. The engine handles individual linear pipelines. The domain handles parallel orchestration across them.

This applies to restaurant (instance per dish), medical clinic (instance per diagnostic), and any "parallel work" scenario. The engine isn't being bypassed — it's handling the linear parts. Only the JOIN logic is outside the engine's scope.

**Verdict: Relabel.** "Bad fit" is misleading. More accurate: "requires domain orchestration layer on top of engine." The engine still handles the linear sub-pipelines. No business is fully outside the engine's reach — some just need more domain glue.

## Revised Recommendations Summary

| # | Change | Type | Verdict | Impact |
|---|--------|------|---------|--------|
| 1 | Merge flags into context with schema annotation | **Simplification** | **STRENGTHENED** — also fixes normalization bug | -1 column per table, -1 struct, -1 engine fn, fixes latent bug |
| 2 | Remove `position` from StepDefinition, use array index | **Simplification** | **HOLDS** | Removes contradiction, eliminates divergence risk |
| 3 | Specify normalization overflow as error | **Correctness** | **HOLDS** | Prevents undefined state on safety cap hit |
| 4 | Add `completed_by`/`cancelled_by` to instance | **Completeness** | **HOLDS** (note audit log overlap) | Audit trail for terminal state transitions |
| 5 | Validate step_id uniqueness at publish time | **Correctness** | **HOLDS** | Prevents ambiguous step references |
| 6 | Handle `StepNotFound` gracefully in engine | **Correctness** | **HOLDS** | Structured error instead of panic on corrupt state |
| 7 | Update spec to include `integer` context type | **Consistency** | **HOLDS** | Spec and plan should agree |
| 8 | ~~Decide on owner_type/owner_id~~ | ~~Simplification~~ | **REVERSED** — it earns its place | Keep as-is |

Items 1 and 2 remain the big e=mc² wins. Finding 1 is stronger than originally stated.
