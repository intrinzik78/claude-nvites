# UX/UI Development Workflow

Human-in-the-loop workflow for building Tauri + SvelteKit surfaces using MVVM with an MVC main controller. Design consistency is enforced through TypeScript's type system — not documentation, not conventions, not hope.

## Core Principle: Make Bad Design Unrepresentable

TypeScript is the enforcement layer. Design decisions are encoded as types. If a value isn't in the union, it doesn't compile. Treat UI the same way Rust treats state — invalid states are unrepresentable.

```typescript
// Design vocabulary — the ONLY valid values
type Spacing = 0 | 1 | 2 | 4 | 6 | 8 | 12 | 16;
type DepthLayer = "base" | "surface" | "elevated";
type TextScale = "xs" | "sm" | "base" | "lg" | "xl" | "2xl";
type FontWeight = 400 | 500 | 600 | 700;
type Intent = "neutral" | "primary" | "danger" | "warning" | "success";
type ComponentSize = "sm" | "md" | "lg";
type Radius = "none" | "sm" | "md" | "lg" | "full";
```

Tailwind classes are resolved **inside** primitives from typed props. No component ever writes a raw Tailwind class for design values — only primitives map types to classes:

```typescript
const gapClass: Record<Spacing, string> = {
  0: "gap-0", 1: "gap-1", 2: "gap-2", 4: "gap-4",
  6: "gap-6", 8: "gap-8", 12: "gap-12", 16: "gap-16",
};
```

## Architecture

### Two-Tier Layout Model

**Global layout** (`(app)/+layout.svelte`): The application shell. Owns sidebar, topbar, auth context, global commands, keyboard shortcuts, notifications. This is the MVC controller. One per surface.

**View layout** (`domain/+layout.svelte`): Each domain (bookings, customers, settings, etc.) is a mini-app with its own layout. Owns domain-level navigation, filters, and chrome. Every domain gets a view layout — even single-page domains — because domains grow.

```
App Shell (global +layout.svelte — MVC controller)
└── View (domain +layout.svelte — owns domain chrome)
    └── Pages (routes — composition only, zero styling)
```

### MVVM + MVC

- **Model**: SDK types, shared across surfaces
- **View**: Svelte components — composition and layout only, no business logic, no direct SDK calls
- **ViewModel**: `.svelte.ts` files — reactive state (`$state`, `$derived`), logic, SDK integration
- **Controller**: Global `+layout.svelte` — navigation, auth, shared context via Svelte context API (not prop drilling)

Views import ViewModels. ViewModels call the SDK. Views never touch the SDK directly (`sdk-only-access` principle).

### Component Layering

```
lib/
  components/           ← shared primitives (Button, Input, DataTable, etc.)
  types/ui/             ← design token types with barrel (index.ts)

routes/(app)/
  bookings/
    _components/        ← view-specific compositions
    bookings.svelte.ts  ← ViewModel
    +layout.svelte      ← view layout
    +page.svelte        ← page (composition only)
```

**Rules:**
1. `lib/components/` — shared primitives. Tailwind lives here and ONLY here.
2. `_components/` in view dirs — domain-specific compositions of primitives. Minimal direct Tailwind (layout arrangement only: grid, flex).
3. `+page.svelte` — composes view components, binds to ViewModel. Zero styling.
4. A component moves to `lib/` when a second view needs it. Not before.

### Route Structure

```
src/routes/
  (app)/
    +layout.svelte                ← global shell (MVC controller)

    dashboard/
      +layout.svelte              ← view layout
      +page.svelte

    bookings/
      +layout.svelte              ← view layout (list/calendar toggle, filters)
      +page.svelte                ← list
      calendar/+page.svelte       ← calendar view
      new/+page.svelte            ← create
      [id]/
        +layout.svelte            ← detail shell (header, tabs)
        +page.svelte              ← detail overview
        edit/+page.svelte         ← edit form

    customers/
      +layout.svelte              ← view layout
      +page.svelte                ← list
      [id]/+page.svelte           ← detail

    waivers/
      +layout.svelte              ← view layout
      +page.svelte

    pos/
      +layout.svelte              ← view layout
      +page.svelte

    settings/
      +layout.svelte              ← view layout (settings nav)
      +page.svelte                ← general
      users/+page.svelte
      pricing/+page.svelte

  (auth)/
    login/+page.svelte
```

## Workflow

### Stage 1: Route Map (Human-Led)

Define the application as a SvelteKit route tree. Every domain gets a view layout. This is the foundation.

### Stage 2: Intent + ViewModel Spec (Co-Authored)

Each route gets a structured spec — data, actions, and states. No visual details.

```
## /bookings
Intent: Staff views and manages today's bookings
ViewModel:
  - bookings: Booking[] (from SDK)
  - filter: "today" | "upcoming" | "past"
  - selectedId: string | null
Actions:
  - createBooking() → navigate to /bookings/new
  - cancelBooking(id) → confirm → SDK call → refresh
  - selectBooking(id) → navigate to /bookings/[id]
States: loading | empty | populated | error
```

### Stage 3: Visual Design (Human-Led)

Provide visual references. In order of effectiveness:

**Best inputs for Claude:**
- Figma screenshots/PNGs per screen (paste into Claude Code)
- Design tokens exported as JSON → Tailwind config
- Paper sketches photographed and pasted in
- ASCII layouts in the spec
- Vibes by reference ("dense like Linear, not airy like Notion")

**Do not use:**
- Figma CSS output (absolute-positioned, unusable)
- Figma developer mode code (wrong abstractions)
- Figma-to-code plugins (unmaintainable)

### Stage 4: Component Decomposition (Claude-Led)

Reverse-engineer each screen into a component tree:

```
Screen: /bookings
├── View: BookingsPage.svelte (composition only)
│   ├── BookingFilters → uses: Select, ButtonGroup
│   ├── BookingTable → uses: DataTable, Badge, StatusIndicator
│   │   └── BookingRow → uses: TableRow, Button
│   └── EmptyState | ErrorState (conditional)
├── ViewModel: bookings.svelte.ts
│   └── SDK methods, reactive state
└── Model: SDK types (Booking, BookingStatus)
```

Every leaf must trace back to a `lib/components/` primitive or be identified as a new primitive to build.

### Stage 5: Design Tokens as Types (Co-Authored)

Define the design system as TypeScript types + Tailwind resolution maps. This is where enforcement happens. Types live in `lib/types/ui/` as individual files with a barrel (`lib/types/ui/index.ts`). Resolution maps are defined inline in each component via `satisfies Record<Type, string>` — not in a centralized file, because the same type maps to different Tailwind in different component contexts. Surfaces implement these types as `@theme` CSS tokens in `app.css` (e.g., `DepthLayer` → `--color-depth-base`, `--color-depth-surface`, `--color-depth-elevated`), giving component mappings semantic utilities instead of raw palette classes.

### Stage 6: Build Primitives (Claude-Led)

Build leaf components: Button, Input, Card, Badge, StatusIndicator, DataTable, Select, Modal, EmptyState, ErrorState.

Each primitive:
- Typed props using design system types (no `string` where a union exists)
- All states handled (default, hover, focus, loading, error, disabled)
- Resolves types to Tailwind internally
- Scoped CSS only where Tailwind can't reach

### Stage 7: Compose Screens (Claude-Led)

Pages compose view components. View components compose primitives. No new Tailwind at the page level. If a page needs styling, it's missing a component.

### Stage 8: Screenshot Review (Human-Led)

Paste rendered screenshots into Claude Code. Claude iterates on what it actually sees. This closes the feedback loop.

## UX Spec Template

```
## Screen: [Name]
Route: /path
Purpose: [One sentence]
User: [Who, what goal]

### Layout
- [ASCII sketch or grid/flex description]
- Depth layer: base | surface | elevated

### Components (leaf-first)
- ComponentName: [what it does]
  Props: { intent: Intent; size: ComponentSize; ... }
  States: default, hover, loading, error, empty, disabled

### Interactions
- [trigger] → [action] → [result]

### Data
- Inputs: [data, source (SDK method)]
- Outputs: [events/actions emitted]
```

## Ownership Summary

| Stage | Owner | Output |
|-------|-------|--------|
| 1. Route map | Human | Route tree |
| 2. Intent + ViewModel | Co-authored | Structured specs per route |
| 3. Visual design | Human | PNGs / sketches / token refs |
| 4. Component decomposition | Claude | Component trees tracing to primitives |
| 5. Design tokens as types | Co-authored | `lib/types/ui/` types + inline `satisfies` maps |
| 6. Primitives | Claude | Typed leaf components |
| 7. Screens | Claude | Composed views, zero direct styling |
| 8. Screenshot review | Human | Visual feedback → iterate |
