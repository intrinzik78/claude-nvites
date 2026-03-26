# Desktop App UX/UI Architecture

Architecture and workflow for Tauri 2 + SvelteKit desktop surfaces. Applies to `surface-command-center`, `surface-member`, and any future `surface-*` Tauri app.

For Svelte code conventions (runes, props, TypeScript, component structure), see `docs/SVELTE_STYLE_GUIDE.md`. This document covers architecture, data flow, and the build workflow — not how to write Svelte.

## Core Constraint: There Is No Server

Tauri surfaces compile to static desktop apps. There is no Node.js server at runtime.

- `adapter-static` in `svelte.config.js`
- `+layout.ts` at root: `export const ssr = false; export const prerender = true;`
- **No `+page.server.ts`** — these won't compile. There is no server to run them.
- **No `+server.ts` BFF endpoints** — same reason.
- **No `$env/static/private`** — env vars live on the Rust side.
- **No `sdk-ts` imports** — web SDK uses HTTP fetch. Desktop surfaces use `sdk-rust` via Tauri IPC.
- **No HTTP-only cookies** — auth is Rust-side, not browser-side.

Every instinct to create a server load function, a BFF endpoint, or a cookie-based auth flow is wrong here.

## Architecture

### Data Flow: Tauri IPC

All data flows through Tauri's `invoke()` bridge:

```
Svelte Component → ViewModel (.svelte.ts) → invoke('command_name', { args })
                                                    ↓
                                              Tauri Rust handler
                                              (src-tauri/src/commands/)
                                                    ↓
                                              sdk-rust → HTTP → server
```

**The command layer** lives in two places that must stay in sync:

1. **Rust handlers** — `src-tauri/src/commands/*.rs`. Registered in `main.rs` via `invoke_handler`. Each handler takes typed args, calls the SDK client, returns typed responses.
2. **TypeScript wrappers** — `src/lib/api/commands.ts`. Typed functions that call `invoke()` with the correct command name and args. Components never call `invoke()` directly.

```typescript
// src/lib/api/commands.ts
import { invoke } from '@tauri-apps/api/core';
import type { BookingDto } from '@uwz/api-contracts';

export async function getBookings(date: string): Promise<BookingDto[]> {
    return invoke('get_bookings', { date });
}
```

```rust
// src-tauri/src/commands/bookings.rs
#[tauri::command]
async fn get_bookings(
    state: tauri::State<'_, AppState>,
    date: String,
) -> Result<Vec<BookingDto>, String> {
    let client = state.client.lock().await;
    client.bookings().list_by_date(&date).await
        .map_err(|e| e.to_string())
}
```

New features require **both** — a Rust handler and a TS wrapper. Missing either side is a build error or a runtime panic.

### Auth Model

The bearer token never touches JavaScript. It lives in Rust:

```
Login form → invoke('login', { email, password })
                    ↓
          Rust stores token in AppState (Mutex<Client>)
                    ↓
          All subsequent invoke() calls use the stored client
                    ↓
          On 401: Rust emits Tauri event → frontend redirects to login
```

- `AppState` holds a `Mutex<Client>` — the SDK client with the bearer token.
- Frontend knows login state and username, never the token itself.
- `(auth)/` route group for login. `(app)/` route group for authenticated content.
- Role/permissions fetched post-login via `getSessionMe()`, stored in Svelte context.

### Svelte Context for Auth & State

Svelte 5's `setContext` must be called synchronously during component init. Auth context is created empty during init, then populated async:

```typescript
// src/lib/authContext.svelte.ts
export function createAuthContext() {
    let username = $state('');
    let role = $state<string | undefined>(undefined);

    return {
        get username() { return username; },
        get role() { return role; },
        async load(session: SessionMeDto) {
            username = session.username;
            role = session.role ?? undefined;
        },
        clear() {
            username = '';
            role = undefined;
        }
    };
}

// In +layout.svelte — synchronous init, async load
const auth = createAuthContext();
setContext('auth', auth);

onMount(async () => {
    try {
        const session = await getSessionMe();
        auth.load(session);
    } catch {
        // Role fetch failure is non-fatal — app loads with empty nav
    }
});
```

Calling `setContext` inside an async callback triggers `lifecycle_outside_component`. This pattern applies to any Svelte 5 context that depends on async data.

### MVVM + MVC

Same conceptual model as web surfaces, different transport:

- **Model**: api-contracts types (shared DTOs)
- **View**: Svelte components — composition and layout, no direct `invoke()` calls
- **ViewModel**: `.svelte.ts` files — reactive state (`$state`, `$derived`), calls command wrappers
- **Controller**: Global `(app)/+layout.svelte` — shell, auth context, navigation, keyboard shortcuts

Views import ViewModels. ViewModels call command wrappers. Views never call `invoke()` directly.

### ViewModel Convention

Every data-displaying component has a co-located `.svelte.ts` file:

```
src/lib/components/
    BookingList.svelte          ← View
    bookingList.svelte.ts       ← ViewModel
```

ViewModels own `$state` for data, `$derived` for computed values, and expose methods that call the command layer:

```typescript
// bookingList.svelte.ts
import { getBookings } from '$lib/api/commands';

export function createBookingListVM() {
    let bookings = $state<BookingDto[]>([]);
    let loading = $state(false);
    let error = $state('');

    let confirmed = $derived(bookings.filter(b => b.status === 'confirmed'));

    async function loadForDate(date: string) {
        loading = true;
        error = '';
        try {
            bookings = await getBookings(date);
        } catch (e) {
            error = e instanceof Error ? e.message : 'Failed to load bookings';
        } finally {
            loading = false;
        }
    }

    return {
        get bookings() { return bookings; },
        get confirmed() { return confirmed; },
        get loading() { return loading; },
        get error() { return error; },
        loadForDate,
    };
}
```

There is no SSR fallback path. Every route is client-rendered. Every data display needs a ViewModel.

### Component Layering

```
src/lib/
    components/       ← shared primitives (typed props, Tailwind containment)
    api/              ← command wrappers (invoke bridge)
    types/ui/         ← design token types with barrel (index.ts)

src/routes/(app)/
    bookings/
        _components/        ← domain-specific compositions of primitives
        bookings.svelte.ts  ← ViewModel
        +layout.svelte      ← domain chrome
        +page.svelte         ← composition only, zero styling
```

**Rules:**
1. `lib/components/` — shared primitives. Tailwind lives here and ONLY here.
2. `_components/` in route dirs — domain compositions. Layout-only Tailwind (grid, flex, gap).
3. `+page.svelte` — composes view components, binds to ViewModel. Zero styling.
4. A component promotes to `lib/` when a second domain needs it. Not before.

### Two-Tier Layout

**Global layout** (`(app)/+layout.svelte`): The application shell. Owns sidebar, menu bar, auth context, global commands, keyboard shortcuts. This is the MVC controller.

**Domain layout** (`domain/+layout.svelte`): Each domain is a mini-app. Owns domain-level navigation, filters, and chrome. Every domain gets a layout — even single-page domains — because domains grow.

```
App Shell (global +layout.svelte)
└── Domain (domain +layout.svelte — owns domain chrome)
    └── Pages (routes — composition only, zero styling)
```

## Desktop-Specific Patterns

### No Responsive Breakpoints

Desktop window, 1024x768 minimum. Design for the window, not for mobile. `sm:` and `md:` breakpoints are wrong — they imply a mobile-up strategy that doesn't apply.

### Menu Lifecycle

Native menus are frontend-driven. `showAppMenu()` after auth resolves, `hideAppMenu()` on sign-out. App starts with an empty menu. `on_menu_event` is registered once in Tauri `setup()` and survives menu rebuilds.

### Keyboard Shortcuts

Desktop apps are keyboard-heavy. Common operations should have shortcuts registered in the global layout. Domain-specific shortcuts register in domain layouts and clean up on navigation.

### Role-Based UI

Role from Svelte context via `$derived`. Additive model: operator base → editor adds → admin adds.

**Gate controls, never data.** Every role sees the same data. Role determines which buttons, actions, and menu items are visible. `actions_by_role` in the surface config defines the authorization model.

### Polling & Live Data

Active views may poll for fresh data (e.g., 30-second interval for queue status). Inactive/completed views are static — no polling. Use `$effect` with cleanup for poll intervals:

```typescript
$effect((): void | (() => void) => {
    if (isActiveView) {
        const interval = setInterval(() => refresh(), 30_000);
        return () => clearInterval(interval);
    }
});
```

## Build Workflow

Adapted from the 8-stage web workflow for desktop constraints.

### Stage 1: Route Map (Human-Led)
Define the SvelteKit route tree. Every domain gets a layout.

### Stage 2: Intent + ViewModel Spec (Co-Authored)
Each route gets: data (from which Tauri commands), actions (which commands to call), states (loading/empty/populated/error).

### Stage 3: Visual Design (Human-Led)
Figma screenshots, reference app screenshots, design tokens. The surface skill defines the visual identity — this doc doesn't.

### Stage 4: Component Decomposition (Claude-Led)
Reverse-engineer screens into component trees. Every leaf traces to a `lib/components/` primitive.

### Stage 5: Command Layer (Co-Authored)
Define which Tauri commands are needed. Write both the Rust handlers and TS wrappers before building UI.

### Stage 6: Build Primitives (Claude-Led)
Typed props, all states handled, Tailwind resolved internally. The surface skill defines the design vocabulary.

### Stage 7: Compose Screens (Claude-Led)
Pages compose view components. No new Tailwind at the page level.

### Stage 8: Screenshot Review (Human-Led)
Paste rendered screenshots. Iterate on what you see.

## Ownership Summary

| Stage | Owner | Output |
|-------|-------|--------|
| 1. Route map | Human | Route tree |
| 2. Intent + ViewModel | Co-authored | Specs per route |
| 3. Visual design | Human | PNGs / sketches / token refs |
| 4. Component decomposition | Claude | Component trees |
| 5. Command layer | Co-authored | Rust handlers + TS wrappers |
| 6. Primitives | Claude | Typed leaf components |
| 7. Screens | Claude | Composed views |
| 8. Screenshot review | Human | Visual feedback → iterate |
