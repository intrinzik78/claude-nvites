# Svelte 5 Style Guide

> Shared code conventions for Svelte surfaces. This document covers how to write code, not what to build. Surface-specific concerns (data fetching, rendering strategy, platform APIs) live in the corresponding surface skill.

---

## Table of Contents

1. [Project Structure](#project-structure)
2. [Component Patterns](#component-patterns)
3. [Svelte 5 Runes](#svelte-5-runes)
4. [TypeScript Conventions](#typescript-conventions)
5. [State Management](#state-management)
6. [API Integration](#api-integration)
7. [Styling](#styling)
8. [Navigation & Routing](#navigation--routing)
9. [Error Handling](#error-handling)
10. [Testing](#testing)
11. [Strengths (Lean On Developer)](#strengths)
12. [Weaknesses (Claude Should Supplement)](#weaknesses)

---

## Project Structure

**Pattern: Hybrid — type-based subdirectories with component-owned mappings**

```
src/
  lib/
    api/              # Surface-specific API layer (HTTP fetch, SDK, IPC — varies by surface)
    components/       # Shared primitives grouped by type
      buttons/
      cards/
      forms/
      layout/
      nav/
      section/
      spinners/
      alerts/
      errors/
    icons/            # SVG icon library
    text/             # Typography utilities
    types/
      ui/             # Design token union types (barrel: index.ts)
      ...             # Domain types (server models, API shapes)
    utils/            # Pure utility functions
  routes/
    (auth)/           # Login flow (unauthenticated)
    (app)/            # Main authenticated app
      domain/
        _components/        # Domain-specific compositions
        domain.svelte.ts    # ViewModel
        +layout.svelte      # Domain chrome
        +page.svelte        # Composition only, zero styling
```

**Conventions:**
- Components: `PascalCase.svelte`
- Logic files: `ComponentName.logic.ts` (co-located with component)
- Rune state files: `*.svelte.ts` (e.g., `FetchState.svelte.ts`)
- Types: `PascalCase.ts` in `types/` directory
- Utils: `camelCase.ts` in `utils/` directory

**Design token types:**
- All design token union types live in `lib/types/ui/` as individual files with a barrel (`lib/types/ui/index.ts`)
- Import via `import type { Padding, ColorVariant } from '$lib/types/ui'`
- Domain types (server models, API shapes) stay in `lib/types/` alongside `ui/`

**Component-owned mappings (no centralized `mappings.ts`):**
- Each component defines its own `satisfies Record<Type, string>` inline
- The same type legitimately resolves to different Tailwind in different components (e.g., `Padding: 'sm'` → `'py-0 md:py-1 px-0 md:px-4'` in `SectionWrapper` vs `'p-0.5'` in `CardWrapper`)
- A centralized mappings file either forces uniform resolution or namespaces by component — both are worse than colocation

**`_components/` convention:**
- Domain-specific compositions live in `_components/` within route directories
- These compose `lib/components/` primitives for a specific domain context
- A component promotes to `lib/components/` when a second domain needs it — not before
- `_components/` get layout-only Tailwind (grid, flex, gap) — no design token resolution

**Per-domain `+layout.svelte`:**
- Every domain gets its own `+layout.svelte`, even single-page domains
- Domain layouts own domain-level navigation, filters, and chrome
- Domains grow — the layout is ready when they do

---

## Component Patterns

### Standard Component Structure

```svelte
<script lang="ts">
    // 1. Type imports
    import type { ColorVariant } from '$lib/types/ui';
    import type { Snippet } from 'svelte';

    // 2. Props interface (inline, not exported)
    interface Props {
        title: string;
        tone?: ColorVariant;
        style?: string;          // escape hatch for one-off overrides
        children?: Snippet;
    }

    // 3. Props destructuring with defaults
    let { title, tone = 'dark', style, children }: Props = $props();

    // 4. Component-owned mapping — inline, not imported from a central file
    //    Values below are illustrative. Surfaces with @theme tokens
    //    use their own palette (e.g., bg-depth-base, text-accent-fg).
    const toneClasses = {
        white: 'bg-white text-zinc-900',
        black: 'bg-black text-white',
        light: 'bg-zinc-100 text-zinc-900',
        dark:  'bg-zinc-800 text-zinc-50',
        muted: 'bg-zinc-300 text-zinc-800',
        brand: 'bg-emerald-950 text-amber-50',
    } satisfies Record<ColorVariant, string>;

    // 5. Derived/computed values
    const classes = $derived(toneClasses[tone]);
</script>

<!-- 6. Markup -->
<div class={classes} {style}>
    <h2>{title}</h2>
    {#if children}
        {@render children()}
    {/if}
</div>

<!-- 7. Scoped styles (when needed beyond Tailwind) -->
<style>
    /* component-specific styles */
</style>
```

### Props Pattern

- Always define an `interface Props` inside the `<script>` block
- Use `$props()` rune for destructuring
- Provide sensible defaults for optional props
- Callback functions passed as props (not custom events)
- **Page component carve-out:** Page components (`+page.svelte`) rely on SvelteKit's auto-generated types from `./$types`. Explicit `interface Props` is not required — the types flow from `+page.server.ts` automatically. Reusable components (everything in `lib/components/`, `_components/`, icons) must always define `interface Props`.

```svelte
interface Props {
    onSave(data: ProjectFormData): void;
    onCancel(): void;
    errorMessage: string;
    isError: boolean;
    isLoading: boolean;
}

let { onSave, onCancel, errorMessage, isError, isLoading }: Props = $props();
```

### Children / Snippets

```svelte
<!-- Rendering children -->
{#if children}
    {@render children()}
{:else}
    {fallbackContent}
{/if}
```

### Dynamic Elements

```svelte
<!-- Use svelte:element for dynamic HTML tags -->
<svelte:element this={as} class={sizeClass}>
    {title}
</svelte:element>
```

### DOM Event Handlers (CSP Safety)

For DOM events that can fire **before hydration** (`load`, `error`, `loadstart`, `canplay`, etc.), do not use declarative `onload={handler}` syntax on the element. Svelte 5 emits an inline capture stub — `onload="this.__e=event"` — in the SSR HTML to cache the event for post-hydration replay. That inline attribute is blocked by any CSP with a strict `script-src` directive (no `'unsafe-inline'`, no `'unsafe-hashes'`), which both fails the Lighthouse `errors-in-console` Best Practices audit and silently prevents the handler from running.

This is a two-headed failure: a visible Best Practices regression AND a latent functional bug where the handler never fires on fresh (non-cached) loads.

**Wrong:**

```svelte
<img bind:this={imgEl} onload={() => (loaded = true)} src="/hero.webp" />
```

**Right — programmatic listener in `$effect`:**

```svelte
<script lang="ts">
    let imgEl = $state<HTMLImageElement | null>(null);
    let loaded = $state(false);

    $effect(() => {
        const img = imgEl;
        if (!img) return;
        // Cached / pre-hydration: image already complete
        if (img.complete && img.naturalWidth > 0) {
            loaded = true;
            return;
        }
        // Post-hydration: attach listener programmatically
        const handler = () => { loaded = true; };
        img.addEventListener('load', handler, { once: true });
        return () => img.removeEventListener('load', handler);
    });
</script>

<img bind:this={imgEl} src="/hero.webp" class:is-loaded={loaded} />
```

The `const img = imgEl` capture gives the cleanup closure a stable reference (since `imgEl` is `$state` and can change). The `complete` check handles cached/pre-hydration loads where the event has already fired. The `addEventListener` path handles post-hydration loads without emitting any inline attribute to SSR HTML.

**This does not apply to delegated events** (`onclick`, `oninput`, `onchange`, `onkeydown`, etc.). Svelte attaches those at the document level and they never emit inline capture stubs — declarative syntax is fine for user-interaction events because they can't fire before hydration anyway.

---

## Svelte 5 Runes

### `$state` - Reactive local state

```typescript
let menuOpen: boolean = $state(false);
let screenSize: number = $state(320);
let searchQuery: string = $state("");
```

### `$derived` - Computed values

```typescript
let hasActiveFilter: boolean = $derived(selectedStatus !== 'all' || selectedCategory !== 'all');
let displayItems = $derived(items.filter(i => matchesFilters(i, selectedStatus, selectedCategory)));

// Derived with function body
let submitReady = $derived((): boolean => {
    return (!nameError() && !intentError() && hasProject);
});
```

### `$effect` - Side effects

```typescript
$effect(() => {
    if (connectionStatus.online && pendingRetry) {
        retryPendingOperation();
        pendingRetry = false;
    }
});
```

### `$effect` with cleanup

Return a cleanup function from `$effect` when the effect creates resources (intervals, listeners, subscriptions). Svelte runs the cleanup on re-run and component destroy — no `onMount` cleanup or shared mutable state needed.

**Gotcha:** With `noImplicitReturns` enabled, conditional cleanup needs an explicit return type annotation since not all code paths return a value:

```typescript
// Conditional cleanup — annotate the return type
$effect((): void | (() => void) => {
    if (shouldPoll) {
        const interval = setInterval(() => refresh(), 30_000);
        return () => clearInterval(interval);
    }
});

// Unconditional cleanup — no annotation needed
$effect(() => {
    const handler = () => update();
    window.addEventListener('resize', handler);
    return () => window.removeEventListener('resize', handler);
});
```

### Rune-based State Factory (`.svelte.ts` files)

```typescript
// FetchState.svelte.ts
export function createFetchState(): FetchState {
    let errorCode = $state<number | null>(null);
    let errorMessage = $state<string>('');
    let isLoading = $state<boolean>(false);
    let isSuccess = $state<boolean>(false);
    let isError = $derived((errorCode !== null) && (errorMessage !== ''));

    return {
        get errorCode() { return errorCode; },
        get errorMessage() { return errorMessage; },
        get isError() { return isError; },
        get isLoading() { return isLoading; },
        get isSuccess() { return isSuccess; },
        dismissError() { errorCode = null; errorMessage = ''; },
        newError(code: number, message: string) { /* ... */ },
        fetchSuccess() { /* ... */ },
        reset() { /* ... */ },
        startLoading() { /* ... */ }
    };
}
```

---

## TypeScript Conventions

### Strict Mode Enabled

```json
{
    "strict": true,
    "noImplicitAny": true,
    "strictNullChecks": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noImplicitReturns": true
}
```

### Union Types for Domain Constraints

```typescript
export type DepthLayer = 'base' | 'surface' | 'elevated';
export type HeadingLevel = 'h1' | 'h2' | 'h3' | 'h4' | 'h5' | 'h6';
export type HttpMethod = 'GET' | 'POST' | 'PUT' | 'DELETE' | 'PATCH';

// Domain enums (mirroring server)
export type EntityStatus = 'active' | 'paused' | 'closed' | 'archived';
export type EntityPrivacy = 'standard' | 'sensitive' | 'private';
```

### Rust-Style Result Types

```typescript
// ApiSuccess mirrors the server's response wrapper
export interface ApiSuccess<T> {
    code: number;
    message: string;
    data: T;
}

// ApiError for API failures
export class ApiError extends Error {
    constructor(public code: number, public message: string) {
        super(message);
        this.name = 'ApiError';
    }
    isUnauthorized() { return this.code === 401; }
    isForbidden()    { return this.code === 403; }
    isNotFound()     { return this.code === 404; }
    isRateLimited()  { return this.code === 429; }
}
```

### `satisfies` for Type-Safe Lookups

Components own their mappings inline. The same type resolves to different Tailwind in different component contexts:

```svelte
<!-- SectionWrapper.svelte — padding means section-level spacing -->
<script lang="ts">
    import type { Padding } from '$lib/types/ui';

    const paddingClasses = {
        none: '',
        sm:   'py-0 md:py-1 px-0 md:px-4',
        md:   'py-2 md:py-4 px-1 md:px-6',
        lg:   'py-4 md:py-8 px-2 md:px-8',
    } satisfies Record<Padding, string>;
</script>
```

```svelte
<!-- CardWrapper.svelte — padding means card-level spacing -->
<script lang="ts">
    import type { Padding } from '$lib/types/ui';

    const paddingClasses = {
        none: 'p-0',
        sm:   'p-0.5',
        md:   'p-1',
        lg:   'p-2',
    } satisfies Record<Padding, string>;
</script>
```

This pattern ensures exhaustiveness (add a new union member → every component's mapping gets a compile error) while allowing context-appropriate resolution.

---

## State Management

**Pattern: Local runes + factory functions. No global stores.**

- Component-local state via `$state` and `$derived`
- Reusable state logic via factory functions in `.svelte.ts` files
- Callback props for parent-child communication
- `setContext`/`getContext` for deeply nested shared state (auth status, FetchState)
- No Svelte 4 `writable`/`readable` stores

**ViewModel scope:** ViewModels mediate **client-side** data access — they own fetch/mutation logic and expose reactive state to views. SSR-only pages that receive data via `+page.server.ts` and mutate via form actions don't need ViewModels. Adding an empty ViewModel wrapper around server-provided data is scaffolding with no function.

---

## API Integration

**Principle: Views never call APIs directly. The ViewModel mediates all data access.**

The API layer is surface-specific — each surface defines its own transport. This style guide covers only the shared conventions.

### Two API Contexts (Web Surfaces)

SvelteKit web surfaces have two distinct API paths:

| Context | Where | Transport | Example |
|---------|-------|-----------|---------|
| Server-side | `+page.server.ts` / `+layout.server.ts` | SDK via `createClient()` with `locals.token` | Loading page data at request time |
| Client-side | ViewModels (`.svelte.ts`) | Typed API modules → `+server.ts` BFF endpoints | Interactive flows (booking wizard, live search) |

`+server.ts` endpoints are the BFF layer — they proxy to the backend SDK with proper auth. ViewModels call **typed API functions**, not `fetch()` directly. Co-locate API modules (e.g. `bookingApi.ts`) alongside their ViewModel; move to `lib/api/` when a second domain needs the same calls. Server loads call the SDK directly via `createClient()`.

SSR-only pages with form actions use neither — data arrives from `+page.server.ts`, mutations go through `<form action="?/cancel">`. No ViewModel needed.

### Tauri Surfaces

Tauri surfaces have one API context: client-side Tauri `invoke()` calls.
ViewModels call typed command wrappers (`lib/api/commands.ts`).
No server loads, no BFF endpoints. The surface skill defines the command layer.

### Typed Error Class

Every surface uses the same `ApiError` class for consistent error handling across the component tree:

```typescript
export class ApiError extends Error {
    constructor(public code: number, public message: string) {
        super(message);
        this.name = 'ApiError';
    }
    isUnauthorized() { return this.code === 401; }
    isForbidden()    { return this.code === 403; }
    isNotFound()     { return this.code === 404; }
    isRateLimited()  { return this.code === 429; }
}
```

### ViewModel Pattern

ViewModels (`.svelte.ts` files) own all client-side state and mutation logic. They expose reactive state to views and delegate transport to co-located typed API modules:

```typescript
// bookingApi.ts — typed transport (co-located with ViewModel)
import type { TimeSlot, CreateBookingBody } from '@uwz/sdk-ts';

export async function getAvailability(productId: number, date: string): Promise<TimeSlot[]> {
    const params = new URLSearchParams({ product_id: String(productId), date });
    const res = await fetch(`/book/availability?${params}`);
    if (!res.ok) {
        const body = await res.json().catch(() => null);
        throw new Error(body?.message ?? 'Failed to load availability.');
    }
    return res.json();
}

// bookingFlow.svelte.ts — ViewModel imports typed API functions
import { getAvailability } from './bookingApi';

export function createBookingFlow() {
    let slots = $state<TimeSlot[]>([]);
    let slotsError = $state('');

    async function fetchAvailability(productId: number, date: string) {
        try {
            slots = await getAvailability(productId, date);
        } catch (e) {
            slotsError = e instanceof Error ? e.message : 'Network error.';
        }
    }

    return {
        get slots() { return slots; },
        get slotsError() { return slotsError; },
        fetchAvailability,
    };
}
```

---

## Styling

### Stack: Tailwind CSS 4.0 + Scoped Styles + CSS Custom Properties

### Font System

Each surface defines its font families via CSS custom properties. The surface skill specifies the actual typefaces — the style guide enforces how they're used:
- Hierarchy through weight (400–700), size, and letter-spacing
- Font families resolved in `lib/components/` primitives, never in pages or `_components/`

#### Font File Location & Caching

Font files MUST live in `src/lib/fonts/` and be referenced with **relative paths** in `app.css`:

```css
@font-face {
    font-family: 'ExampleFont';
    src: url('./lib/fonts/ExampleFont.woff2') format('woff2'),
         url('./lib/fonts/ExampleFont.woff') format('woff');
    font-display: swap;
}
```

**Why:** `adapter-node`'s static file server (`sirv`) only sets `cache-control: public,max-age=31536000,immutable` on files under `/_app/immutable/`. Fonts in `static/` get no cache headers — browsers heuristically cache them for ~4 hours. Relative `url()` paths cause Vite to content-hash the files and place them in `_app/immutable/assets/`, where they receive the immutable header automatically.

**Rules:**
- Use relative paths (`./lib/fonts/`) in `@font-face`, never absolute (`/fonts/`). Absolute paths bypass Vite.
- Provide woff2 (primary) + woff (fallback). The CSS font stack provides system font fallback for the <1% of browsers that support neither.
- Preload the primary heading font (LCP-critical) from the root `+layout.svelte` using Vite's `?url` import — not from `app.html` (static template can't reference hashed filenames):

```svelte
<script lang="ts">
    import fontUrl from '$lib/fonts/HeadingFont.woff2?url';
</script>
<svelte:head>
    <link rel="preload" href={fontUrl} as="font" type="font/woff2" crossorigin="anonymous" />
</svelte:head>
```

- Do NOT put fonts in `static/fonts/` for the main site. That directory exists only for self-contained pages that run outside the adapter (e.g., maintenance pages served from `hooks.server.ts`).

### Color Variants

Components accept typed props (e.g., `ColorVariant`, `Padding`) and map them to Tailwind classes via inline `satisfies Record<>` lookups. The three-layer depth system (`base` → `surface` → `elevated`) creates visual hierarchy through background lightness.

Surfaces define `@theme` color tokens in their `app.css` (e.g., `--color-depth-base`, `--color-accent`). When a surface has tokens, component mappings must use the token utilities (`bg-depth-base`, `text-accent-fg`) instead of raw Tailwind palette classes (`bg-zinc-900`, `text-emerald-500`) for depth, brand, and accent colors. Glass effects, shadows, and other bespoke per-component values stay as raw Tailwind — these are intentional variation, not token candidates.

### `style?` Prop Escape Hatch

Shared primitives may accept an optional `style?: string` prop for one-off inline style overrides that don't warrant a new design token. This is an escape hatch, not a pattern — if the same override appears in multiple callsites, it should become a typed prop.

### Tailwind Containment

Tailwind class resolution is strictly layered:

| Layer | Tailwind allowed | Purpose |
|-------|-----------------|---------|
| `lib/components/` primitives | **Full** — design token resolution | Map typed props to Tailwind classes |
| `_components/` compositions | **Layout only** — grid, flex, gap | Arrange primitives, no design tokens |
| `+page.svelte` pages | **None** | Composition only, zero styling |

If a page needs styling, it's missing a component. Create the component in `_components/` (or `lib/components/` if shared).

---

## Navigation & Routing

### File-Based Routing (SvelteKit)

- `(auth)/` layout group for login (unauthenticated)
- Authenticated layout group (e.g. `(app)/`, `portal/`) for main application
- Layout handles nav via `$derived`
- Auth guard in the authenticated layout — bearer tokens and credentials must never reach client-side JavaScript. Implementation varies by surface (see surface skill files for specifics).

### Navigation Logic Separation

```
navLogic.ts    Pure functions (testable, no browser deps)
navState.ts    Browser-specific (uses SvelteKit goto())
```

### Keyboard Accessibility

```typescript
export function keyNav(relativeURL: string, e: KeyboardEvent) {
    if (e.key === ' ' || e.key === 'Enter') {
        if (e.key === ' ') e.preventDefault();
        goto(relativeURL);
    }
}
```

---

## Error Handling

- **API level**: `ApiError` class with status code type guards (see [API Integration](#api-integration))
- **Component level**: `FetchErrorDisplayBox` with dismiss button
- **Route level**: `+error.svelte` global error page
- **Auth level**: Auto-redirect to login on 401/session expiration
- **Offline level**: Connection status indicator when server is unreachable

---

## Testing

- **Framework**: Vitest 4 — single project, Svelte vite plugin handles rune compilation
- **Config**: `test.include` in `vite.config.ts` — no separate `vitest.config.ts` needed
- **Convention**: `*.test.ts` co-located with source files
- **Scope**: Layers 1-3 (utilities, SDK query construction, viewmodel error contracts). No component DOM testing yet.
- **API mocking**: `vi.mock('$lib/api/commands')` stubs Tauri `invoke()` wrappers. Surface-specific transport mocking lives in the surface skill.
- **Async viewmodels**: Use `flushPromises()` from `$lib/testUtils` to settle resolved promises before asserting state

---

## Strengths

> These are areas where the developer is strong. Claude should follow these patterns, not override them.

1. **Type system discipline** — Strict TS config, union types for domain constraints, `satisfies` for type-safe lookups. Never weaken type safety.

2. **Component structure** — Consistent script/markup/style ordering, inline Props interface, clean destructuring. Follow this layout.

3. **Logic separation** — Pure logic in `.logic.ts` / `.ts` files, browser code isolated. This enables testing and keeps components lean. Preserve this pattern.

4. **Typography system** — Fixed size scale with single font, hierarchy through weight.

5. **Theming via union types** — ColorVariant, Padding, Rounded, and domain status types mapped to Tailwind classes via component-owned `satisfies Record<>`. Extend, don't replace.

6. **Navigation architecture** — Clean split between pure logic and browser-specific code. Accessible keyboard handling. Maintain this standard.

7. **ViewModel factory pattern** — Rune-based state factories in `.svelte.ts` files. Views compose them, never own fetch logic directly.

8. **Context API for shared state** — Auth status, FetchState, and other cross-component state use `setContext`/`getContext` with runes. No prop drilling for shared state.

---

## Weaknesses

> These are areas where Claude should actively supplement, improve, or gently correct.

### Critical

1. **`children: any` instead of `Snippet`** — Always use `children?: Snippet` or `children?: Snippet<[param]>` for type safety.

2. **Legacy Svelte 4 stores** — Any `writable`/`readable`/`derived` from `svelte/store` should be migrated to `$state`/`$derived` runes in `.svelte.ts` files.

3. **Test coverage is partial** — Layers 1-3 (utilities, SDK, viewmodels) are covered. Layer 4 (component rendering) is deferred. Claude should write tests for new code and suggest tests for modified code.

### Important

4. **No error boundaries** — No component-level error catching. Suggest error boundaries for critical sections.

5. **No request cancellation** — API calls don't use cancellation. Add for navigation-sensitive contexts.

6. **No data caching or deduplication** — Every API call is independent. Consider a simple cache layer for repeated requests.

### Minor

7. **Three-layer depth consistency** — Ensure components use the correct depth layer (base/surface/elevated) for their z-position in the layout hierarchy. `surface-website` now has `@theme` tokens for this (`depth-base`, `depth-surface`, `depth-elevated`).

8. **No load functions** — Data fetching is entirely client-side in existing code. Surface skills define when to use SvelteKit load functions vs client-side fetching.
