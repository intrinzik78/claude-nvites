---
name: frontend-command-center
description: Build the UWZ staff command center (Tauri desktop). Enforces "beautiful utilitarian" design, IPC data loading, and operational UI patterns for surface-command-center.
---

# Frontend Command Center

Every screen is a **cockpit** — dense, precise, crafted for the hands that use it all day.
Every component reminds the user of a **swiss chronometer** — bezel, recess, outlines, color choices, depth, motion, all implemented beautifully. From the subtlest of shadows to the boldest of features, nothing feels out of place.

## References

Read these before building. They cover code conventions, component workflow, and route structure — this skill won't repeat them.

- `docs/SVELTE_STYLE_GUIDE.md` — Svelte code conventions, component patterns, TypeScript, Tailwind containment, component-owned design token mappings
- `docs/APP_UX.md` — Tauri desktop architecture, MVVM, data loading via IPC, auth model
- `route-map.json` (monorepo root) — routes, endpoints, data models, navigation, booking/queue/order lifecycle state machines
- `command-center.json` (monorepo root) — check-in group entity, 8-state service machine, split mechanics, `actions_by_role` operational model

**Stack:** SvelteKit + Svelte 5 + Tailwind 4 + TypeScript strict + Tauri 2.
**Surface:** Staff-only — operator, editor, admin roles.
**Scaffold:** `../worktrees/surface-command-center/surface-command-center/src/`

## Before You Build

**What does the operator see first?** The one thing that answers "is everything OK?" in under a second. Build the hierarchy around that answer.

Read `docs/screenshots/` before writing code — screenshots override written rules when they conflict:
- `components.png` — Figma design vocabulary: button forms, filter pills, gauges, typography scale
- `container.png` — Shell layout: sidebar, content area, toolbar, menu bar (authoritative)
- `list-01.png`, `list-02.png` — Linear list density and typographic hierarchy (quality target for data rows)
- `settings-01.png` — Linear grouped controls (quality target for settings/config views)
- `state-01.png`, `state-02.png` — Linear filter bars and view controls (quality target for toolbars)
- `colors-shapes-containers.png` — Depth layers and color swatches
- `icons.png`, `menu.png` — Icon set and menu bar reference

When a micro-decision isn't covered below, match the precision visible in these references.

## Visual Identity — Locked

- **Dark palette** — Zinc (cool blue-gray), not neutral. `--color-base` (oklch 18% 0.01 275) app background, `zinc-900` domain layouts, `zinc-900` panel surfaces, `zinc-700` borders. The `base` token lives in `app.css` and is set on the `(app)` layout.
- **Atmospheric texture in the chrome, not in data.** Grain, frosted glass, subtle depth belong in the shell — sidebar, toolbar, panel borders, modal overlays. Data rows and content areas stay clean.
- **Fonts** — Three-tier type system: **Shrikhand** (`--font-family-title`) for internal page titles (h1), **Sarpanch** (`--font-family-label`) for data titles, labels, and external-facing brand (h3-h6, login), **Sulphur Point** (`--font-family-body`) for body text. CSS custom properties defined in `app.css`. No BlackOpsOne — that's the customer-facing voice.
- **Accent indigo** — the primary saturated color at oklch hue 275. Defined as oklch tokens in `app.css` (`--color-accent`, `--color-accent-fg`, `--color-accent-ring`, etc.). Used for primary actions, focus states, and filter indicators. **Token caveat:** Tailwind 4 does not reliably generate `text-accent-fg` utilities from `@theme` tokens. Use `style:color="var(--color-accent-fg)"` for static elements or `[color:var(--color-accent-fg)]` in dynamic class ternaries. Background utilities (`bg-accent`) work normally.
- **Cream text** — `--color-cream` (oklch 92% 0.02 75) replaces pure white for all readable text (dial markings). Pure `text-white` reserved for small marks on `bg-accent` surfaces (lume points — checkmarks, selected items, active breadcrumbs). Use `text-cream` for names, counts, headings, form inputs, hover targets.
- **Semantic status colors** (green, yellow, red) — defined as indicator tokens in `app.css`. Appear ONLY in `StatusBadge` and `StatusDot`. Never structural, never as backgrounds or section colors.
- **No amber, blue, or sky** — these colors have no place in the palette. Split indicators use accent-fg, remainder badges use neutral zinc, step type labels use neutral zinc, status banners use neutral zinc. If you're reaching for a warm or cool accent that isn't indigo, stop.
- **Depth: recessed panels** — `zinc-900` background + `zinc-900` panels with `border-zinc-700/40` + `shadow-[inset_0_2px_6px_rgba(0,0,0,0.25)]`. Panels are recessed wells, not raised surfaces. `elevated` reserved for modals/overlays. Elevation through border opacity and inset shadow, not background lightness.
- **Shell layout** — Sidebar + main content + bottom toolbar + top menu bar (per `container.png`). Menu bar: Create | Edit | Tools | Game | Account | Settings.
- **Component forms from Figma** — Round action buttons, filter pills, gauges. These are the designed forms (`components.png`); use them, don't substitute generic rectangles.

## Component Vocabulary

Use existing components before creating new ones. New components match their energy.

Directory structure: `src/lib/components/` with subdirectories `buttons/`, `forms/`, `layout/`, `nav/`, `widgets/`.

| Component | Purpose |
|-----------|---------|
| `layout/Panel` | Depth-layered container (`base` / `surface` / `elevated`) |
| `SequenceBar` | Workflow step progression — the indicator light pattern |
| `StatusBadge` | Domain-aware status pill (booking, instance, queue, waiver, etc.) |
| `StatusDot` | Minimal point status indicator |
| `buttons/FilterPill` | Toggle filter — accent *text* when active, muted text when inactive. No background fill change. |
| `buttons/ToggleGroup` | Recessed bezel wrapper for filter clusters (inset shadow + hairline border) |
| `buttons/ActionButton` | Instrument-panel control — `bg-zinc-800` + `border-zinc-700/20` surface, text-color-only variants: `primary` (accent-fg text + accent-ring border), `neutral` (zinc-300), `success`/`danger`/`warning` (semantic text). Matches FilterPill material. |
| `buttons/IconButton` | Compact icon-only action |
| `widgets/Gauge` | Operational metric display |
| `nav/BreadcrumbBar` | Navigation breadcrumbs with active/inactive states |
| `DatePicker` | Date selection control |
| `ErrorAlert` | Inline error display |
| `Badge` | General-purpose count/label badge |
| `forms/Select`, `forms/TextInput` | Form primitives |

## Design Patterns

### The Data Row — Not a Table

**Reference:** `list-01.png`. Rows are continuous content lines, not grid cells. Typographic weight creates hierarchy. 1px `border-zinc-700` separators. No zebra striping, no cell borders.

```svelte
<!-- Target pattern: a booking row -->
<div class="flex items-center justify-between px-4 py-3
            border-b border-zinc-700
            hover:bg-zinc-700/25 cursor-pointer transition-colors duration-100">
  <div class="flex flex-col gap-0.5">
    <span class="font-[family-name:var(--font-family-label)] text-white">
      {booking.guest_name}
    </span>
    <span class="text-sm text-zinc-500">{booking.guest_email}</span>
  </div>
  <div class="flex items-center gap-4">
    <span class="text-sm text-zinc-400">{formatTime(booking.start_at)}</span>
    <StatusBadge status={booking.status} domain="booking" />
  </div>
</div>
```

### Grouped Controls

**Reference:** `settings-01.png`. Section header above grouped rows. Within groups: subtle dividers. Between groups: 24-32px whitespace. Controls right-aligned, labels left-aligned.

```svelte
<!-- Target pattern: a settings section -->
<div class="space-y-6">
  <div>
    <h3 class="font-[family-name:var(--font-family-label)] text-white text-sm">
      Notifications
    </h3>
    <p class="text-sm text-zinc-500 mt-1">
      Applies across all connected devices.
    </p>
  </div>
  <div class="divide-y divide-zinc-700 rounded-lg bg-zinc-800">
    {#each settings as setting}
      <div class="flex items-center justify-between px-4 py-3">
        <div>
          <div class="font-medium text-white">{setting.label}</div>
          <div class="text-sm text-zinc-500">{setting.description}</div>
        </div>
        <Toggle bind:checked={setting.enabled} />
      </div>
    {/each}
  </div>
</div>
```

### Workflow Progression — Indicator Lights

Single-color inversion system via `SequenceBar`. Three visual states:

- **Completed:** Accent bg + dark text (the lit lamp)
- **Current:** Dark bg + accent border + accent text (the active step)
- **Pending:** Dark bg + muted text (the unlit lamp)

Cancelled states: red replaces accent. This pattern applies to sequential workflow steps only — status badges use semantic colors (green/yellow/red) for categorical recognition.

### Border Nesting Rule — Decreasing Contrast Gradient

Border opacity scales inversely with nesting depth. Outer containers define boundaries; inner containers suggest structure. If every layer screams "I'm a box," the hierarchy flattens.

| Depth | Context | Border |
|-------|---------|--------|
| 0 | Panel (top-level container) | `border-zinc-700/40` |
| 1 | Control group inside a panel (ToggleGroup, bezels) | `border-zinc-700/20` |
| 2+ | Element inside a control group | `border-zinc-700/10` or none |

**Exception:** A bezel that sits *outside* a panel (e.g., BookingSearch in the header bar) uses depth-0 opacity (`/40`) since it is the outermost container.

### Filter & Tab Bars — The Instrument Cluster

**Reference:** `filters.png`, `state-01.png`, `state-02.png`. Filters are **text-color indicators**, not filled buttons. Three-layer depth like a Swiss chronometer:

1. **Bezel** (ToggleGroup) — `border-zinc-700/20` + `shadow-[inset_0_1px_3px_rgba(0,0,0,0.3)]`. A recessed channel that groups the cluster. Uses depth-1 border when nested inside a panel; depth-0 (`/40`) when standalone.
2. **Dial** (FilterPill) — `bg-zinc-800`, `rounded-lg`. Visible surface segments sitting in the bezel — one step lighter than the panel to read as distinct controls.
3. **Hand** (active text) — `accent-fg` via `style:color` directive. The single mark of intentional color.

Inactive text: `text-zinc-500`, hover to `text-zinc-300`. No background fill changes between states.

The bezel can wrap just toggle pills (ToggleGroup) or an entire control bar (BookingSearch wraps pills + date picker + select + search button in one bezel). Use `FilterPill` for toggle filters, `ToggleGroup` for mutually exclusive pill groups within a larger bar.

### Typography as Hierarchy

Weight and size differences must be decisive, not subtle.

- **Primary data** — `font-family-label`, `text-white`. The operator's eye finds this first.
- **Secondary data** — `font-family-body`, `text-zinc-400`. Present but receding.
- **Section headers** — `font-family-label`, uppercase, reduced size, `text-zinc-500`, generous letter-spacing.
- **Size floor:** interactive elements never below `text-base` (18px). Body/metadata can use `text-sm` (14px) but no smaller.
- **Squint test:** if you can't instantly distinguish title from metadata, the hierarchy has failed.

### Spacing Grid

8px base grid. Density is a feature — breathing room lives between sections, not within them.

- **Within a row:** `gap-2` (8px)
- **Between rows:** 1px border or `gap-1` (4px)
- **Between sections:** `gap-6` (24px) to `gap-8` (32px)
- **Panel padding:** `p-4` (16px)

### Color Discipline

Nearly monochrome. 1-2 saturated elements per view, maximum.

- **Accent indigo** — structural, not decorative. Active filters, primary actions, focus rings.
- **Semantic status** — ONLY in `StatusBadge`/`StatusDot`. Never backgrounds or section colors.
- **Red** — destructive actions only, confirmation-gated.
- **Everything else is neutral.** If you're reaching for a color not listed above, stop.

**Intensity scales inversely with surface area.** Small elements (dots, badges) use full saturation. Large surfaces step down one shade or add opacity.

**Accent text visibility floor:** `accent-fg` must be oklch 75%+ lightness and 0.15+ chroma to read on near-black backgrounds. Lower values appear as dark gray, not colored text.

### Interaction & Motion

Motion confirms, never entertains. Duration ceiling: 250ms.

- Row hover: `transition-colors duration-100`, `bg-zinc-700/25` — a breath of lightness, not a highlight
- Row selected: `bg-zinc-700/40` — distinct from hover, used for expandable rows (e.g., QueuePanel action strip)
- State transitions: 150ms ease
- Filter changes: fade out 100ms, fade in 150ms, no layout jump
- Panel open/close: slide + fade, 200ms

### Instrument Panel — Detail View Pattern

Detail views (CheckInFlow, future detail pages) use a single bordered container with three divider-separated zones:

1. **Gauge face** — compact summary (SequenceBar, key metrics). `px-6 pt-5 pb-4`.
2. **Readout** — detailed content (step list, data fields). `border-t border-zinc-700/30 px-6 py-5`.
3. **Controls** — action buttons or inline sub-panels. `border-t border-zinc-700/30 px-6 py-4`.

Container: `rounded-lg border border-zinc-700/40 bg-zinc-800 shadow-[inset_0_2px_6px_rgba(0,0,0,0.25)]`. The `border-zinc-700/30` dividers are depth-1 (inside a panel) — subtle zone suggestions, not hard boundaries.

Sub-panels (like SplitPanel) render inline as control zone content, not as standalone Panel components. The instrument panel is one piece.

### Tray Pattern — Expandable Sub-Rows

When a list row expands to show children (split groups, action strips), the expansion is a tray:

- `rounded-b-lg` — squared top anchors to parent row, rounded bottom closes the tray
- `border border-zinc-700/20` — depth-1 bezel
- `shadow-[inset_0_3px_4px_rgba(0,0,0,0.35)]` — top inset shadow (recessed under parent)
- `transition:slide={{ duration: 150 }}` — drawer opens/closes

Used by: BookingList/WalkUpTrack split group expansion, QueuePanel action strip.

### Empty, Loading, Error

- **Empty:** centered message + contextual action ("No bookings for March 15"), not a blank void.
- **Loading:** skeleton shapes matching actual layout. Never a centered spinner replacing the view.
- **Error:** persistent, inline, non-modal. `ErrorAlert` with retry. Rest of view stays visible.

## Anti-Patterns

**What kills the vibe:**
- `<table>` with uniform cells — use content rows with typographic hierarchy
- Marketing padding / sparse layouts — density is a feature
- Rainbow state machines — use the indicator light inversion pattern
- Theatrical motion — staggered entrances, parallax, scroll choreography
- Tiny click targets — operators move fast, possibly wearing gloves
- Generic rectangles — the Figma round buttons, pills, and gauges exist

**Trained instincts that are wrong here:**
- **Creating `+page.server.ts` or `+server.ts`** — no server. All data via Tauri `invoke()`.
- **Starting with `sm:` / `md:` breakpoints** — desktop window, 1024x768+.
- **Filtering data by role** — role gates controls (buttons, actions), never data visibility.
- **Reaching for green/yellow/red on new components** — status colors live in `StatusBadge`/`StatusDot` only.

## Command-Center-Specific Rules

### Data Loading — Tauri IPC

- `+layout.ts` at root: `export const ssr = false; export const prerender = true;`
- All data via `invoke()` in `src/lib/api/commands.ts` — typed wrappers around Tauri commands
- New API calls require BOTH a Rust handler in `src-tauri/src/commands/` AND a TS wrapper in `commands.ts`

**ViewModel convention:** Every data-displaying component has a co-located `.svelte.ts` file (e.g., `bookingList.svelte.ts` beside `BookingList.svelte`). ViewModels own `$state` for data, `$derived` for computed values, and call `invoke()` for loading. No SSR fallback path.

### Auth Model

- Tauri Rust side holds bearer token in `AppState` (`Mutex<Client>`)
- Frontend knows login state + username, never touches the token
- `(auth)/` group for login, `(app)/` group for authenticated content
- Role/permissions fetched post-login via dedicated command, stored in Svelte context (`authContext.svelte.ts`)
- Token expiry: Rust side intercepts 401s and emits Tauri event -> frontend redirects to login

### Role-Based UI

- Role from Svelte context -> `$derived` visible affordances. Additive: operator base -> editor adds -> admin adds.
- Never hide data by role — only controls/actions. See `command-center.json` `actions_by_role`.

### State Machine UI

- Reference `command-center.json` for the expanded 8-state service machine + check-in group model
- `SequenceBar` displays workflow progression using the indicator light pattern
- Advance/revert buttons role-gated
- Split mechanics: visual expansion of a booking line into child groups, each with independent state tracking

### Navigation & Desktop Affordances

- `DateNavigator` with `?date=` param is the primary temporal control — operators flip between days constantly. Default: today.
- `?from=` param for contextual back buttons on drill-downs (booking detail, queue detail, group detail)
- `DrillLink` component appends `?from=` automatically
- Keyboard shortcuts for common ops (advance state, toggle photos_taken, DateNavigator prev/next)

### Hard Boundaries

- No HTTP-only cookies — auth is Rust-side
- No `$env/static/private` — env vars are Rust-side
- No `sdk-ts` imports — this surface uses `sdk-rust` via Tauri commands
- No website component imports — each surface owns its own `lib/components/`

$ARGUMENTS
