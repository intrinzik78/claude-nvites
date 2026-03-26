# Docs Audit — 2026-03-14

Cross-referencing Architecture.md, APP_UX.md, WEB_UX.md, CLI_TOOL_DESIGN.md, DECISIONS.md, ESIGN_GUIDE.md, MYSQL_PLAYBOOK.md, PRE_LAUNCH.md, RUST_STYLE_GUIDE.md, and SVELTE_STYLE_GUIDE.md for discrepancies, intent drift, and reference drift.

---

## HIGH — Intent Drift / Contradictions

### 1. WEB_UX.md identity crisis

Architecture.md (line 52) labels WEB_UX.md as "Web surface architecture, MVVM, 8-stage build workflow." But WEB_UX.md line 3 describes itself as covering **"Tauri + SvelteKit surfaces"** — all surfaces, not web-only. Its route structure example (bookings, customers, waivers, POS, settings at lines 73-115) describes **staff-facing command-center routes**, not public website routes. The doc was likely written when command-center was still planned as a web app, and the identity was never reconciled when APP_UX.md was created for desktop.

Architecture.md and WEB_UX.md disagree on what WEB_UX.md IS.

### 2. Two different "8-stage workflows" with no acknowledgment

Both WEB_UX.md and APP_UX.md define 8-stage build workflows. They diverge at **Stage 5**:

| Stage | WEB_UX.md | APP_UX.md |
|-------|-----------|-----------|
| 5 | Design Tokens as Types (Co-Authored) | Command Layer (Co-Authored) |

APP_UX.md (line 252) says "Adapted from the 8-stage web workflow for desktop constraints" — but the stages are actually different, not adapted. Architecture.md references "8-stage build workflow" as if there's one canonical version. A builder following "the 8-stage workflow" gets different instructions depending on which doc they open.

### 3. WEB_UX.md and SVELTE_STYLE_GUIDE.md: heavy duplication, no cross-reference

Both docs substantially cover the same ground with no acknowledgment of each other:
- Component layering (3-tier Tailwind containment)
- MVVM + ViewModel pattern (`.svelte.ts` files)
- `_components/` convention (same rules verbatim)
- Per-domain `+layout.svelte` rule
- Route structure with `(auth)/` and `(app)/` groups

APP_UX.md correctly says "For Svelte code conventions, see `docs/SVELTE_STYLE_GUIDE.md`." WEB_UX.md makes no such division — it owns code conventions AND architecture in the same doc. This means:
- Updates to component layering rules must be made in **two** places
- The web-surface-specific architecture that DEC-050 mandates (SSR-only loads, BFF endpoints) lives in **SVELTE_STYLE_GUIDE.md** (lines 375-383) rather than WEB_UX.md, which is backwards

### 4. SVELTE_STYLE_GUIDE responsive breakpoint examples contradict APP_UX.md

SVELTE_STYLE_GUIDE.md lines 328-329 (SectionWrapper example):
```
sm: 'py-0 md:py-1 px-0 md:px-4',
```

APP_UX.md lines 219-221:
> "No Responsive Breakpoints — Desktop window, 1024x768 minimum. `sm:` and `md:` breakpoints are wrong — they imply a mobile-up strategy that doesn't apply."

SVELTE_STYLE_GUIDE calls itself "Shared code conventions for Svelte surfaces." An example that's correct for web is an explicit anti-pattern for desktop. No caveat.

### 5. DISPATCH child waiver instruction is about to become actively harmful

Three docs say child waivers don't exist:
- archive/dispatches/DISPATCH_ESIGN_WAIVER_DISCRETE.md line 142: **"Do not implement the child waiver flow."**
- ESIGN_GUIDE.md line 225: "The child waiver endpoint was removed."
- DISPATCH line 11: "old `POST /v1/portal/waivers/child` is also removed"

Git status shows `portal_waivers_begin_child_post.rs` being actively created in the current dev session. Once the child endpoint ships, the dispatch **tells surface developers to NOT implement something that exists.** The ESIGN_GUIDE lists it as a "known limitation" that's about to be resolved. These docs will need updating when the child flow lands.

---

## MEDIUM — Reference Drift / Stale Data

### 6. Architecture.md Reference Docs table is incomplete

The table lists 6 docs: RUST_STYLE_GUIDE, SVELTE_STYLE_GUIDE, WEB_UX, APP_UX, STARTUP_GATES, DECISIONS.

Missing from the table:
- **ESIGN_GUIDE.md** — the waiver system is now a major architectural surface with its own compliance framework, hash schemes, and cross-cutting contracts
- **CLI_TOOL_DESIGN.md** — the canonical CLI architecture doc
- **MYSQL_PLAYBOOK.md** — database operations playbook
- **PRE_LAUNCH.md** — launch readiness tracker

### 7. PRE_LAUNCH.md stale migration count

Line 61: "29 migrations against Cloud SQL." Actual count: **39 migration files**. Off by 10 — the ESIGN waiver work alone added 4+ migrations. Misleading for deployment planning.

### 8. Architecture.md Open Questions: first question is answered

Line 74: "Customer waivers: submission flow through website, member portal, or dedicated surface?"

This is definitively answered. ESIGN_GUIDE.md documents the complete flow through portal auth on the website (`/v1/portal/waivers/*`). archive/dispatches/DISPATCH_ESIGN_WAIVER_DISCRETE.md is addressed to `surface-website`. Multiple DECs (DEC-085, DEC-128, DEC-133) encode waiver decisions. This is no longer an open question — it's a shipped system.

### 9. MYSQL_PLAYBOOK.md generic/specific identity conflict

Line 3: "Generic setup for Rust + MySQL + Google Cloud SQL projects." Examples use `myapp` as the database name. But line 109: "This project does not currently use offline mode" — project-specific editorial. Line 224: "this project seeds via migrations" — same. It's neither a reusable template nor a UWZ-specific playbook. Someone reading it for UWZ hits `myapp`; someone templating it hits UWZ opinions.

### 10. WEB_UX.md missing the web-specific architecture DEC-050 mandates

DEC-050 established critical web-surface architecture: SSR-only load functions, no universal loads, `+server.ts` BFF endpoints for client-side interactivity, `$env/static/private` for API_BASE_URL. This architecture is documented in **SVELTE_STYLE_GUIDE.md** (lines 375-383, "Two API Contexts") — not in WEB_UX.md, which Architecture.md labels as the "Web surface architecture" doc. The doc that should own this content doesn't have it. The doc that shouldn't need it does.

---

## LOW — Minor Inconsistencies

### 11. Model terminology mismatch

WEB_UX.md line 45: Model = "SDK types, shared across surfaces."
APP_UX.md line 129: Model = "api-contracts types (shared DTOs)."

Same thing semantically (SDK types originate in api-contracts), but inconsistent terminology between two docs that describe the same pattern.

### 12. PRE_LAUNCH.md / STARTUP_GATES.md scope overlap unclear

Architecture.md lists STARTUP_GATES.md in its reference table. PRE_LAUNCH.md line 4 says "See also: STARTUP_GATES.md for runtime configuration requirements." Both are about launch readiness. Their scopes: STARTUP_GATES covers runtime config that's **silently broken if wrong**; PRE_LAUNCH is a broader **checklist tracker** with open/resolved items. The relationship works but isn't stated in Architecture.md — it lists STARTUP_GATES but not PRE_LAUNCH, making PRE_LAUNCH a doc with no entry point from the index.

### 13. SVELTE_STYLE_GUIDE weakness #8 ambiguous surface scope

Line 580: "No load functions — Data fetching is entirely client-side in existing code."

Accurate for desktop surfaces (client-side by design). But DEC-050 mandates SSR-only loads for web. The weakness doesn't specify which surface. Since the guide is shared across all surfaces, this reads as "no surface uses SSR loads" — which contradicts DEC-050's intent (and the API Integration section in the same document).

---

## Structural Pattern

The most concerning pattern is **#1/#2/#3 taken together**: WEB_UX.md, APP_UX.md, and SVELTE_STYLE_GUIDE.md have overlapping ownership with no clear division. WEB_UX.md doesn't know if it's web-specific or general. APP_UX.md correctly carved out desktop, but WEB_UX.md was never narrowed to match. The web-specific architecture (DEC-050) landed in SVELTE_STYLE_GUIDE instead of WEB_UX.md. Content that should exist in one place exists in two.

The child waiver issue (#5) is time-sensitive — it becomes actively harmful once the other session ships.
