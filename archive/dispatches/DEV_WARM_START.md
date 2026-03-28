# Dispatch: Warm start — nvites.me foundation session 2

**Date:** 2026-03-26
**Workstream:** dev

## What nvites.me is

QR code marketing analytics gateway. Clients create campaigns with hyper-short URLs that forward users to a destination. As users pass through the gateway, the system captures device, location, and timing data. Analytics delivered as daily/weekly email digests. Target: small businesses tracking physical/digital marketing campaigns. Solo dev project, market fit unvalidated.

## What was done (this session)

1. Defined project vision — Architecture.md Intent section filled
2. Surgery slices 4-9 complete — codebase compiles, `cargo xtask build-all` passes (Rust pipeline green)
3. Removed ~40,000 lines across ~300 files: bookings, albums, waivers, queues, extractions, scans, share codes, doc-extractor
4. Filled all 8 TODO-stubbed docs (DEPLOYMENT, COLD_START, EMAIL_DESIGN, WEB_UX, APP_UX, STARTUP_GATES, PRE_LAUNCH, ARCHITECTURE-DIAGRAM)
5. Pruned handoffs (336 → 273) and archive dispatches (57 → 25) — deleted-domain files only
6. Stripped website to foundation: home, auth, shop, portal/profile, contact, about. Rebranded nav/footer to nvites.me
7. Severed payment → booking contract coupling (removed `booking_id` from `PaymentTransactionDto`)
8. Fixed sdk-rust lib name (uwz_rust_sdk → nvites_rust_sdk), all tests pass
9. Command center gutted to placeholder panels, Tauri Rust compiles clean

## What was NOT done

- **`@nvites` npm scope**: not registered on npmjs.com. Blocks svelte-check and any TS dev. See `DEV_NPM_SCOPE_REGISTRATION.md`.
- **DB migration**: `payment_transaction.booking_id` FK still exists in DB. ~40 orphaned tables in `TABLES_TO_REMOVE.md`. Docker MySQL is stopped, `nvites` schema doesn't exist yet.
- **Docs commit**: 8 updated files + archive deletions in `docs/` and `archive/` are symlinked from `../claude/` — need separate commit there.
- **UWZ branding residue**: some lib components (ParticleField, steps, timers) and about/contact pages may still have UWZ copy. Generic CSS design tokens still reference paintball theming.
- **No remote repos**: neither monorepo nor claude repo has a remote.
- **Core product doesn't exist yet**: no QR redirect endpoint, no campaign data model, no analytics capture, no digest emails.

## Things to know

- **Two repos**: monorepo at `nvites-me/monorepo/`, claude config at `nvites-me/claude/`. Docs/skills are symlinked.
- **Docker MySQL is stopped**: `nvites` schema doesn't exist yet. `CREATE DATABASE nvites;` needed.
- **Rust pipeline is green**: `cd server && cargo xtask build-all` passes (build + clippy). svelte-check fails on `@nvites/sdk-ts` resolution.
- **Website routes**: `/` (placeholder), `/shop`, `/about`, `/contact`, `/login`, `/register`, `/portal/me`, `/portal/orders`, `/portal/logout`.
- **Server endpoints**: sessions, secrets, verifications, users, shop products, portal/me, payments (held/approve/decline), webhooks, workflows, workflow instances, epochs, health.
- **Open dispatches**: `DEV_NPM_SCOPE_REGISTRATION.md`, `DEV_HANDOFFS_CLEANUP.md` (partially done — 273 remain), `SERVER_PAYMENT_BOOKING_FK.md` (contract done, DB FK remains).

## Things to avoid

- Don't `cargo build` from outside `server/` — the workspace is scoped there
- Don't guess what nvites.me features should look like — the user will define this
- Don't touch the UWZ project at `/home/zik/programming/uwz/`
- Don't read .env files (they're outside the monorepo)
- Don't commit docs/ or archive/ from the monorepo (they're symlinks)

## Recommended next session flow

1. `/orient` — picks up all dispatches
2. Ask: "Ready to build the core product, or more cleanup?"
3. If build: start with campaign + short URL data model in api-contracts (new domain, new tables, new endpoints)
4. If cleanup: npm scope registration, DB migration for orphaned tables, remaining UWZ branding pass

## Confidence

**High** — the foundation is solid, pipeline is green, every commit is a rollback point
