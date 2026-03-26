# Dispatch: Warm start — nvites foundation session continuation

**Date:** 2026-03-26
**Workstream:** dev

## Problem

This is a new project forked from an existing codebase (UWZ). A stripping session removed business domains (bookings, waivers, queues, albums, scans) and renamed the project from `uwz` to `nvites`. The codebase does not compile — downstream crates still reference deleted api-contracts types. The user has not yet defined what nvites.me actually *is*, so all placeholder docs have `<!-- TODO -->` markers awaiting a vision session.

## What was done (this session)

1. Copied UWZ monorepo into `/home/zik/programming/nvites-me/monorepo/`, removed `.git`, initialized fresh repo
2. Created separate git repo at `../claude/` for docs/skills (symlinked into monorepo — same pattern as UWZ)
3. Isolated DB: all code paths point to `nvites` schema, `ALLOWED_TEST_DATABASES` updated, CI uses `nvites_test`
4. Removed cli-idropr, cli-tako (leaf CLIs)
5. Relocated `EntityStatus` to `common.rs`, stripped booking fields from `HeldPaymentDto`
6. Gutted api-contracts: deleted bookings.rs, albums.rs, waivers.rs, queue_entries.rs, extractions.rs and all path modules. Moved `PaymentNonce` to payments.rs
7. Renamed `uwz` → `nvites` across 68 files (crate names, package names, Tauri identifiers, import paths)
8. Stripped docs: Architecture.md rewritten for current crate layout, DECISIONS.md filtered from 170→99 entries and renumbered, 8 docs stubbed with TODO placeholders, style guides preserved as-is
9. Updated skills: dispatch, handoff, orient now use file-based dispatches in `docs/dispatches/`

## What was NOT done

- **Slices 4-9**: schema-emitter, api crate, database, sdk-rust, sdk-ts, surfaces. The codebase does not compile. See `DEV_REMAINING_SURGERY_SLICES.md` for the full plan and red team landmines.
- **Handoffs cleanup**: 80+ UWZ handoff files still in `handoffs/`. See `DEV_HANDOFFS_CLEANUP.md`.
- **Payment FK**: `payment_transaction.booking_id` still exists in both the DTO and DB. See `SERVER_PAYMENT_BOOKING_FK.md`.
- **npm scope**: `@nvites` not registered. See `DEV_NPM_SCOPE_REGISTRATION.md`.
- **Project vision**: The user has not defined what nvites.me is. Architecture.md has a TODO placeholder. Don't guess — ask.
- **Website content**: All UWZ branding copy (paintball, Houston, directions, FAQs, etc.) still lives in surface-website Svelte components. This is a future content pass, not part of the foundation stripping.
- **`TABLES_TO_REMOVE.md`**: Lists ~40 orphaned DB tables. No migration written yet. The `booking` table specifically cannot be dropped until the FK from `payment_transaction` is severed.

## Things to know

- **Two repos**: monorepo at `nvites-me/monorepo/`, claude config at `nvites-me/claude/`. Docs/skills are symlinked. Commit to both.
- **Docker MySQL is stopped**: The user intentionally stopped the docker instance to prevent accidental writes to the UWZ `uwz` schema. The `nvites` schema doesn't exist yet — `CREATE DATABASE nvites;` is needed when Docker comes back.
- **No remote**: Neither repo has a remote. These are local-only right now.
- **The user's working style**: Moves fast, thinks out loud, wants pushback. Trusts your judgment but expects you to flag risks. Prefers commits at natural checkpoints. Does not want you working outside the current directory tree without asking.
- **CLAUDE.md anti-patterns still apply**: Don't read .env files, don't commit docs/ or archive/ from the monorepo (they're symlinks), ask before working outside the tree.

## Things to avoid

- Don't try to `cargo build` without completing slices 4-5 at minimum — it will fail loudly on hundreds of missing types
- Don't guess what nvites.me is about — the user will define this intentionally
- Don't touch the UWZ project at `/home/zik/programming/uwz/` — that's production
- Don't write migrations against a running DB without confirming the schema name is `nvites`
- Don't remove the `handoffs/` directory structure entirely — keep `.gitkeep` files so the skill has write targets

## Recommended next session flow

1. `/orient` — will pick up all dispatches including this one
2. Ask the user: "Want to continue the surgery slices, or define the project direction first?"
3. If surgery: start with slice 4 (schema-emitter) — it's mechanical and unblocks everything downstream
4. If direction: fill in Architecture.md Intent section, then the TODO-stubbed docs become actionable

## Confidence

**High** — the plan is solid, the red team was thorough, and every commit is a rollback point
