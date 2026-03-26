# Queue Panel Migration: `expected_at` + Hour-Block Redesign

## Why

The queue panel serves as a **heads-up display** for the ops team — "who's coming and when, how much gear do I prep?" The current flat card list sorted by priority tier doesn't answer the time question because `expected_at` doesn't exist in the data model. 80% of queue entries come from the website (call-ahead) where customers select an arrival time.

This migration adds `expected_at` through the full stack (database → api-contracts → server → Tauri → frontend) and redesigns the queue panel from flat cards to hour-block groupings with per-block headcount subtotals.

## Target State

```
┌─ Queue ──────────────── 31 guests ── + ↻ ─┐
│                                             │
│  10:00–11:00 ──────────────── 12 guests ──  │
│  10:30  Martinez family        ★   8  ●     │
│  11:00  Johnson                ★   4  ●     │
│                                             │
│  11:00–12:00 ──────────────── 19 guests ──  │
│  11:00  Williams group         ★   6  ●     │
│  11:30  Chen                   ★   3  ●     │
│  12:00  Davis birthday         ★  10  ●     │
│                                             │
│  No time ─────────────────────────────────  │
│    —    Smith (walk-in)            2  ●     │
│                                             │
│  ┄ Skipped (2) ┄┄┄┄┄┄┄┄┄┄┄ 10 guests ┄┄   │
│  10:00  Taylor                     6  ○     │
│  11:00  Brown                      4  ○     │
└─────────────────────────────────────────────┘
```

★ = call-ahead marker. ● = status dot (yellow waiting, green arrived). ○ = skipped (ring).

## Red Team Findings

| # | Finding | Verdict |
|---|---------|---------|
| RT-1 | WalkUpTrack depends on raw `queueVM.entries` — ViewModel `entries` must stay unfiltered | Safe — new derivations (`nonSkipped`, `hourBlocks`) only affect queue panel display |
| RT-2 | NaiveTime serde → `"HH:MM:SS"`, HTML input → `"HH:MM"` | Mitigated — Tauri command parses both formats with fallback |
| RT-3 | All entries have `expected_at = null` until website call-ahead ships | Acceptable — degrades to flat "No time" section, staff can optionally enter times |
| RT-4 | Priority tier info lost when removing tier badge | Mitigated — keep within-block tier sort + subtle call-ahead marker (★) |
| RT-5 | Two-click interaction (click row → click action) vs one-click | Acceptable for ~10-20 daily actions, justified by cleaner glanceable view |
| RT-6 | Hour block boundary: 11:00 → "11:00–12:00" block | Standard clock-hour grouping |
| RT-7 | `deny_unknown_fields` backward compat | Safe — all surfaces deploy together |
| RT-8 | Click-to-select accessibility | Mitigated — tabindex, ARIA attributes, keyboard Enter/Space/Escape |
| RT-9 | Security | No concerns — chrono validates times, sqlx parameterizes queries |

---

## Slices

### Slice 1 — Contract: `expected_at` in api-contracts + migration

**Reasoning:** The contract layer is the foundation. Everything else depends on these types compiling. Doing this first means slice 2 (server) can immediately use the new field without forward-declaring anything.

**Type choice: `Option<NaiveTime>` (not `DateTime<Utc>`).** The `date` field already exists on the entry — `expected_at` is "what time on that date," not a full timestamp. NaiveTime maps cleanly to MySQL `TIME`, avoids timezone complexity, and `<input type="time">` produces "HH:MM" naturally. chrono's serde serializes NaiveTime as "HH:MM:SS".

**Files:**

1. **New file:** `server/migrations/20260228120000_queue_entry_add_expected_at.sql`
   ```sql
   ALTER TABLE `queue_entry` ADD COLUMN `expected_at` time NULL AFTER `notes`;

   -- Backfill seed call-aheads with plausible expected times
   UPDATE queue_entry SET expected_at = '15:00:00'
     WHERE contact = 'seed-kevin@example.com' AND expected_at IS NULL;
   UPDATE queue_entry SET expected_at = '11:00:00'
     WHERE contact = 'seed-marcus@example.com' AND expected_at IS NULL;
   UPDATE queue_entry SET expected_at = '10:00:00'
     WHERE contact = 'seed-tanya@example.com' AND expected_at IS NULL;
   ```

2. **`api-contracts/src/queue_entries.rs`**
   - Add `use chrono::NaiveTime` to imports (line 5)
   - Add `pub expected_at: Option<NaiveTime>` to `CreateQueueEntryBody` (after `notes`)
   - Add `pub expected_at: Option<NaiveTime>` to `QueueEntryDto` (after `notes`, before `arrived_at`)
   - Add test: `create_body_deser_with_expected_at` — roundtrip with `"15:00:00"`
   - Add test: `dto_serde_roundtrip_with_expected_at` — verify NaiveTime survives JSON roundtrip

**Verify:** `cd server && cargo test -p api-contracts`

---

### Slice 2 — Server: domain model + POST handler + build pipeline

**Reasoning:** Server can't compile until the domain model matches the contract. This slice threads `expected_at` through every server-side layer: domain struct, database helper, SQL queries, DTO conversion, POST handler. The build-all gate at the end proves the full pipeline works.

**Files:**

1. **`server/api/src/types/queue_entries/queue_entry.rs`**
   - Add `use chrono::NaiveTime` to imports (line 3, extend chrono import)
   - `QueueEntry` struct: add `expected_at: Option<NaiveTime>` after `notes` (line 24)
   - Getter: `pub fn expected_at(&self) -> Option<NaiveTime> { self.expected_at }`
   - `DatabaseHelper` struct: add `expected_at: Option<NaiveTime>` after `notes` (line 63)
   - `DatabaseHelper::transform`: pass through `expected_at: self.expected_at` (line 87)
   - `QUEUE_ENTRY_COLS` (line 97-98): add `expected_at` after `notes` — **column order must match DatabaseHelper field order** (sqlx positional mapping)
   - `NewQueueEntry` struct (line 213): add `pub expected_at: Option<NaiveTime>`
   - `NewQueueEntry::into_db` (line 222-257): add `expected_at` to INSERT SQL columns + `?` placeholder + `.bind(&self.expected_at)` + field in returned `QueueEntry` (with `expected_at: self.expected_at`)
   - `From<&QueueEntry> for QueueEntryDto` (line 261-278): add `expected_at: q.expected_at()`
   - Update all 4 test `DatabaseHelper` constructions (lines ~300, ~330, ~352, ~377): add `expected_at: None`

2. **`server/api/src/api/queue_entries/queue_entries_post.rs`**
   - Add `expected_at: body.expected_at` to `NewQueueEntry` construction (line 41-48)

**Verify:**
```
cd server && cargo xtask build-all
cd server && cargo test -p uwz-api
```

---

### Slice 3 — Bridge: Tauri command + frontend types + commands.ts

**Reasoning:** The bridge layer connects server changes to the frontend. Tauri commands receive strings from the frontend and must parse NaiveTime. The TS types must match the new DTO shape. Completing this slice means the data can flow end-to-end, even though the UI doesn't use `expected_at` yet.

**Files:**

1. **`surface-command-center/src-tauri/src/commands/queue.rs`**
   - Add `use chrono::NaiveTime` to imports (line 1)
   - `create_queue_entry` (line 90-110): add param `expected_at: Option<String>`
   - Parse with fallback (HTML `<input type="time">` produces "HH:MM", serde produces "HH:MM:SS"):
     ```rust
     let expected_at = expected_at
         .map(|s| NaiveTime::parse_from_str(&s, "%H:%M:%S")
             .or_else(|_| NaiveTime::parse_from_str(&s, "%H:%M")))
         .transpose()
         .map_err(|e| e.to_string())?;
     ```
   - Include in `CreateQueueEntryBody { name, contact, party_size, date, notes, expected_at }`

2. **`surface-command-center/src/lib/types.ts`**
   - Add `expected_at: string | null` to `QueueEntryDto` interface (after `notes`, line 46)

3. **`surface-command-center/src/lib/api/commands.ts`**
   - `createQueueEntry` (line 62-70): add `expectedAt?: string` param
   - Pass through to invoke: `{ name, contact, partySize, date, notes, expectedAt }`

**Verify:** `cd surface-command-center && pnpm check`

---

### Slice 4 — Logic: ViewModel grouping + StatusDot primitive

**Reasoning:** The ViewModel is the brain of the UI. Adding grouping logic before the template rewrite means we can verify the computed derivations compile and produce correct shapes before touching any Svelte markup. StatusDot is a trivial primitive but needs to exist before the template can reference it.

**Files:**

1. **`surface-command-center/src/lib/components/queuePanel.svelte.ts`**

   Add `HourBlock` type export:
   ```typescript
   export interface HourBlock {
       label: string;        // "10:00–11:00" (en-dash)
       startHour: number;    // for sorting
       entries: QueueEntryDto[];
       headcount: number;    // sum of party_size
   }
   ```

   Add new derived computations:
   - `nonSkipped` — entries with status not in (complete, skipped, active), sorted by: tier (call-ahead first), then expected_at (nulls last), then id
   - `skipped` — entries with status === 'skipped'
   - `hourBlocks` — group `nonSkipped` (where expected_at is not null) by floor(hour), produce `HourBlock[]` sorted by startHour. **Parse hour with `parseInt(entry.expected_at!.slice(0, 2), 10)`** (NaiveTime serde format is "HH:MM:SS", first 2 chars are the hour).
   - `noTimeEntries` — nonSkipped entries where expected_at is null
   - `noTimeHeadcount` — sum of party_size across noTimeEntries
   - `totalHeadcount` — sum of party_size across nonSkipped
   - `skippedHeadcount` — sum of party_size across skipped

   Expose all through return object with getters.

   Extend `create()` signature: add `expectedAt?: string` param, pass to `createQueueEntry()`.

   **Keep `visible` and `entries` unchanged** — WalkUpTrack depends on `queueVM.entries` for active queue entries (+page.svelte:65).

2. **New file: `surface-command-center/src/lib/components/StatusDot.svelte`**

   Minimal colored circle primitive. Props: `variant: 'yellow' | 'green' | 'red'`, `filled: boolean` (default true).
   - `filled=true` → solid fill using `indicator-*-fg` tokens
   - `filled=false` → ring only (border, no fill) for skipped entries
   - Uses `satisfies Record<DotVariant, string>` for Tailwind token mappings (per style guide)
   - `aria-hidden="true"` — decorative, status conveyed by text/context

**Verify:** `cd surface-command-center && pnpm check`

---

### Slice 5 — Presentation: QueuePanel rewrite + QueueCreateModal time picker

**Reasoning:** This is the visual payoff. All data, types, and logic are in place from slices 1–4. This slice rewrites the QueuePanel template from cards to hour blocks and adds the time picker to the create modal. It's the largest single slice but it's pure presentation — if it breaks, nothing underneath is affected.

**Files:**

1. **`surface-command-center/src/routes/(app)/command-center/_components/QueuePanel.svelte`**

   **Header changes:**
   - Badge shows total headcount ("31 guests") instead of entry count
   - Keep add/refresh IconButtons, error badge

   **Body — new structure:**
   ```
   {#each vm.hourBlocks as block}
     HourBlockHeader: "10:00–11:00 ─── 12 guests"
     {#each block.entries as entry}
       EntryRow: time | name | ★? | party_size | StatusDot
       {#if selectedEntryId === entry.id}
         ActionStrip: contextual buttons
       {/if}
     {/each}
   {/each}

   {#if vm.noTimeEntries.length > 0}
     "No time" header
     {#each vm.noTimeEntries as entry}
       EntryRow (dash instead of time)
     {/each}
   {/if}

   {#if vm.skipped.length > 0}
     Collapsible "Skipped (N) · M guests" header
     {#if showSkipped}
       {#each vm.skipped as entry}
         EntryRow (hollow dot)
       {/each}
     {/if}
   {/if}
   ```

   **Entry row layout:** Single line, compact. `time | name | ★ (if call-ahead) | Np | StatusDot`. Hover: `bg-neutral-700/30`. Click: sets `selectedEntryId`, reveals action strip below.

   **Action strip (expanded below selected row):** Slim row with small buttons matching current actions: arrive/skip (waiting), activate/skip (arrived), unskip (skipped), complete (active). Same ViewModel methods. Same mutating/busy guards.

   **Interaction state:**
   - `selectedEntryId: number | null = $state(null)`
   - `showSkipped: boolean = $state(false)`
   - Reset `selectedEntryId` to null via `$effect` when `vm.entries` changes (30s poll may remove selected entry)

   **Accessibility (RT-8):** Rows get `tabindex="0"`, `role="button"`, `aria-expanded={selected}`. Enter/Space toggles. Escape closes.

   **Remove:** `ACTION_STYLES` constant, card layout (`rounded-lg bg-neutral-700/50 px-4 py-3`), segmented button bar, inline StatusBadge per entry, priority tier StatusBadge.

   **Keep:** onMount with 30s polling + `menu:new-queue-entry` listener, modal triggers (`showCreate`, `activatingEntry`), QueueCreateModal/QueueActivateModal imports and rendering, `confirmDeleteId` pattern.

2. **`surface-command-center/src/lib/components/QueueCreateModal.svelte`**

   Add optional time picker:
   - `let expectedTime = $state('')`
   - New field between Notes and error/buttons:
     ```svelte
     <label for="qc-expected">Expected arrival <span>(optional)</span></label>
     <input id="qc-expected" type="time" bind:value={expectedTime} />
     ```
   - On submit: pass `expectedTime || undefined` to `vm.create()`
   - Update `vm.create()` call to include the new parameter

**Verify:**
1. `cd surface-command-center && pnpm check` — TypeScript compiles
2. Start dev environment, open command center
3. Visual: seed data shows Kevin at 15:00, Marcus at 11:00, Tanya at 10:00 in hour blocks; walk-ups in "No time"
4. Click a row → action strip appears. Arrive/skip/activate work.
5. Skipped section collapses/expands
6. Create modal: entry with time → correct hour block. Entry without time → "No time" section.
7. Keyboard: Tab to rows, Enter to expand, Escape to close

---

## QC Checklist (run after all slices)

### Rust
- [ ] `NaiveTime` import present in api-contracts and server crate — verify `chrono` dep has `serde` feature
- [ ] `QUEUE_ENTRY_COLS` column order matches `DatabaseHelper` field order (sqlx positional)
- [ ] `NewQueueEntry::into_db` INSERT column count matches `?` placeholder count
- [ ] All 4 test `DatabaseHelper` constructions have `expected_at` field
- [ ] `QueueEntryDto` field order in `From` impl matches struct definition
- [ ] NaiveTime serde roundtrip test passes

### TypeScript/Svelte
- [ ] `QueueEntryDto` in `types.ts` includes `expected_at: string | null`
- [ ] ViewModel `nonSkipped` excludes complete, skipped, AND active
- [ ] ViewModel `entries` array remains unfiltered (WalkUpTrack dependency)
- [ ] HourBlock grouping: null expected_at → noTimeEntries, not hourBlocks
- [ ] Hour parsing: `parseInt(...)` not string slicing (handles "09:00:00" → 9)
- [ ] QueueCreateModal passes `"HH:MM"` string from `<input type="time">`
- [ ] `selectedEntryId` resets on data refresh
- [ ] Rows have tabindex, Enter expands, Escape closes

### Security
- [ ] No raw SQL interpolation — all sqlx bind
- [ ] NaiveTime parse rejects invalid values
- [ ] No error messages leaking internals
- [ ] Create endpoint auth unchanged
