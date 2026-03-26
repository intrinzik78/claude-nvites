# NEXT.md

## server
- ~~Rate limiter bucket_capacity stuck at default 50: `build_rate_limiter` calls `.with_tokens_per_bucket()` which sets `initial_tokens_per_bucket` but never `.with_bucket_capacity()` — capacity stays at builder default (50). `LIMITER_INITIAL_TOKENS_PER_BUCKET` env var is loaded but never wired to the builder. Fix: add `.with_bucket_capacity(env.limiter_tokens_per_bucket)` and `.with_initial_tokens(env.limiter_initial_tokens_per_bucket)` to the builder chain.~~
- ~~Add `guarded` catch_unwind to queue entry and booking integration tests — these create records visible on the command center and in reporting. Mechanical, pattern established in workflow/waiver tests.~~
- ~~Fix `generate_slots()` in `availability_get.rs` — step by 30 min (not `duration_minutes`), last slot at `close_time - 2hr`. Duration only used for capacity overlap window. Currently produces 2 slots/day for 180-min products instead of ~13. Tests need rewrite to match.~~
- Rename local dev database from `uwz` to `uwz_dev` — defense in depth for test DB target sentinel. Cross-cutting: `.env`, CI workflow, xtask `DEFAULT_DATABASE_URL`, docs.
- [stretch] Upgrade Rust toolchain from 1.92 to 1.94 — own PR, run full test suite, update `rust-toolchain.toml` + `ci.yml`, `cargo fmt`. Watch for 1.94 closure capture semantics change.

## surface-command-center
- ~~Check-in group entity / split mechanics — deferred from migration plan~~
- ~~Design spec for check-in group entity / split UX — prerequisite for above~~
- ~~Known issues~~ (all resolved)

## surface-website

### Build
- `/prices` Phase 3: non-tier sub-pages (`/prices/food`, `/prices/gear`, `/prices/membership`) — redirects temporarily point to `/prices` parent. Each sub-page must ship with its redirect update (RT-9).
- "Plan Your Visit" guided micro-app — step-through planning flow, top conversion funnel + SEO landing page. Design in a dedicated session.
- Begin content creation

### Polish / cleanup
- `/book` + `/prices` copy polish — package feature descriptions need owner verification (`tiers.ts` TODO). See `docs/DISPATCH_WEBSITE_PAYMENTS.md`.
- Mobile menu `nextMobileDelay()` cleanup — move counter reset from template side effect into the `$effect` that fires when `mobileMenuOpen` changes. Cosmetic only.

### Owner decisions
- Home page "See Prices" link — add body link alongside "Book Now"? SEO weight vs CTA dilution.
- `/hours` label — "Hours & Pricing" vs "Hours" now that `/prices` is its own section.

### Deferred (post-deploy verification)
- [deferred] Verify PostHog + SvelteKit client-side navigation (RT-1)
- [deferred] Verify OG image URL reachability for pictures deep-links

### Heads-up
- FAQ redirect overrides are fragile — when Slice 6 updates /faq targets, the carve-outs from /blog/party/ → /birthday won't be obvious.
- Tailwind-in-page is universal — style guide's "zero styling in pages" rule is aspirational. Acknowledge or accept.

## crosscutting
- Expand CI clippy coverage to `sdk-rust`, `cli-idropr`, `cli-tako`, `cli-api-testing` — fmt is covered (shipped 2026-03-24) but clippy is not. Will increase CI time; consider whether to gate on warnings or just report.
- Add `cargo xtask install-hooks` — move pre-commit hook source to `scripts/pre-commit` (version-controlled), xtask command installs into `.git/hooks/`. Current hook lives only in `.git/hooks/` and won't survive a fresh clone.
- [deferred] Verify PUBLIC_MODE + PUBLIC_POSTHOG_ANALYTICS in CI/deploy configs
- [deferred] Expose TIMEZONE_LABEL env var to surfaces — hardcoded "Central Time" in CallAheadForm.svelte and any future time displays should reference a single config source (Phase 5 of queue expected_at, RT-7)
- CallAhead SDK gap: `CallAheadBody`/`CallAheadResponse` types are exported but no `makeCallAheadApi` wrapper exists in `sdk-ts/src/api/`. Same pattern as waiver SDK gap — mechanical fix when needed.
---

## Suggestions

<!-- Appended by /orchestrate. Everything above the --- is human-owned. -->