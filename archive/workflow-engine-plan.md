# Workflow Engine — Server Implementation Plan

## Context

UWZ needs a generalized workflow engine that powers check-in pipelines, equipment maintenance, rental fulfillment, and any future operational workflow. The engine must be domain-agnostic — it knows steps, conditions, and advancement, never what a "waiver" or "headcount" means. Domain systems create instances, feed context, and interpret results.

The design spec lives in `workflow-engine.json`. Concurrency control lives in `concurrency.json` and is owned by parent entities (bookings, tickets), not the engine. This plan covers the Rust server implementation only — SDK and surface contracts are enforced separately by skills.

## The e=mc² Insight

Three concepts. That's the whole engine.

1. **Definition** — immutable blueprint (steps, context schema, flags)
2. **Instance** — mutable runtime state (current step, context bag, flags, status)
3. **Engine** — pure functions: `(definition, instance) → Mutation`

The `StepType` enum IS the advancement logic. The `Mutation` struct describes what changed. The service layer persists it. The engine has zero side effects, zero database access, zero awareness of HTTP or concurrency. It's a match arm.

```rust
match &current_step.step_type {
    Manual => advance_to_next(def, inst),
    Gate { ast, msg } => if ast.eval(ctx) { advance_to_next(def, inst) } else { Blocked(msg) },
    Auto(_) => Rejected,
}
```

## Module Structure

Lives in the existing `server/api` crate. No new workspace crate — it depends on `DatabaseConnection`, `AppState`, `Error`, `ApiResult`, `RouteLock`, all of which live in `api`.

```
server/api/src/
  enums/
    workflow.rs              ← all enums: DefinitionStatus, InstanceStatus, StepType, etc.

  types/workflow/
    mod.rs                   ← re-exports
    condition.rs             ← Condition AST, parser (~60 lines), evaluator (~40 lines)
    context.rs               ← ContextValue enum, ContextSchema, validation
    definition.rs            ← WorkflowDefinition struct, step/flag defs, DB queries
    instance.rs              ← WorkflowInstance struct, DB queries, apply_mutation
    engine.rs                ← Pure functions (THE engine). No db, no side effects.
    epoch_guard.rs           ← Pre-mutation check: load parent, verify lock + epoch
    monitor.rs               ← Background poller for auto-duration steps

  api/
    workflows/               ← Definition CRUD + publish/archive handlers
    workflow_instances/       ← Instance mutation handlers (advance, skip, pause, etc.)
```

## Core Enums

All follow existing `repr(u8)` + `from_u8()` convention from `campaign_status.rs`.

| Enum | Variants | Storage |
|------|----------|---------|
| `DefinitionStatus` | Draft=0, Published=1, Archived=2 | tinyint FK to lookup |
| `InstanceStatus` | Active=0, Paused=1, Completed=2, Cancelled=3, Split=4 | tinyint FK to lookup |
| `StepType` | Manual, Gate { condition, ast, message }, Auto(AutoConfig) | serde JSON in mediumtext |
| `AutoConfig` | Duration { minutes, message }, Condition { expr, ast, message } | serde tagged enum |
| `ComparisonOp` | Eq, Ne, Gte, Lte, Gt, Lt | part of AST |
| `ContextValueType` | Integer, Number, Boolean, Text | schema declarations |
| `ContextValue` | Integer(i64), Number(f64), Boolean(bool), Text(String) | runtime context bag |
| `AdvanceResult` | Advanced { to_step_id }, Completed, Blocked { message }, Rejected { reason } | engine return |

`InstanceStatus` gets `is_terminal()` → true for Completed, Cancelled, Split.

`StepType` is the critical enum. It's `#[serde(tag = "type")]` for JSON storage. The config (condition, AST, message, duration) lives inside the variant — not in a separate struct. The enum IS the polymorphism.

## Condition Language

Grammar: `field operator value`. One comparison per gate. No AND/OR.

**AST is three fields:**
```rust
struct Condition { left: Operand, op: ComparisonOp, right: Operand }
enum Operand { Field(String), Literal(ContextValue) }
```

**Parser** splits on whitespace, identifies fields vs literals (bool → number → field reference). ~60 lines.

**Evaluator** resolves operands against context + flags HashMap, dispatches comparison by operator and type. ~40 lines.

**Validation** at publish time: checks field references exist in context_schema, checks type compatibility, rejects ordering ops on booleans. Stores parsed AST on step config. Runtime never parses strings.

**Known limitation (v1):** String literals with spaces break the whitespace parser. Acceptable — all real conditions are numeric or boolean comparisons. Document the limitation. Add quoted string support in v2 if needed.

## Database Schema

Two lookup tables, two core tables. Follows existing conventions: `int` auto_increment PK, `tinyint` status FK with `ON DELETE RESTRICT`, `mediumtext` for JSON, `datetime` timestamps, `utf8mb4`.

### `workflow_definition`
| Column | Type | Notes |
|--------|------|-------|
| id | int PK auto_increment | row identity (FK target for instances) |
| workflow_key | varchar(64) | stable identity across all versions of the same workflow |
| name | varchar(128) | |
| owner_type | varchar(64) | opaque to engine ("product", "asset_type") |
| owner_id | varchar(64) | |
| version | int DEFAULT 1 | incremented on publish |
| status_id | tinyint FK | → workflow_definition_status |
| published_at | datetime NULL | |
| context_schema | mediumtext | JSON array of field defs |
| steps | mediumtext | JSON array of step defs (includes AST) |
| flags | mediumtext | JSON array of flag defs |
| created_at, updated_at | datetime | |

**Unique constraint:** `(workflow_key, version)` — each version of a workflow is a distinct row.
**Index:** `(workflow_key, status_id, version)` for "latest published" query.
**Query:** `WHERE workflow_key=? AND status_id=1 ORDER BY version DESC LIMIT 1`

`workflow_key` is the stable identity. `id` is the row PK used for FK from instances. Publishing creates a new row (new `id`, same `workflow_key`, incremented `version`). Instance's `workflow_id` FK points to the specific row — no separate `workflow_version` column needed on the instance.

**Why JSON not normalized steps:** Steps are always read as a complete list, immutable after publish, never individually queried. JSON eliminates joins and partial-update temptation.

### `workflow_instance`
| Column | Type | Notes |
|--------|------|-------|
| id | int PK auto_increment | |
| workflow_id | int FK | → workflow_definition (specific version row, pins the instance) |
| current_step_id | varchar(64) | stable identity, not position |
| context | mediumtext | JSON HashMap |
| flags | mediumtext | JSON HashMap |
| status_id | tinyint FK | → workflow_instance_status |
| entered_step_at | datetime | when instance entered current step |
| due_at | datetime NULL | for auto-duration: entered + minutes |
| remaining_seconds | int NULL | preserved on pause |
| created_at | datetime | |
| completed_at | datetime NULL | |
| created_by | varchar(64) | |
| split_from | int NULL FK | self-referential, ON DELETE SET NULL |
| parent_entity_type | varchar(64) | for monitor to find parent epoch |
| parent_entity_id | varchar(64) | |

**Index:** `(status_id, due_at)` — the auto-monitor's query path.
**Monitor query:** `WHERE status_id=0 AND due_at IS NOT NULL AND due_at <= NOW()`

**No epoch column** — epoch lives on the parent entity. The engine doesn't own concurrency.

### Full Migration SQL

```sql
SET FOREIGN_KEY_CHECKS = 0;

CREATE TABLE `workflow_definition_status` (
  `id` tinyint NOT NULL,
  `name` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `description` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

INSERT INTO `workflow_definition_status` (`id`, `name`, `description`) VALUES
  (0, 'draft',     'Editable. Not available for instance creation.'),
  (1, 'published', 'Immutable for breaking changes. Available for instance creation.'),
  (2, 'archived',  'No new instances. Running instances unaffected.');

CREATE TABLE `workflow_instance_status` (
  `id` tinyint NOT NULL,
  `name` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `description` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

INSERT INTO `workflow_instance_status` (`id`, `name`, `description`) VALUES
  (0, 'active',    'Running. Advancement permitted. Auto-monitor watches.'),
  (1, 'paused',    'Halted. No advancement. Duration timers frozen.'),
  (2, 'completed', 'Reached final step. Terminal.'),
  (3, 'cancelled', 'Terminated before completion. Terminal.'),
  (4, 'split',     'Original instance after split. Terminal.');

CREATE TABLE `workflow_definition` (
  `id` int NOT NULL AUTO_INCREMENT,
  `workflow_key` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `name` varchar(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `owner_type` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `owner_id` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `version` int NOT NULL DEFAULT 1,
  `status_id` tinyint NOT NULL DEFAULT 0,
  `published_at` datetime DEFAULT NULL,
  `context_schema` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `steps` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `flags` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_workflow_key_version` (`workflow_key`, `version`),
  KEY `ix_workflow_def_latest` (`workflow_key`, `status_id`, `version`),
  KEY `ix_workflow_def_owner` (`owner_type`, `owner_id`),
  CONSTRAINT `fk_workflow_def_status` FOREIGN KEY (`status_id`)
    REFERENCES `workflow_definition_status` (`id`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE `workflow_instance` (
  `id` int NOT NULL AUTO_INCREMENT,
  `workflow_id` int NOT NULL,
  `current_step_id` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `context` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `flags` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `status_id` tinyint NOT NULL DEFAULT 0,
  `entered_step_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `due_at` datetime DEFAULT NULL,
  `remaining_seconds` int DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `completed_at` datetime DEFAULT NULL,
  `created_by` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `split_from` int DEFAULT NULL,
  `parent_entity_type` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `parent_entity_id` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  PRIMARY KEY (`id`),
  KEY `ix_instance_workflow` (`workflow_id`),
  KEY `ix_instance_status` (`status_id`),
  KEY `ix_instance_auto_poll` (`status_id`, `due_at`),
  KEY `ix_instance_split_from` (`split_from`),
  KEY `ix_instance_parent` (`parent_entity_type`, `parent_entity_id`),
  CONSTRAINT `fk_instance_workflow` FOREIGN KEY (`workflow_id`)
    REFERENCES `workflow_definition` (`id`) ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT `fk_instance_status` FOREIGN KEY (`status_id`)
    REFERENCES `workflow_instance_status` (`id`) ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT `fk_instance_split_from` FOREIGN KEY (`split_from`)
    REFERENCES `workflow_instance` (`id`) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

SET FOREIGN_KEY_CHECKS = 1;
```

### JSON Column Shapes

**`steps` mediumtext** — serialized `Vec<StepDefinition>`:
```json
[
  {
    "step_id": "pb_prep",
    "position": 1,
    "label": "Prepped",
    "type": "manual",
    "phase": "pre_arrival",
    "optional": false
  },
  {
    "step_id": "pb_waivers",
    "position": 5,
    "label": "Waivers Complete",
    "type": "gate",
    "phase": "check_in",
    "optional": false,
    "condition": "waiver_count == headcount",
    "condition_ast": {
      "left": { "Field": "waiver_count" },
      "op": "Eq",
      "right": { "Field": "headcount" }
    },
    "message": "Waiver count ({waiver_count}) does not match headcount ({headcount})"
  },
  {
    "step_id": "er_session",
    "position": 6,
    "label": "In Session",
    "type": "auto",
    "phase": "service",
    "optional": false,
    "trigger": "duration",
    "duration_minutes": 60,
    "message": "60-minute session complete"
  }
]
```

**`context_schema` mediumtext** — serialized `Vec<ContextFieldDef>`:
```json
[
  { "key": "headcount", "type": "integer", "source": "input", "description": "Number of guests" },
  { "key": "waiver_count", "type": "integer", "source": "computed", "description": "Signed waivers" },
  { "key": "pressure_psi", "type": "number", "source": "input", "description": "PSI reading" }
]
```

**`flags` mediumtext** on definition — serialized `Vec<FlagDefinition>`:
```json
[{ "flag_key": "photos_taken", "label": "Photos Taken", "default": false }]
```

**`context` mediumtext** on instance — serialized `HashMap<String, ContextValue>`:
```json
{ "headcount": { "Integer": 15 }, "waiver_count": { "Integer": 12 }, "pressure_psi": { "Number": 850.0 } }
```

**`flags` mediumtext** on instance — serialized `HashMap<String, bool>`:
```json
{ "photos_taken": false }
```

### Mutation Struct Fields

```rust
pub struct Mutation {
    pub new_step_id: Option<String>,
    pub new_status: Option<InstanceStatus>,
    pub new_due_at: Option<Option<DateTime<Utc>>>,        // Some(None) clears it
    pub new_remaining_seconds: Option<Option<i32>>,        // Some(None) clears it
    pub new_completed_at: Option<Option<DateTime<Utc>>>,   // Some(None) clears it
    pub entered_step_at: Option<DateTime<Utc>>,
    pub new_context: Option<HashMap<String, ContextValue>>,
    pub new_flags: Option<HashMap<String, bool>>,
}
```

`apply_mutation()` builds a dynamic `UPDATE workflow_instance SET ... WHERE id = ?` from non-None fields. `current_step_position` is NOT stored — derive it at read time by looking up `current_step_id` in the definition's steps array.

## Engine (Pure Functions)

`engine.rs` contains a zero-field `Engine` struct used as a namespace. Every function takes `&WorkflowDefinition` and/or `&WorkflowInstance` and returns `Result<(AdvanceResult, Mutation), WorkflowError>`.

`Mutation` is a struct with all-Option fields describing what changed. The service layer's `apply_mutation()` builds a dynamic UPDATE from non-None fields.

| Function | Input | Logic |
|----------|-------|-------|
| `advance` | def, inst | Match on StepType: Manual→next, Gate→eval then next or block, Auto→reject |
| `skip` | def, inst | Check optional + not gate, then next |
| `set_position` | def, inst, target_step_id | Set current_step_id, compute due_at if auto-duration |
| `toggle_flag` | inst, flag_key | Flip bool in flags map |
| `pause` | def, inst | Status→Paused, freeze timer (remaining_seconds) |
| `resume` | def, inst | Status→Active, restart timer (due_at from remaining) |
| `cancel` | inst | Status→Cancelled, set completed_at |
| `auto_advance` | def, inst | Same as advance_to_next but callable by monitor |
| `normalize` | def, inst, now | Loop: while current step is auto and trigger is satisfied, advance. Safety cap: 10 transitions. |

**Internal helper:** `advance_to_next(def, inst)` → finds next step by position order from current step_id. If no next step → Completed. If next step is auto-duration → compute due_at.

**Normalization:** After any step transition (advance, skip, set_position, resume, auto_advance, update_context), the service layer calls `Engine::normalize()`. This prevents an instance from resting on a satisfied auto-condition step or an auto-duration step with 0 minutes. The engine loop advances through consecutive auto steps until it hits a manual/gate step or completes. Safety cap of 10 transitions prevents infinite loops from bad definitions. ~15 lines.

**Missing field semantics:** If a condition references a context field that hasn't been populated yet, the condition evaluates to `false` (gate blocks, auto-condition does not advance). The `AdvanceResult::Blocked` message includes `MissingField("field_name")` as a structured reason so the operator knows WHY the gate is blocked, not just that it is.

**Message interpolation:** `{field}` placeholders in gate block messages replaced with context values. Missing fields render as `{field_name}` unchanged. ~15 lines.

## Service Layer

Follows existing patterns. No controller struct needed (unlike sessions) — workflow operations are stateless request-response.

- `WorkflowInstance::load_with_definition(id, db)` — loads instance + its pinned definition version
- `WorkflowInstance::apply_mutation(mutation, db)` — dynamic UPDATE from Mutation
- `WorkflowInstance::due_instances(db)` — auto-monitor query
- `WorkflowDefinition::latest_published(workflow_key, db)` — for instance creation. Query: `WHERE workflow_key=? AND status_id=1 ORDER BY version DESC LIMIT 1`. The `InstancesPost` handler receives `workflow_key` in the request body and passes it here.
- `WorkflowDefinition::publish(id, db)` — parse + validate all conditions, store ASTs, flip status

**Epoch guard** (`epoch_guard.rs`):
- `check(parent_type, parent_id, client_epoch, db)` — load parent, check lock timeout, check epoch match
- `increment(parent_type, parent_id, db)` — bump epoch after mutation
- `parent_type` validated against a known set (enum with `from_str`) to prevent SQL injection via table name

**Split** uses an explicit `sqlx` transaction: `SELECT ... FOR UPDATE` on original, two child INSERTs, UPDATE original to `split`, epoch increment. All or nothing.

## API Handlers

Follow existing struct-based pattern from `secrets_post.rs`. Empty struct, static `logic()` method.

**Definition endpoints** (admin for write, operator for read):

| Method | Path | Handler |
|--------|------|---------|
| POST | /api/workflows | WorkflowsPost — create draft |
| GET | /api/workflows | WorkflowsGet — list published |
| GET | /api/workflows/{id} | WorkflowsGetOne — detail with version history |
| PUT | /api/workflows/{id} | WorkflowsPut — update draft only |
| POST | /api/workflows/{id}/publish | WorkflowsPublish — validate + publish |
| POST | /api/workflows/{id}/archive | WorkflowsArchive — archive published |
| DELETE | /api/workflows/{id} | WorkflowsDelete — delete draft only |

**Instance endpoints** (operator for all, epoch required on mutations):

| Method | Path | Handler |
|--------|------|---------|
| POST | /api/workflow-instances | InstancesPost — create from latest published |
| GET | /api/workflow-instances/{id} | InstancesGet — state + definition |
| POST | /api/workflow-instances/{id}/advance | InstancesAdvance |
| POST | /api/workflow-instances/{id}/skip | InstancesSkip |
| PUT | /api/workflow-instances/{id}/position | InstancesPosition |
| PATCH | /api/workflow-instances/{id}/context | InstancesContext |
| POST | /api/workflow-instances/{id}/flags/{key} | InstancesFlags |
| POST | /api/workflow-instances/{id}/split | InstancesSplit |
| POST | /api/workflow-instances/{id}/pause | InstancesPause |
| POST | /api/workflow-instances/{id}/resume | InstancesResume |
| POST | /api/workflow-instances/{id}/cancel | InstancesCancel |

Every mutation handler follows the same pattern:
1. Epoch guard check (lock + epoch)
2. Load instance + definition
3. Pure engine call → (AdvanceResult, Mutation)
4. If mutation changed current_step_id → call `Engine::normalize()` and merge resulting mutation
5. Persist mutation
6. Increment parent epoch
7. Return result

Registered in `route_collection.rs` with `RouteLock` middleware for permissions.

## Auto-Monitor

Follows `ScanController`/`ScanSweeper` pattern. Spawned from `main.rs` via `WorkflowMonitor::run()`.

- Configurable poll interval (default 10s)
- Query: `WHERE status_id=0 AND due_at IS NOT NULL AND due_at <= NOW()`
- For each result: load definition, call epoch_guard (skip if locked), call `Engine::auto_advance()`, call `Engine::normalize()`, persist mutation, increment parent epoch
- `due_at` is persisted — survives server restart
- Uses `tokio::time::interval` with `MissedTickBehavior::Delay`
- **Respects parent locks:** monitor calls `epoch_guard::check()` without a client epoch (system actor). If parent is locked, instance is skipped until next poll. Operators expect locked parents to freeze automation.

Condition-trigger auto steps don't use the monitor. They evaluate inline inside the `update_context` handler via `normalize()` — when context changes satisfy the condition, auto-advance happens immediately.

## Red Team Findings

| Finding | Severity | Resolution |
|---------|----------|------------|
| ~~f64 equality comparison~~ | ~~Medium~~ | **Resolved:** `ContextValue::Integer(i64)` added. Counts (headcount, waiver_count, items) use Integer with strict equality. Number(f64) reserved for measurements (PSI, FPS). No epsilon needed. |
| No audit log in v1 | Medium | Epoch changes provide basic "something changed" signal. `Mutation` struct can be serialized to an append-only log table in v2 with zero engine changes — logging happens at service layer. |
| String literals with spaces break condition parser | Low | All real conditions are numeric/boolean. Document limitation. Add quoted string support in v2. |
| `parent_type` string as table name → SQL injection risk | High | Validate against `ParentType` enum with `from_str()`. Unknown types rejected before SQL construction. |
| ~~Definition versioning~~ | ~~Medium~~ | **Resolved:** `workflow_key` added as stable identity across versions. Unique constraint on `(workflow_key, version)`. Instance FK pins to specific row `id`. No `workflow_version` on instance. |
| Auto-condition stall bug | High | `normalize()` loop after every step transition. Auto steps that are immediately satisfiable fire without waiting for external trigger. Safety cap of 10 transitions. |
| Missing context fields at runtime | Medium | Missing field → condition evaluates false. Structured `MissingField` reason in block message. Explicit and documented. |
| Monitor must respect parent locks | Medium | Monitor calls `epoch_guard::check()`. Locked parents are skipped until next poll cycle. |
| Auto-monitor 10s poll latency | Negligible | Timer is for operational signaling, not guest-facing countdown. Client renders countdown from `due_at`. Server eventually advances. |
| Split atomicity | Handled | InnoDB transaction with `SELECT ... FOR UPDATE`. All or nothing. |

## Implementation Sequence

1. Migration file — lookup tables + core tables
2. `enums/workflow.rs` — all enums
3. `types/workflow/context.rs` — ContextValue, ContextSchema, validation
4. `types/workflow/condition.rs` — parser, evaluator, validation
5. `types/workflow/definition.rs` — struct, DB queries
6. `types/workflow/instance.rs` — struct, DB queries, apply_mutation
7. `types/workflow/engine.rs` — pure functions (advance, skip, pause, resume, cancel, auto_advance, normalize)
8. Unit tests for engine — every branch against synthetic defs/instances
9. `types/workflow/epoch_guard.rs` — pre-mutation guard
10. `api/workflows/` — definition CRUD handlers
11. `api/workflow_instances/` — instance mutation handlers
12. `types/workflow/monitor.rs` — auto-step poller
13. Wire into `main.rs` and `route_collection.rs`
14. Add `WorkflowError` variants to `Error` enum with `#[from]`
15. Add `Resource::Workflows` to permission enum for `RouteLock`

## Verification

- **Unit tests** for `engine.rs`: synthetic definitions + instances, test every AdvanceResult path (advance through manual, gate pass, gate block, auto reject, skip optional, skip gate rejected, pause/resume timer math, cancel from active, cancel from paused, normalize through consecutive auto steps, normalize safety cap)
- **Unit tests** for `condition.rs`: parse valid expressions, reject malformed, validate against schema, evaluate against context, missing field returns false
- **Integration test**: create definition → publish → create instance → advance through full pipeline → verify completed status
- **Monitor test**: create instance on auto-duration step with 0-minute duration → poll → verify auto-advanced
- **Split test**: create instance → split → verify original is `split` status, two children exist with correct context
- **Normalization test**: definition with consecutive auto-condition steps where conditions are pre-satisfied → advance into first → verify instance lands on the next manual/gate step

## Reference Patterns (existing files to follow)

All paths relative to `server/api/src/`. These are in the server worktree at `/home/zik/programming/uwz/worktrees/server/server/api/src/` (implementation happens there, not in the surface-command-center worktree).

| Pattern | Reference File | What to copy |
|---------|---------------|--------------|
| `repr(u8)` enum with `from_u8` | `enums/campaign_status.rs` | Enum shape, bounds-check test, serde derive |
| Handler struct with `logic()` | `api/secrets/secrets_post.rs` | Empty struct, static async method, `WereChecked` + `Json<T>` + `Data<AppState>` params |
| Route scope registration | `types/route_collection.rs` | `web::scope()` with `.wrap(RouteLock)` and `.route()` calls |
| Background sweeper/poller | `types/scans/controller.rs` | `tokio::time::interval`, poll loop, spawn pattern |
| Error enum with `#[from]` | `enums/error.rs` | Add `WorkflowError` variants, `derive_more::From` |
| DB query with sqlx | `types/sessions/database_session.rs` | `sqlx::query_as()`, `FromRow` derive, `MySqlPool` usage |
| API response | `types/api_result.rs` | `ApiResult::ok(200, "ok").with_data(response)` |
| Permission check | `types/permissions.rs` | `UserPermissions`, `Resource` enum, bitmasked checks |
| Builder pattern | `types/user/builder.rs` | Method chaining, `build() -> Result<T>` |

## Files to Modify (existing)

- `server/api/src/enums/mod.rs` — add `pub mod workflow;`
- `server/api/src/enums/error.rs` — add WorkflowError variants with `#[from]`
- `server/api/src/types/mod.rs` — add `pub mod workflow;`
- `server/api/src/types/route_collection.rs` — add `workflows` and `workflow_instances` scopes in `v1()`
- `server/api/src/main.rs` — add `WorkflowMonitor::run(&shared_data).await;` alongside other sweepers
- `server/api/src/types/permissions.rs` — add `Resource::Workflows` variant to permission enum

## Files to Create

- `migrations/YYYYMMDDHHMMSS_workflow_engine.sql` (full SQL above in Database Schema section)
- `server/api/src/enums/workflow.rs`
- `server/api/src/types/workflow/mod.rs`
- `server/api/src/types/workflow/condition.rs`
- `server/api/src/types/workflow/context.rs`
- `server/api/src/types/workflow/definition.rs`
- `server/api/src/types/workflow/instance.rs`
- `server/api/src/types/workflow/engine.rs`
- `server/api/src/types/workflow/epoch_guard.rs`
- `server/api/src/types/workflow/monitor.rs`
- `server/api/src/api/workflows/mod.rs`
- `server/api/src/api/workflows/workflows_post.rs`
- `server/api/src/api/workflows/workflows_get.rs`
- `server/api/src/api/workflows/workflows_put.rs`
- `server/api/src/api/workflows/workflows_publish.rs`
- `server/api/src/api/workflows/workflows_archive.rs`
- `server/api/src/api/workflows/workflows_delete.rs`
- `server/api/src/api/workflow_instances/mod.rs`
- `server/api/src/api/workflow_instances/instances_post.rs`
- `server/api/src/api/workflow_instances/instances_get.rs`
- `server/api/src/api/workflow_instances/instances_advance.rs`
- `server/api/src/api/workflow_instances/instances_skip.rs`
- `server/api/src/api/workflow_instances/instances_position.rs`
- `server/api/src/api/workflow_instances/instances_context.rs`
- `server/api/src/api/workflow_instances/instances_flags.rs`
- `server/api/src/api/workflow_instances/instances_split.rs`
- `server/api/src/api/workflow_instances/instances_pause.rs`
- `server/api/src/api/workflow_instances/instances_resume.rs`
- `server/api/src/api/workflow_instances/instances_cancel.rs`

## Companion Design Specs

These files in the surface-command-center worktree root contain the full design context:
- `workflow-engine.json` — generalized engine spec with 4 example workflows
- `concurrency.json` — epoch/lock concurrency control system
- `diagram.md` — visual flow diagrams of the original domain-specific workflow
