# Workflow Engine — System Diagram

> The system doesn't know what a "safety orientation" is. It knows "step N of M, type: manual, label: Safety Orientation." All product-specific knowledge lives in configuration, not code.

## Data Model

```
┌─────────────────────────────────────────────────────────────────┐
│  PRODUCT                                                        │
│  ┌─────────────┐                                                │
│  │ id           │──────────────┐                                │
│  │ name         │              │ has one                        │
│  │ workflow_id ─┼──────┐       │                                │
│  └─────────────┘      │       │                                │
│                        ▼       │                                │
│  WORKFLOW DEFINITION           │                                │
│  ┌─────────────────┐           │                                │
│  │ id               │          │                                │
│  │ product_id  ◄────┼──────────┘                                │
│  │ name             │                                           │
│  │ active           │                                           │
│  │ steps[]  ────────┼──────┐                                    │
│  └─────────────────┘      │                                    │
│                            ▼                                    │
│  STEP DEFINITION (ordered array)                                │
│  ┌──────────────────────────────────────┐                       │
│  │ position   │ label         │ type    │                       │
│  │ phase      │ config{}      │         │                       │
│  ├────────────┼───────────────┼─────────┤                       │
│  │ 1          │ Prepped       │ manual  │                       │
│  │ 2          │ Waivers Done  │ gate    │                       │
│  │ 3          │ In Session    │ auto    │                       │
│  │ ...        │ ...           │ ...     │                       │
│  └──────────────────────────────────────┘                       │
│                                                                 │
│  FLAGS (independent toggles, not part of step progression)      │
│  ┌──────────────────────────────────┐                           │
│  │ flag_key       │ label   │ default│                          │
│  │ photos_taken   │ Photos  │ false  │                          │
│  │ gear_returned  │ Gear    │ false  │                          │
│  └──────────────────────────────────┘                           │
└─────────────────────────────────────────────────────────────────┘
```

## Step Types

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│  MANUAL ─── Operator taps → system increments current_step      │
│             No conditions. "This is done, move on."             │
│                                                                 │
│  GATE ───── Operator taps → system evaluates condition          │
│             ├─ condition met ──→ increments current_step        │
│             └─ condition fails → shows block message, no move   │
│             e.g. waiver_count == headcount                      │
│                                                                 │
│  AUTO ───── System monitors trigger                             │
│             ├─ condition trigger → evaluates expression         │
│             └─ duration trigger ─→ countdown timer              │
│             When met → auto-increments, notifies operator       │
│                                                                 │
│  FLAG ───── NOT part of linear progression                      │
│             Independent toggle, set at any time                 │
│             Shown as indicator on check-in group                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Check-In Group Execution

```
                    ┌──────────────┐
                    │ ENTRY POINT  │
                    │              │
                    │  booking     │
                    │  walk_up     │
                    │  digital_queue│
                    └──────┬───────┘
                           │ creates
                           ▼
              ┌─────────────────────────┐
              │    CHECK-IN GROUP        │
              │                         │
              │  workflow_id ──→ which pipeline
              │  current_step ─→ position in pipeline
              │  headcount                │
              │  waiver_count (computed)  │
              │  flags: { key: bool }    │
              │  group_status:           │
              │    active | waiting | fulfilled
              └────────────┬────────────┘
                           │
                           ▼
        ┌──────────────────────────────────────┐
        │         PIPELINE EXECUTION           │
        │                                      │
        │  Phase: pre_arrival                  │
        │  ┌───┐  ┌───┐                        │
        │  │ 1 │→ │ 2 │→                       │
        │  └───┘  └───┘                        │
        │                                      │
        │  Phase: check_in                     │
        │  ┌───┐  ┌───┐  ┌───┐                 │
        │  │ 3 │→ │ 4 │→ │ 5 │→               │
        │  └───┘  └───┘  └─┬─┘                 │
        │                  │                    │
        │              GATE: waiver_count       │
        │              == headcount?            │
        │              ├─ yes → continue        │
        │              └─ no ── BLOCKED         │
        │                                      │
        │  Phase: service                      │
        │  ┌───┐  ┌───┐  ┌───┐                 │
        │  │ 6 │→ │ 7 │→ │ 8 │ ── COMPLETE    │
        │  └───┘  └───┘  └───┘                 │
        │                                      │
        │  Flags (toggle anytime):             │
        │  ☐ Photos Taken                      │
        │  ☐ Gear Returned                     │
        └──────────────────────────────────────┘
```

## Split Mechanics

```
                 ┌─────────────────┐
                 │  ORIGINAL GROUP  │
                 │  headcount: 20   │
                 │  current_step: 5 │
                 │  workflow: X     │
                 └────────┬────────┘
                          │ SPLIT
                 ┌────────┴────────┐
                 ▼                 ▼
    ┌─────────────────┐  ┌─────────────────┐
    │  GROUP A         │  │  GROUP B         │
    │  headcount: 12   │  │  headcount: 8    │
    │  workflow: X     │  │  workflow: X     │
    │  current_step: 5 │  │  current_step: 5 │
    └────────┬────────┘  └────────┬────────┘
             │                    │
             ▼                    ▼
      independent            independent
      advancement            advancement
      through same           through same
      pipeline               pipeline

  Split is workflow-agnostic.
  It operates on headcount, waivers, and position.
  Late arrivals can start at any step.
```

## Command Center Rendering

```
┌─────────────────────────────────────────────────────────────────┐
│  COMMAND CENTER (renders generically from workflow definitions)  │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ Group: "Smith Birthday Party"          headcount: 15    │    │
│  │                                                         │    │
│  │ pre_arrival    check_in           service               │    │
│  │ ── ── ──      ── ── ──           ── ── ──              │    │
│  │ ✓  ✓          ✓  ✓  ●           ○  ○  ○               │    │
│  │                      │                                  │    │
│  │                   CURRENT                               │    │
│  │                   [Advance ▶]                           │    │
│  │                                                         │    │
│  │ ✓ = completed   ● = current   ○ = upcoming             │    │
│  │ 🚫 = gate blocked (shows message)                      │    │
│  │                                                         │    │
│  │ Flags: ☐ Photos Taken                                   │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                 │
│  Adding a new product with a different workflow requires         │
│  ZERO code changes to the command center.                       │
│  Just a new workflow definition in the database.                │
└─────────────────────────────────────────────────────────────────┘
```

## Gate Condition Language

```
  Intentionally limited. The operator is the smart part of the system.

  Supported fields:          Supported operators:
  ─────────────────          ────────────────────
  waiver_count               ==  !=
  headcount                  >=  <=
  payment_confirmed          >   <
  flags.*

  Examples:
    waiver_count == headcount
    payment_confirmed == true
    flags.gear_returned == true

  If it can't be expressed here → make it a manual step.
```

## Architectural Impact

```
  BEFORE                              AFTER
  ──────                              ─────
  hardcoded service_state enum   →    configurable workflow pipelines
  photos_taken as special field  →    generic flag system
  product-specific UI logic      →    generic rendering from definitions

  products table:     + workflow_id
  check_in_groups:    - service_state (removed)
                      + workflow_id
                      + current_step (position int)
                      + flags (JSON object)
  settings:           + /settings/workflows (builder UI, admin only)
```

## API

```
  /api/workflows
  ├── GET /          operator+   List workflows
  ├── GET /[id]      operator+   Workflow detail with steps
  ├── POST /         admin       Create workflow
  ├── PUT /[id]      admin       Update (add/remove/reorder steps)
  └── DELETE /[id]   admin       Delete (only if no active groups using it)

  /settings/workflows             admin       Workflow builder UI
```
