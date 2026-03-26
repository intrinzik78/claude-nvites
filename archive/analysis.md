# Codebase Compliance Audit

**Date:** 2026-02-22
**Branch:** dev
**Documents audited:** Architecture.md, RUST_STYLE_GUIDE.md, SVELTE_STYLE_GUIDE.md, CLI_TOOL_DESIGN.md
**Additional references discovered:** UX.md, frontend-website skill, route-map.json

---

## Executive Summary

The backend is disciplined. The frontend is where the debt lives. This audit confirmed what was probably already felt: the server, SDKs, and CLIs — built on a year of deliberate personal engineering — are tightly aligned with their governing documents. The Svelte surfaces, where AI-assisted development has been running with less oversight, have drifted from the style guide in structural ways that need hands-on attention before they calcify.

### What we're sure about

- **Rust compliance is real, not an artifact.** The RUST_STYLE_GUIDE was extracted from existing code, so perfect compliance is expected — but it also means the patterns are genuinely internalized. Zero violations across 15 rules, verified in 20+ files per rule. The foundation holds.
- **SDK-only access is enforced everywhere.** No surface bypasses the SDK layer. This is the most important architectural principle and it's clean.
- **The Svelte type safety violations are concrete bugs.** 8 components use `children: any` instead of `Snippet`, and button components have `actionFn: any`. These are not architectural debates — they're type holes that the style guide explicitly flags as "Critical Weakness."
- **Architecture.md has one stale line.** sdk-ts is documented as "Planned — not yet implemented" but is fully implemented and in production use. This should be a one-line fix.
- **cli-user is dead weight.** Empty directory with only a `target/` folder, referenced in CLI_TOOL_DESIGN.md but absent from Architecture.md. Should be removed or documented.

### What needs investigation

- **Is the Svelte Style Guide aspirational or prescriptive?** It describes a mature component architecture (centralized design tokens in `types.ts`/`mappings.ts`, `satisfies Record<>` lookups, mandatory ViewModels, three-layer Tailwind containment, per-domain layouts) that has zero or near-zero adoption. If models read this guide and try to enforce it, they'll generate code that doesn't match the existing codebase. A decision is needed: bring the code up, or bring the guide down to where the code actually is.
- **The design token architecture is forking.** surface-website has 20+ individual type files in `lib/types/ui/`. The style guide wants a single `types.ts` + `mappings.ts` with `satisfies Record<>`. These are two different design systems heading in two different directions. The longer both coexist, the harder convergence gets. This needs a deliberate decision, not continued drift.
- **surface-command-center's component architecture is thin.** Zero `.svelte.ts` ViewModel files, no `lib/components/` directory structure, components calling the Tauri IPC layer directly. This may be acceptable for a small desktop app — or it may be setting a pattern that's hard to undo as the app grows. Needs a judgment call on how much structure this surface warrants at its current size.
- **Portal page styling violations — stubbed pages or real pattern?** Several portal pages (`bookings`, `orders`, `waivers`) have Tailwind directly in `+page.svelte`. If these are throwaway stubs that will be rewritten, the violations are cosmetic. If they're the foundation for real portal UI, the missing `_components/` and `+layout.svelte` files will compound.
- **Audit coverage limits.** The Rust audit sampled broadly (17+ handlers, 20+ mod files, all error enums) but did not read every file. High confidence, not absolute certainty. The real test of Rust compliance comes when unfamiliar areas get new code — the guide was extracted from existing patterns, so compliance with past work is expected.

---

## 1. Architecture.md — PASS with 2 doc-staleness issues

### Principles Honored

| Principle | Verdict | Evidence |
|-----------|---------|----------|
| **sdk-only-access** | **PASS** | All surfaces use SDKs exclusively. Zero reqwest/sqlx/mysql imports in any surface. surface-website goes browser → +server.ts → sdk-ts → API. surface-command-center goes Tauri IPC → sdk-rust → API. |
| **type-system-driven-design** | **PASS (Rust)** / **PARTIAL (TS)** | Rust side is exemplary. TypeScript has `any` leaks in 5+ components (see Svelte section). |
| **Build pipeline** | **PASS** | xtask build-all → schema-emitter → dist/openapi.json → server (include_str!) works as documented. |
| **Crate roles** | **PASS** | All 8 server sub-crates present. api-contracts has zero server deps (only serde, chrono, utoipa). |

### Documentation Drift

| Finding | Severity | Location |
|---------|----------|----------|
| **sdk-ts documented as "Planned — not yet implemented"** but is fully implemented (5 API modules, 11 files, in production use by surface-website) | Medium | `Architecture.md:22` |
| **cli-user exists in repo but not listed in Architecture.md** — empty scaffolding (only `target/` dir). CLI_TOOL_DESIGN.md references it as the pattern origin. | Low | `cli-user/` |
| **surface-member and cli-idropr** are empty `.gitkeep` placeholders | Info | Both listed in Architecture.md, just not built yet |

---

## 2. RUST_STYLE_GUIDE.md — EXCELLENT (99%)

The Rust codebase is the strongest area. Deep verification across handlers, models, enums, and error types confirmed near-total compliance.

### All Checked, All Pass

| Rule | Status | Verified In |
|------|--------|-------------|
| mod.rs gateway with selective re-exports | PASS | 20+ mod.rs files (api, types, traits, enums, workflow) |
| Naming conventions (files, structs, enums, functions, constants, traits) | PASS | Broad sampling across all crates |
| `type Result<T>` alias in every module | PASS | 20+ files verified |
| `#[derive(Debug, From)]` error enums | PASS | `server/api/src/enums/error.rs:15`, `server/database/src/enums/dberror.rs:4` |
| `#[repr(u8)]` for database enums | PASS | All lookup enums (BookingStatus, ResourceType, ShopStatus, UserStatus, etc.) |
| DatabaseHelper → transform pattern | PASS | `booking.rs:60-108`, `product.rs:45-82`, `resource.rs:74-84` — all private, all produce type-safe public structs |
| Zero-sized controller structs with `logic()` | PASS | 17+ handlers verified (BookingsPost, UsersPost, InstancesPost, SecretsPost, etc.) |
| Single table ownership (no raw SQL in handlers) | PASS | Zero `sqlx::query` calls in `server/api/src/api/` directory |
| Handler-level enum validation | PASS | All API boundaries convert i8 → enum before DB calls |
| Error surfacing via `to_api_error_message()` | PASS | 223+ verified calls; intentional catch-all for internal errors returns `None` → generic 500 |
| Hierarchical import grouping | PASS | std → external → internal → type alias |
| Private fields + public getters | PASS | AppState, Booking, Product all encapsulated |
| COALESCE in type methods (not handlers) | PASS | `booking.rs:284`, `resource.rs:152` — aggregate queries in type methods, not handlers |
| Glob imports only in `#[cfg(test)]` | PASS | All 20+ `use super::*` scoped to test modules |
| Rust 2024 edition + Resolver 3 | PASS | `api-contracts/Cargo.toml:4` edition = "2024", `server/Cargo.toml:13` resolver = "3" |

**Zero violations found in the Rust codebase.**

---

## 3. SVELTE_STYLE_GUIDE.md — SIGNIFICANT GAPS

This is where the most findings concentrate. The Svelte surfaces are functional but have structural divergence from the documented style guide.

### Critical (type safety violations)

| Finding | Files | Style Guide Reference |
|---------|-------|-----------------------|
| **`children: any` instead of `Snippet`** | `FrostedButton.svelte:6`, `FrostedLink.svelte:8`, `RetroButton.svelte:5`, `RetroLink.svelte:8`, `GlassCard.svelte:6`, `GlassTile.svelte:6`, `TextBox.svelte:4`, `SectionHeader.svelte:22` | Section 11.1 — explicitly called out as a "Critical Weakness" |
| **`actionFn: any` untyped callbacks** | `FrostedButton.svelte:9`, `RetroButton.svelte:7` (and link variants) | Section 11.1 / Props pattern requires typed callbacks |

### Structural (architecture pattern violations)

| Finding | Evidence | Style Guide Reference |
|---------|----------|-----------------------|
| **No centralized `types.ts` / `mappings.ts` in `lib/components/`** | Design tokens exist but are scattered across `lib/types/ui/` as individual files (AspectRatio.ts, GapSize.ts, Padding.ts, TextSize.ts, ColorVariant.ts, etc.). No single `mappings.ts` with `satisfies Record<>` lookups. | Section 1 — "ALL design token union types in types.ts, ALL mappings in mappings.ts" |
| **`satisfies Record<>` pattern not used anywhere** | Zero matches across surface-website | Section 3 — TypeScript Conventions, Styling |
| **+page.svelte files contain Tailwind classes** | `(public)/+page.svelte` has `flex flex-col items-center...`, `portal/bookings/+page.svelte` has extensive Tailwind | Section 4 — "Composition only, zero styling" |
| **Portal subdomains missing per-domain `+layout.svelte`** | `portal/bookings/`, `portal/orders/`, `portal/waivers/`, `portal/surveys/`, `portal/queue/`, `portal/profile/` — all inherit parent layout, none have their own | Section 1 — "Every domain gets its own +layout.svelte, even single-page domains" |
| **surface-command-center has zero `.svelte.ts` ViewModels** | No `.svelte.ts` files exist. Components call `commands.ts` (Tauri IPC) directly. | Section 5 — "Views never call APIs directly. The ViewModel mediates." |
| **`_components/` convention partially adopted** | Only `book/_components/` and `shop/_components/` exist. Portal domains lack them. | Section 1 — "_components/ convention" |
| **Client-side `fetch()` bypasses `lib/api/` layer** | `bookingFlow.svelte.ts:56,116` calls raw `fetch()` to +server.ts routes instead of using the API layer | Section 5 — API layer should mediate all access |

### Passing

| Rule | Status |
|------|--------|
| No Svelte 4 stores (`writable`/`readable`/`derived`) | PASS — zero imports from `svelte/store` |
| Strict TypeScript configuration | PASS — both surfaces have all strict flags |
| Inline Props interface (not exported) | PASS |
| `$props()` rune for destructuring | PASS |
| navLogic.ts / navState.ts separation | PASS — correctly implemented and documented |
| Callback props (not custom events) | PASS |

---

## 4. CLI_TOOL_DESIGN.md — PASS (1 minor)

Both active CLIs (cli-api-testing, cli-tako) follow the MVC pattern correctly.

| Rule | cli-api-testing | cli-tako |
|------|----------------|----------|
| MVC architecture (SDK model, View struct, Controller) | PASS | PASS |
| Module layout (enums/, types/, args/, commands/) | PASS | PASS |
| `type Result<T>` in every module | PASS | PASS |
| Zero-sized command structs with `async fn run()` | PASS | PASS |
| `derive_more::From` error enum | PASS | PASS |
| Display prefixes ([sdk], [io], [view], [cli]) | PASS | PASS |
| SDK-only (no direct HTTP) | PASS | PASS |
| View fluent chaining | PASS | PASS |
| **Builder pattern** (`Controller::build().with_model().with_view().finish()`) | **PASS** | **MINOR** — uses `Controller::new()` directly |

---

## Red Team: What Might We Be Missing?

1. **Is the command-center ViewModel gap real?** The Svelte Style Guide says "Views never call APIs directly. The ViewModel mediates." But command-center is a Tauri desktop app. The style guide itself says "The API layer is surface-specific." However, the ViewModel pattern is listed as a *shared convention*, not surface-specific. **Verdict: The gap is real but arguably lower priority for a desktop app with simpler data flows.**

2. **Are the bookingFlow.svelte.ts fetch() calls a real violation?** They call +server.ts endpoints (which use the SDK), not the raw API. The client never touches a bearer token. **Verdict: The calls are SDK-compliant at the architecture level, but violate the Svelte convention of API calls going through `lib/api/`.** The existing `lib/api/index.ts` only wraps `createClient()` — it doesn't expose booking functions, so the ViewModel had nowhere to delegate to.

3. **Is the per-domain +layout.svelte finding overly strict?** The style guide is explicit: "every domain gets its own, even single-page domains." The portal subdomains are clearly separate domains (each with their own route directory). **Verdict: Legitimate gap — these will need layouts when domains grow.**

4. **Is the missing `satisfies Record<>` pattern a real problem?** The style guide documents it as the canonical approach for type-safe lookups. The website uses individual type files in `lib/types/ui/` instead. **Verdict: Structural divergence. The individual files may work, but they're not what the guide prescribes.**

---

## Priority Summary

| Tier | Area | Count |
|------|------|-------|
| **High** | Svelte type safety (`children: any`, `actionFn: any`) | 8+ files |
| **High** | Svelte structural patterns (no ViewModels in command-center, missing centralized tokens) | 3 gaps |
| **Medium** | Svelte page styling (+page.svelte with Tailwind, missing domain layouts) | 8+ pages |
| **Medium** | Architecture.md staleness (sdk-ts status, cli-user undocumented) | 2 items |
| **Low** | CLI builder pattern inconsistency (cli-tako) | 1 item |
| **None** | Rust codebase | 0 violations |

---

## 5. UX.md + frontend-website Skill — The Docs Were Right, the Code Didn't Listen

Post-audit analysis of the `/frontend-website` skill and its referenced `UX.md` revealed that the governing documents for surface development are well-written, mutually reinforcing, and describe exactly the architecture the surfaces are failing to follow. The surfaces drifted not because the docs are wrong, but because they weren't in the loop when the code was written.

### UX.md — the most specific frontend architecture doc in the project

`UX.md` was not in the original audit scope but is referenced by the `/frontend-website` skill. It is the most detailed specification of the component architecture, more concrete than the Svelte Style Guide in several areas:

| What UX.md prescribes | Current state | Alignment |
|------------------------|---------------|-----------|
| `lib/components/types.ts` — all design token union types (`Spacing`, `DepthLayer`, `Intent`, etc.) | Tokens scattered across 20+ individual files in `lib/types/ui/` | DIVERGED |
| `lib/components/mappings.ts` — `Record<Spacing, string>` resolution maps | Does not exist. `satisfies Record<>` pattern has zero adoption. | MISSING |
| Tailwind lives in `lib/components/` and ONLY there | Tailwind in `+page.svelte` files and `_components/` | VIOLATED |
| Per-domain `+layout.svelte` for every domain | Portal subdomains inherit parent layout, none have their own | MISSING |
| `.svelte.ts` ViewModels own all SDK calls, views never touch SDK | surface-command-center has zero ViewModels; website's bookingFlow uses raw `fetch()` | VIOLATED |
| 8-stage build workflow: route map → intent → visual design → decomposition → tokens → primitives → screens → review | Evidence suggests stages 6-7 were executed without stages 4-5 | SKIPPED |

**Key insight:** UX.md's 8-stage workflow is designed to produce compliant code by construction. If you follow it in order — define tokens as types (stage 5), build primitives (stage 6), then compose screens (stage 7) — you can't end up with Tailwind in pages or untyped props. The surfaces appear to have jumped to stages 6-7 without the foundation of stages 4-5.

### frontend-website skill — correctly aligned, underutilized

The skill itself is not the source of drift. It:

- Explicitly references SVELTE_STYLE_GUIDE.md and UX.md and tells the agent to read them first
- Correctly prescribes SSR-only data loading, ViewModel-mediated API access, no universal loads, no client-side token exposure
- Provides strong creative direction (cinematic, cinematic, cinematic) that correctly defers to the style guide for structural patterns

**Three concerns for future use:**

1. **UX.md was written for Tauri surfaces.** Opening line: "Human-in-the-loop workflow for building Tauri + SvelteKit surfaces." The example route structure (dashboard, POS, settings) is staff-facing command-center, not customer-facing website. The component architecture principles transfer, but the route examples don't. An agent could get confused about which patterns apply to which surface.
2. **Creative energy could overwhelm structural discipline.** The skill spends 60 lines on cinematic vision and 6 lines pointing to the style guide. An agent running hot on "make it cinematic" might skip UX.md's 8-stage workflow and jump straight to writing Tailwind in pages. The stages exist to prevent exactly the drift this audit found.
3. **Worktree path reference.** The skill points to `../worktrees/surface-website/surface-website/src/` (line 22), not the monorepo path. Minor, but could confuse an agent working from dev.

### Recommendation

The cleanup workflow (below) should treat UX.md's 8-stage process as the canonical build order. Specifically, the design token decision (NEXT.md item 7) maps to UX.md stage 5. Get the types and mappings right first — everything downstream composes from them.

---

## Cleanup Workflow

Surface-by-surface compliance, using `/next` to drive each item through plan → red-team → implement → verify. Website first (it's the real work), command-center second (follows the pattern).

### surface-website — ordered by dependency

| Step | Item | Why this order |
|------|------|----------------|
| 1 | **Resolve design token architecture** — decide: consolidate `lib/types/ui/*.ts` into `lib/components/types.ts` + `lib/components/mappings.ts` with `satisfies Record<>`, or formalize the individual-file pattern and update the style guide. | Load-bearing decision. Steps 2–4 depend on where tokens live. |
| 2 | **Fix type safety violations** — `children: Snippet` in 8 components, `actionFn` typing in button components. | Surgical fixes, no structural dependencies. Highest type-safety payoff for smallest blast radius. |
| 3 | **Page compliance + domain structure** — extract Tailwind from `+page.svelte` into `_components/`, add per-domain `+layout.svelte` for portal subdomains (bookings, orders, waivers, surveys, queue, profile). | Bulk of the work. Touches route structure and component organization. |
| 4 | **ViewModel + API layer** — wire `bookingFlow.svelte.ts` through `lib/api/` properly, ensure all client-side data access goes through ViewModels. | Touches data flow. Do after component structure is stable. |

### surface-command-center — after website is clean

| Step | Item |
|------|------|
| 1 | **Establish `lib/components/` directory structure** — move components out of flat `lib/`, organize per style guide. |
| 2 | **Extract ViewModels** — create `.svelte.ts` files for BookingList and CheckInFlow, move API calls out of components. |
| 3 | **Organize API layer** — `commands.ts` into `lib/api/` with proper structure. |

### Housekeeping (either surface session)

- Update `Architecture.md:22` — sdk-ts status from "Planned" to "Implemented"
- Remove or document `cli-user/`

---

## Bottom Line

The Rust side is rock-solid. The server, api-contracts, SDKs, and CLIs are all tightly aligned with their governing documents.

The Svelte surfaces are where the gap lives, and it's structural rather than broken: the style guide describes a mature component architecture that the frontend hasn't grown into yet. The decision has been made to bring the code into compliance with the guide, surface by surface, using the `/next` skill to drive each item through the plan-red team-implement loop.
