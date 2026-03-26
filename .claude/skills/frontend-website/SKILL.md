---
name: frontend-website
description: Build customer-facing UWZ website pages with cinematic design quality. Enforces aesthetic direction, SSR/CSR strategy, and design system for surface-website.
---

# Frontend Website

Every page is a **scene**. Grand, epic, stunning, cinematic. This is a paintball entertainment center — physical, loud, high-stakes, unforgettable. The site should hit the same way.

Think movie trailer, not brochure. Think arena entrance, not waiting room.

## References

Read these before building. They cover code conventions, component workflow, and route structure — this skill won't repeat them.

- `docs/SVELTE_STYLE_GUIDE.md` — Svelte code conventions, component patterns, TypeScript, Tailwind containment, component-owned design token mappings
- `docs/WEB_UX.md` — 8-stage build process, component layering philosophy, MVVM architecture
- `route-map.json` (monorepo root) — authoritative route tree, data requirements, role permissions, state machines

**Stack:** SvelteKit + Svelte 5 + Tailwind 4 + TypeScript strict + `sdk-ts` (generated from OpenAPI). NO Tauri.
**Surface:** Customer-facing — public marketing + customer portal. Staff tools are surface-command-center.
**Scaffold:** `../worktrees/surface-website/surface-website/src/`

## Creative Direction

Before writing any code, stop. Commit to a vision:

- What is the **one moment** someone will remember from this page?
- What emotion should hit in the first second — adrenaline, anticipation, confidence, excitement?
- Where is the cinematic beat — the hero reveal, the scroll surprise, the hover that rewards curiosity?

Build toward that moment. Everything else serves it.

### The Identity — Locked

These define the brand. They are not suggestions:
- **BlackOpsOne** headings — military/tactical, commanding, unapologetic
- **SpaceGrotesk** body — geometric, technical, clean
- **Dark depth system** — base (deep shadow) → surface (catches light) → elevated (glows). The darkness is the brand.
- **Color tokens** defined in `surface-website/src/app.css` via `@theme`. Use token utilities (`bg-depth-*`, `bg-brand-*`, `text-brand-*`) instead of raw Tailwind palette classes for depth and brand colors. Glass effects and per-component shadows stay as intentional bespoke values.
- **Existing components** (RetroButton, FrostedButton, GlassCard) are the visual vocabulary. New components match their energy — frosted glass, glow effects, tactile depth.

### The Canvas — Everything Else

Within the locked identity, push hard. Make bold choices. Surprise yourself.

**Motion choreography.** One orchestrated sequence per view beats scattered micro-interactions:
- Staggered page reveals that *build* the scene — elements entering with deliberate timing, not all at once
- Scroll-triggered entrances — content materializing as the user moves through the story
- Hover states that reward curiosity — scale shifts, glow pulses, shadow deepening, subtle parallax
- Page transitions that feel like scene cuts, not browser navigation

**Spatial composition.** Break the grid when it serves the moment:
- Marketing heroes: asymmetric, generous, bold type at scale. Negative space is dramatic, not empty.
- Portal pages: controlled density, information-forward. Cinematic doesn't mean sparse — it means *intentional*.
- Overlap. Diagonal flow. Elements that bleed past their containers. Tension in the layout.

**Visual depth and atmosphere.** The site should feel like it has physical weight:
- Grain overlays, layered transparencies, dramatic shadows
- Gradient meshes behind hero sections. Frosted glass panels floating over textured backgrounds.
- Glows, rim lighting on cards, subtle radial gradients suggesting spotlights
- The depth system isn't decoration — it's **lighting design**. Base is shadow. Surface catches light. Elevated burns.

**Color intensity.** The dark palette is the foundation. Accents should *hit*:
- Sharp, confident accent colors — not timid pastels, not muted, not safe
- Color signals energy and action. Safety vest orange. Tactical green. Electric blue.
- One accent per section, maximum impact. Sparingly but boldly.

### What Kills the Vibe

- Generic template layouts — the fastest way to be forgotten
- Timid color — desaturated, playing it safe, hedge-everything palettes
- Zero motion — static pages feel dead for an action brand
- Cookie-cutter card grids — no rhythm, no surprise, no tension
- Flat design with no depth — the three-layer system exists for a reason
- Treating the portal like a boring admin panel — it's still the brand
- Stock photo heroes — if no real imagery, use atmosphere: gradients, particles, grain, light

## Website-Specific Rules

These are the few rules unique to this surface. Everything else comes from the style guide and `docs/WEB_UX.md`.

**Data loading:**
- All pages use `+page.server.ts` (SSR). Public pages for SEO; portal pages for token security (HTTP-only cookie stays server-side via `locals.token`, never serialized to client).
- Server loads call the SDK via `createClient()` with `locals.token`. Client-side interactive flows (booking wizard, live search) use ViewModels that call `+server.ts` BFF endpoints via `fetch()`.
- SSR-only portal pages that receive data from `+page.server.ts` and mutate via form actions do NOT need ViewModels — adding an empty wrapper around server-provided data is scaffolding with no function.
- Auth guard lives in `portal/+layout.server.ts` — redirects to `/login` if no session cookie.
- Client-side reactivity (`$state`, `$derived`, WebSockets, `+server.ts` endpoints) is unaffected — "SSR-everywhere" applies to SvelteKit load functions only.

**Responsive:**
- Mobile-first. Base styles = mobile, `md:` and `lg:` for larger screens.
- **320×640 is the design floor.** Most users are mobile.
- Below 640px, glass containers strip to transparent — the brand lives in the atmospheric layers, not the containers.
- Touch targets: 44px minimum.
- WCAG AA contrast. Visible focus rings. Semantic HTML. Skip links on public pages.

Cinematic doesn't excuse inaccessible. Grand visuals with keyboard navigation and screen reader support — both, always.

**Hard boundaries:**
- No Tauri imports or invoke patterns — this is a web surface
- No `+page.ts` or `+layout.ts` (universal loads) — all data loads are server-only. SDK uses global `fetch` (not SvelteKit's), and `API_BASE_URL` is `$env/static/private` (unavailable in browser).
- No client-side token exposure — bearer token lives in HTTP-only cookie, read via `locals.token` in server loads, never serialized to the client. Session metadata (username, role, expiry) returned from server loads is fine.

---

This site is the first thing a customer sees. Before the paintballs fly, before the adrenaline hits, there's this screen. Don't play it safe. Don't default to what's familiar. Make it worthy of what comes next.

$ARGUMENTS
