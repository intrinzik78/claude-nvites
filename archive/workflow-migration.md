# Crosscutting: Workflow Engine Audit + SDK Exposure

## Context

The command center's three panels map directly to workflow position:
- **Lower right** (digital queue inbox): instances blocked at acceptance auto-step
- **Upper right** (accepted, unpaid): instances past acceptance, blocked at payment auto-step
- **Left** (paid, operational): instances past payment, running through service steps

The engine already supports this via auto-condition steps + `normalize()`. This session audits the implementation, updates the seed workflow, adds instance list filtering, completes SDK exposure, and reviews all changes.

## Audit Summary

| Component | Status | Gap |
|-----------|--------|-----|
| Engine (18 handlers, normalize) | Complete | None |
| Database schema | Complete | Missing `(status_id, current_step_id)` index |
| Seed workflow | Placeholder | 6 manual steps, no auto-condition gates |
| Instance list endpoint | No filtering | `all()` returns everything unfiltered |
| SDK-Rust | 95% | Missing 2 def methods; `set_position` POST->PUT bug; `update_context` wrong return type; `list_instances` no query params |
| SDK-TS | 0% for workflows | Types generated but not exposed; no api module |

## Known issues carried (out of scope)
- Epoch guard calls stubbed (commented out) in `monitor.rs`

## Red Team Findings

| # | Finding | Severity | Mitigation |
|---|---------|----------|------------|
| F1 | Seed migration cannot DELETE a published definition -- FK constraint from any existing instances would fail, and violates engine's "published = immutable" rule | HIGH | Archive v1 (UPDATE status_id=2), INSERT v2 with same workflow_key, version=2 |
| F2 | Plan had incorrect return types for some SDK-TS methods | MEDIUM | Verified all 18 handlers -- exact `request<T>` vs `requestEmpty` table below |
| F3 | SDK-Rust `update_context` declares `Result<ApiSuccess<WorkflowInstanceDto>>` but handler returns no data | MEDIUM | Fix to `Result<()>` in slice 3 since we're touching the file |
| F4 | SDK-Rust `list_instances()` has no query params -- won't work after server adds filtering | MEDIUM | Add matching params to slice 3 |
| F5 | Reviews were batched in slice 5 -- user requires per-slice reviews | MEDIUM | Each slice now ends with `/review` or `/review-ts` |
| F6 | `condition_ast` is `#[serde(skip)]` -- never serialized to JSON | Clarified | Seed data must NOT include condition_ast. `parse_conditions()` handles it after load |
| F7 | Auto-condition steps missing `message` fields | LOW | Include messages: "Group accepted", "Payment confirmed" |
| F8 | `waiver_count >= headcount` vs `== headcount` | Design choice | `>=` is operationally safer -- won't block on edge cases. Kept. |

### Verified Handler Return Types

**Definition handlers:**

| Handler | Returns Data | Type | SDK method |
|---------|-------------|------|-----------|
| POST /workflows (create) | YES | `WorkflowDefinitionDto` | `request<T>` |
| GET /workflows (list) | YES | `Vec<WorkflowDefinitionDto>` | `request<T>` |
| GET /workflows/{id} | YES | `WorkflowDefinitionDto` | `request<T>` |
| PUT /workflows/{id} (update) | NO | -- | `requestEmpty` |
| DELETE /workflows/{id} | NO | -- | `requestEmpty` |
| POST /{id}/publish | YES | `WorkflowDefinitionDto` | `request<T>` |
| POST /{id}/archive | YES | `WorkflowDefinitionDto` | `request<T>` |

**Instance handlers:**

| Handler | Returns Data | Type | SDK method |
|---------|-------------|------|-----------|
| POST /workflow-instances (create) | YES | `WorkflowInstanceDto` | `request<T>` |
| GET /workflow-instances (list) | YES | `Vec<WorkflowInstanceDto>` | `request<T>` |
| GET /workflow-instances/{id} | YES | `WorkflowInstanceDto` | `request<T>` |
| POST /{id}/advance | YES | `AdvanceResult` | `request<T>` |
| POST /{id}/skip | YES | `AdvanceResult` | `request<T>` |
| PUT /{id}/position | YES | `AdvanceResult` | `request<T>` |
| PATCH /{id}/context | NO | -- | `requestEmpty` |
| POST /{id}/split | NO | -- | `requestEmpty` |
| POST /{id}/pause | NO | -- | `requestEmpty` |
| POST /{id}/resume | NO | -- | `requestEmpty` |
| POST /{id}/cancel | NO | -- | `requestEmpty` |

### Verified Auto-Condition JSON Shape

`condition_ast` is `#[serde(skip)]` in both `StepType::Gate` and `AutoConfig::Condition`. 3-deep flatten produces flat JSON. Confirmed by existing roundtrip tests in `definition.rs`.

```json
{"step_id":"ci_accept","label":"Accepted","type":"auto","trigger":"condition","condition":"accepted == true","message":"Group accepted","phase":"intake","optional":false}
```

---

## Slice 1: Seed Workflow Migration

**Goal:** Replace the placeholder 6-step manual "checkin" workflow with the acceptance/payment auto-condition model.

### Files
| Action | Path |
|--------|------|
| Create | `server/migrations/20260227120000_replace_checkin_workflow.sql` |

### Migration SQL

**Archive v1, insert v2** (not DELETE -- respects FK constraints and engine's immutability rule):

```sql
-- Archive the placeholder v1
UPDATE workflow_definition SET status_id = 2 WHERE workflow_key = 'checkin' AND version = 1;

-- Insert the real v2 with acceptance/payment auto-condition model
INSERT INTO workflow_definition
  (workflow_key, name, owner_type, owner_id, version, status_id, published_at, context_schema, steps)
VALUES (
  'checkin',
  'Guest Check-In',
  'system',
  'uwz',
  2,
  1,  -- published
  NOW(),
  '<context_schema_json>',
  '<steps_json>'
);
```

**context_schema** (5 fields):

| key | type | source | display | description |
|-----|------|--------|---------|-------------|
| accepted | boolean | external | -- | Set by operator accepting a queue entry |
| payment_confirmed | boolean | external | -- | Set by POS or online payment |
| headcount | integer | input | -- | Number of guests in the group |
| waiver_count | integer | computed | -- | Signed waivers linked to this group |
| photos_taken | boolean | input | toggle | Photos taken toggle |

**steps** (10 steps -- no `condition_ast` in JSON, `parse_conditions()` handles it on load):

| # | step_id | label | type | phase | condition/trigger | message |
|---|---------|-------|------|-------|-------------------|---------|
| 1 | ci_accept | Accepted | auto | intake | trigger:condition, condition:`accepted == true` | Group accepted |
| 2 | ci_prep | Prepped | manual | pre_arrival | -- | -- |
| 3 | ci_fill | Filled | manual | pre_arrival | -- | -- |
| 4 | ci_arrive | Arrived | manual | check_in | -- | -- |
| 5 | ci_checkin | Checked In | manual | check_in | -- | -- |
| 6 | ci_waivers | Waivers Complete | gate | check_in | condition:`waiver_count >= headcount` | {waiver_count} of {headcount} waivers collected |
| 7 | ci_payment | Payment Confirmed | auto | check_in | trigger:condition, condition:`payment_confirmed == true` | Payment confirmed |
| 8 | ci_safety | Safety Orientation | manual | service | -- | -- |
| 9 | ci_playing | Playing | manual | service | -- | -- |
| 10 | ci_complete | Complete | manual | service | -- | -- |

**Entry paths (context at creation):**
- Pre-paid: `{ accepted: true, payment_confirmed: true, headcount: N, waiver_count: 0, photos_taken: false }` -> normalize auto-advances past both -> lands at `ci_prep`
- Walk-up: `{ accepted: true, payment_confirmed: false, headcount: N, waiver_count: 0, photos_taken: false }` -> auto-advances past accept -> blocks at payment
- Digital queue: `{ accepted: false, payment_confirmed: false, headcount: N, waiver_count: 0, photos_taken: false }` -> blocks at `ci_accept`

### Verify + Review
```bash
cd server && cargo xtask build-all
```
Then run `/review` on the migration file.

---

## Slice 2: Server -- Instance List Filtering

**Goal:** Add query parameters to `GET /v1/workflow-instances` so the command center can filter by status, workflow_id, and parent entity.

### Files
| Action | Path |
|--------|------|
| Create | `server/migrations/20260227120001_instance_status_step_index.sql` |
| Modify | `server/api/src/api/workflow_instances/instances_list_get.rs` |
| Modify | `server/api/src/types/workflow/instance.rs` |
| Modify | `api-contracts/src/paths/workflow_instances.rs` |

### Changes

**New migration** -- compound index for panel queries:
```sql
ALTER TABLE workflow_instance ADD INDEX ix_instance_status_step (status_id, current_step_id);
```

**`instances_list_get.rs`** -- follow `queue_entries_list_get.rs` pattern exactly:
- Add `ListInstancesQuery` struct with `Deserialize` + `deny_unknown_fields`
- Fields: `status: Option<InstanceStatus>`, `workflow_id: Option<i32>`, `parent_entity_type: Option<String>`, `parent_entity_id: Option<String>`
- Accept `Query<ListInstancesQuery>` parameter in handler signature
- Call `WorkflowInstance::filtered(...)` instead of `::all(db)`

**Pattern reference:** `server/api/src/api/queue_entries/queue_entries_list_get.rs` lines 14-48

**`instance.rs`** -- add `filtered()` method following `QueueEntry::by_date()` dynamic SQL pattern:
- Base: `SELECT {INSTANCE_COLS} FROM workflow_instance WHERE 1=1`
- Optional clauses: `AND status_id = ?`, `AND workflow_id = ?`, `AND parent_entity_type = ?`, `AND parent_entity_id = ?`
- Bind order must match push_str order
- `ORDER BY created_at DESC, id DESC LIMIT 500`

**Pattern reference:** `server/api/src/types/queue_entries/queue_entry.rs` lines 111-141

**`api-contracts/src/paths/workflow_instances.rs`** -- add `params(...)` to the `get_workflow_instances` utoipa path:
```rust
params(
    ("status" = Option<InstanceStatus>, Query, description = "Filter by instance status"),
    ("workflow_id" = Option<i32>, Query, description = "Filter by workflow definition id"),
    ("parent_entity_type" = Option<String>, Query, description = "Filter by parent entity type"),
    ("parent_entity_id" = Option<String>, Query, description = "Filter by parent entity id"),
)
```

### Verify + Review
```bash
cd server && cargo xtask build-all   # rebuilds openapi.json with new params
```
Then run `/review` on all modified Rust files in this slice.

---

## Slice 3: SDK-Rust Completion

**Goal:** Add missing definition methods, fix bugs, add list filtering params.

### Files
| Action | Path |
|--------|------|
| Modify | `sdk-rust/src/types/workflows/workflows_client.rs` |

### Changes (6 items)

**1. Add `update_definition()` to WorkflowsClient:**
```rust
/// PUT /v1/workflows/{id} -- update a draft workflow definition.
pub async fn update_definition(&self, id: i32, body: UpdateWorkflowBody) -> Result<()> {
    let path = format!("/v1/workflows/{id}");
    self.client.send_empty(self.client.put(&path)?.json(&body)).await
}
```
Note: handler returns no data -> `send_empty`.

**2. Add `delete_definition()` to WorkflowsClient:**
```rust
/// DELETE /v1/workflows/{id} -- delete a draft workflow definition.
pub async fn delete_definition(&self, id: i32) -> Result<()> {
    let path = format!("/v1/workflows/{id}");
    self.client.send_empty(self.client.delete(&path)?).await
}
```

**3. Fix `set_position()` HTTP method bug** -- line ~153:
Change `self.client.post(&path)?` -> `self.client.put(&path)?`
Server registers this as `web::put()` at `route_collection.rs:164`.

**4. Fix `update_context()` return type** -- line ~138:
Change `Result<ApiSuccess<WorkflowInstanceDto>>` -> `Result<()>`
Change `self.client.send(...)` -> `self.client.send_empty(...)`
Handler returns `ApiResult::success()` with no data.

**5. Add query params to `list_instances()`:**
```rust
/// GET /v1/workflow-instances -- list workflow instances with optional filters.
pub async fn list_instances(
    &self,
    status: Option<InstanceStatus>,
    workflow_id: Option<i32>,
    parent_entity_type: Option<&str>,
    parent_entity_id: Option<&str>,
) -> Result<ApiSuccess<Vec<WorkflowInstanceDto>>> {
    let mut params = Vec::new();
    if let Some(s) = status { params.push(("status".into(), (s as u8).to_string())); }
    if let Some(w) = workflow_id { params.push(("workflow_id".into(), w.to_string())); }
    if let Some(t) = parent_entity_type { params.push(("parent_entity_type".into(), t.to_string())); }
    if let Some(i) = parent_entity_id { params.push(("parent_entity_id".into(), i.to_string())); }
    let qs = if params.is_empty() { String::new() } else {
        format!("?{}", params.iter().map(|(k,v)| format!("{k}={v}")).collect::<Vec<_>>().join("&"))
    };
    let path = format!("/v1/workflow-instances{qs}");
    self.client.send(self.client.get(&path)?).await
}
```

**6. Add `UpdateWorkflowBody` to imports** (line ~9).

### Verify + Review
```bash
cd sdk-rust && cargo check && cargo test
```
Then run `/review` on the modified file.

---

## Slice 4: SDK-TS Workflow Module

**Goal:** Create the TypeScript workflow API module and wire it into the client.

### Files
| Action | Path |
|--------|------|
| Create | `sdk-ts/src/api/workflows.ts` |
| Modify | `sdk-ts/src/types/index.ts` |
| Modify | `sdk-ts/src/client.ts` |
| Modify | `sdk-ts/src/index.ts` |

### Changes

**`sdk-ts/src/types/index.ts`** -- add workflow type re-exports after the existing Waiver section:
```typescript
// -- Workflow types --
export type WorkflowDefinitionDto = components["schemas"]["WorkflowDefinitionDto"];
export type WorkflowInstanceDto = components["schemas"]["WorkflowInstanceDto"];
export type ContextFieldDef = components["schemas"]["ContextFieldDef"];
export type ContextValue = components["schemas"]["ContextValue"];
export type ContextValueType = components["schemas"]["ContextValueType"];
export type StepDefinition = components["schemas"]["StepDefinition"];
export type StepType = components["schemas"]["StepType"];
export type AutoConfig = components["schemas"]["AutoConfig"];
export type DefinitionStatus = components["schemas"]["DefinitionStatus"];
export type InstanceStatus = components["schemas"]["InstanceStatus"];
export type AdvanceResult = components["schemas"]["AdvanceResult"];
// -- Workflow request bodies --
export type CreateWorkflowBody = components["schemas"]["CreateWorkflowBody"];
export type UpdateWorkflowBody = components["schemas"]["UpdateWorkflowBody"];
export type CreateInstanceBody = components["schemas"]["CreateInstanceBody"];
```

**`sdk-ts/src/api/workflows.ts`** -- new file following `queue.ts` pattern exactly. `makeWorkflowsApi(client: UwzClient)` returns:

Definition methods:

| Method | HTTP | Path | Returns | SDK call |
|--------|------|------|---------|----------|
| `listDefinitions()` | GET | /v1/workflows | `WorkflowDefinitionDto[]` | `request` |
| `getDefinition(id)` | GET | /v1/workflows/{id} | `WorkflowDefinitionDto` | `request` |
| `createDefinition(body)` | POST | /v1/workflows | `WorkflowDefinitionDto` | `request` |
| `updateDefinition(id, body)` | PUT | /v1/workflows/{id} | void | `requestEmpty` |
| `deleteDefinition(id)` | DELETE | /v1/workflows/{id} | void | `requestEmpty` |
| `publishDefinition(id)` | POST | /v1/workflows/{id}/publish | `WorkflowDefinitionDto` | `request` |
| `archiveDefinition(id)` | POST | /v1/workflows/{id}/archive | `WorkflowDefinitionDto` | `request` |

Instance methods:

| Method | HTTP | Path | Returns | SDK call |
|--------|------|------|---------|----------|
| `listInstances(params?)` | GET | /v1/workflow-instances | `WorkflowInstanceDto[]` | `request` |
| `getInstance(id)` | GET | /v1/workflow-instances/{id} | `WorkflowInstanceDto` | `request` |
| `createInstance(body)` | POST | /v1/workflow-instances | `WorkflowInstanceDto` | `request` |
| `advanceInstance(id, epoch?)` | POST | /{id}/advance | `AdvanceResult` | `request` |
| `skipInstance(id, epoch?)` | POST | /{id}/skip | `AdvanceResult` | `request` |
| `setInstancePosition(id, stepId, epoch?)` | PUT | /{id}/position | `AdvanceResult` | `request` |
| `updateInstanceContext(id, context, epoch?)` | PATCH | /{id}/context | void | `requestEmpty` |
| `splitInstance(id, ctxA, ctxB, epoch?)` | POST | /{id}/split | void | `requestEmpty` |
| `pauseInstance(id, epoch?)` | POST | /{id}/pause | void | `requestEmpty` |
| `resumeInstance(id, epoch?)` | POST | /{id}/resume | void | `requestEmpty` |
| `cancelInstance(id, reason?, epoch?)` | POST | /{id}/cancel | void | `requestEmpty` |

Query params on `listInstances`: `status?: string`, `workflow_id?: number`, `parent_entity_type?: string`, `parent_entity_id?: string` -- build URLSearchParams same as queue.ts pattern.

**`sdk-ts/src/client.ts`** -- add import and spread:
```typescript
import { makeWorkflowsApi } from "./api/workflows.js";
// in createClient():
...makeWorkflowsApi(client),
```

**`sdk-ts/src/index.ts`** -- add workflow type re-exports to the barrel export (mirror types/index.ts additions).

### Verify + Review
```bash
cd sdk-ts && npm run check && npm test
```
Then run `/review-ts` on all modified/created TypeScript files in this slice.

---

## Slice 5: Final Build Pipeline Verification

**Goal:** Full end-to-end build pipeline + regenerate SDK-TS types from updated OpenAPI spec.

### Actions
```bash
# 1. Full server pipeline (api-contracts -> openapi.json -> server)
cd server && cargo xtask build-all

# 2. Regenerate TS types from updated openapi.json (slice 2 added query params)
cd sdk-ts && npm run generate

# 3. All gates
cd sdk-rust && cargo check && cargo test
cd sdk-ts && npm run check && npm test
```

---

## Dependency Graph

```
Slice 1 (seed migration)     -- independent
Slice 2 (server filtering)   -- independent (run cargo xtask build-all after)
Slice 3 (SDK-Rust)            -- independent
Slice 4 (SDK-TS)              -- benefits from slice 2 (updated OpenAPI spec)
Slice 5 (build verification)  -- depends on all prior slices
```

## All Files Summary

| Slice | File | Action |
|-------|------|--------|
| 1 | `server/migrations/20260227120000_replace_checkin_workflow.sql` | Create |
| 2 | `server/migrations/20260227120001_instance_status_step_index.sql` | Create |
| 2 | `server/api/src/api/workflow_instances/instances_list_get.rs` | Modify |
| 2 | `server/api/src/types/workflow/instance.rs` | Modify |
| 2 | `api-contracts/src/paths/workflow_instances.rs` | Modify |
| 3 | `sdk-rust/src/types/workflows/workflows_client.rs` | Modify |
| 4 | `sdk-ts/src/api/workflows.ts` | Create |
| 4 | `sdk-ts/src/types/index.ts` | Modify |
| 4 | `sdk-ts/src/client.ts` | Modify |
| 4 | `sdk-ts/src/index.ts` | Modify |

## Progress Tracker

- [x] Slice 1: Seed Workflow Migration
- [x] Slice 2: Server -- Instance List Filtering
- [x] Slice 3: SDK-Rust Completion (+ fixed 4 pre-existing return type bugs: skip, pause, resume, split; + send_empty now accepts 201)
- [x] Slice 4: SDK-TS Workflow Module
- [ ] Slice 5: Final Build Pipeline Verification
