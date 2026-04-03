# Architectural Decisions

<!-- next-id: DEC-103 -->

> Canonical log of architectural decisions promoted from session handoffs.
> Only edited on the integration branch (dev).

---

## DEC-001 — Price snapshot at order/transaction creation time (2026-02-16)
**Source**: `handoffs/server/2026-02-16-bookings-build.md`
`price_cents` is copied from the product at creation time. Never accepted from the client. Protects against price manipulation and preserves historical accuracy when product prices change. Convention applies to any entity that records a price at the moment of commitment (orders, line items, add-ons).

## DEC-002 — UUID reference codes: 16-char alphanumeric (2026-02-16)
**Source**: `handoffs/server/2026-02-16-bookings-build.md`
Reference codes use `Uuid::web_safe_with_nums(16)` — 16-character alphanumeric strings. Convention applies to all public-facing entity identifiers.

## DEC-003 — SELECT ... FOR UPDATE for overlap prevention (2026-02-16)
**Source**: `handoffs/server/2026-02-16-bookings-build.md`
Double-booking is prevented by `SELECT ... FOR UPDATE` inside a transaction, serializing concurrent writes to the same resource/time range. V1 treats any overlap as rejection; capacity-based counting deferred.

## DEC-004 — All DATETIME stored as UTC (2026-02-16)
**Source**: `handoffs/server/2026-02-16-bookings-build.md`
All DATETIME columns store UTC values. API layer handles timezone conversion for display. Cross-crate convention — all surfaces and SDKs must send/receive UTC.

## DEC-005 — Committed `dist/openapi.json` as bootstrap artifact (2026-02-17)
**Source**: `handoffs/cross-cutting/2026-02-17-build-system-reorg.md`
`dist/openapi.json` is committed (not gitignored) so that `include_str!` in the API crate works on clone-and-build without running the pipeline first. Pipeline overwrites on run; CI catches staleness.

## DEC-006 — `api-contracts` extracted to monorepo root (2026-02-18)
**Source**: `server/handoffs/api-types-migration.md`
The shared types crate was renamed from `api-types` to `api-contracts` and moved from `server/api-types/` to the monorepo root at `api-contracts/`. Zero server/actix dependencies (only serde, utoipa, chrono). Standalone crate consumed by server workspace crates via path deps. SDKs will consume it directly when they become real — until then, YAGNI keeps it simple.

## DEC-007 — Contract types live in api-contracts (2026-02-18)
**Source**: `handoffs/crosscutting/2026-02-18-workflow-engine-slice-4.md`
api-contracts is the contract boundary for domain types. `ContextValue`, `ContextValueType`, `AdvanceResult`, `InstanceStatus`, request bodies, and DTOs all live in api-contracts. Server re-exports them. Engine-internal types remain server-only until CLI/SDK consumers need them.

## DEC-008 — api-contracts types return Option, not Result (2026-02-18)
**Source**: `handoffs/crosscutting/2026-02-18-workflow-engine-slice-4.md`
api-contracts has zero server dependencies. Functions like `InstanceStatus::from_u8()` return `Option<Self>` instead of `Result<_, Error>` because error types live in the server. Call sites in the server use `.ok_or(Error::...)` to convert. Convention: all fallible api-contracts functions use `Option`, never server error types.

## DEC-009 — Workflow engine is pure: no DB, no side effects (2026-02-18)
**Source**: `handoffs/crosscutting/2026-02-18-workflow-engine-slice-1.md`
`WorkflowEngine` is a zero-sized struct with pure functions: `(definition, instance, now) → (AdvanceResult, Mutation)`. No database access, no IO, no side effects. A separate service layer wraps engine calls with DB reads/writes. This boundary enables offline use (CLI simulation), deterministic testing, and future extraction to a shared crate.

## DEC-010 — Executor generic pattern for DB method deduplication (2026-02-18)
**Source**: `handoffs/crosscutting/2026-02-18-workflow-engine-slice-3.md`
DB types should use a shared inner function generic over `sqlx::Executor` instead of duplicating `foo()` + `foo_as_transaction()` methods. One copy of the logic, half the bug surface for column additions. Workflow instance pioneered this pattern; existing types (`secret.rs`, `person.rs`, `email_verification.rs`) can be migrated opportunistically. New types should follow this pattern.

## DEC-011 — Actor identity comes from auth context, not request body (2026-02-19)
**Source**: `handoffs/crosscutting/2026-02-19-cleanup-cancel-reason-jsonconfig.md`
`actor` and `created_by` fields in request bodies must come from the authenticated user context, not the request body. Prevents identity spoofing. This is a contract change affecting api-contracts request bodies; do it before more endpoints copy the pattern.

## DEC-012 — Definition contract types extracted to api-contracts (2026-02-19)
**Source**: Workflow engine slice 5
Definition-side types (`DefinitionStatus`, `ContextFieldDef`, `StepDefinition`, `StepType`, `AutoConfig`, `ContextSchema`) plus request bodies and response DTOs extracted to api-contracts. Extends DEC-007 scope. Engine-internal types (`ComparisonOp`, `Operand`, `ConditionAst`) tagged along because step types embed them as `#[serde(skip)]` fields — extracting them avoids engine refactoring. These 3 types have no `ToSchema`, no wire visibility. Server re-exports all types; existing tests compile unchanged against re-exported types.

## DEC-013 — All migrations live in server/migrations/ (2026-02-19)
**Source**: `handoffs/crosscutting/2026-02-19-seed-lookup-tables.md`
All SQL migrations (schema and seed data) live in `server/migrations/`. The initial 80-table schema was moved from `monorepo/migrations/` to consolidate. `cargo xtask db-reset` resolves `server/migrations/` via `workspace_dir()` — a separate `monorepo/migrations/` directory is invisible to it. New migrations always go in `server/migrations/`.

## DEC-014 — Lookup table seeds are migrations with values matching Rust enum discriminants (2026-02-19)
**Source**: `handoffs/crosscutting/2026-02-19-seed-lookup-tables.md`
Lookup tables with Rust enum counterparts (`campaign_status`, `user_type`, `user_account_status`, `server_mode`, `email`) are seeded via SQL migration with explicit IDs matching `repr(u8)`/`repr(u64)` discriminants. Comments in the migration reference the Rust source file. Tables without a Rust enum are left empty for population via Workbench. Adding a new enum variant requires a corresponding seed migration.

## DEC-015 — Role-based auth sufficient for internal phase; entity-level deferred (2026-02-19)
**Source**: `handoffs/crosscutting/2026-02-19-workflow-auth-audit.md`
Workflow endpoints use role-based authorization only (SysAdmin for mutations, Editor for reads/instance ops). No entity-level checks exist — any Editor can operate on any instance. This is acceptable while all users are internal staff. Entity-level auth (parent entity → organization resolution) is required before public launch but blocked on org tables, membership infrastructure, and entity resolvers that don't exist yet. Flag for pre-launch hardening.

## DEC-016 — Per-field PATCH updates accepted despite COALESCE style guide (2026-02-19)
**Source**: `handoffs/crosscutting/2026-02-19-booking-resource-crud.md`
The style guide (`docs/RUST_STYLE_GUIDE.md`) prescribes single COALESCE UPDATEs for PATCH endpoints. No handler in the codebase follows this — both `users_patch.rs` and `resources_patch.rs` use individual UPDATE queries per field. The style guide is arguably more correct (atomicity), but the current pattern is acceptable at V1 scale. Style guide left as-is as the aspirational target. Future PATCH handlers may use either pattern; refactor to COALESCE is not urgent.

## DEC-017 — sdk-rust re-exports domain types for CLI consumers (2026-02-20)
**Source**: `handoffs/cli-tako/2026-02-20-user-commands.md`
Types required to call SDK methods (request enums, DTOs like `UserDto`, `UserStatus`, `UserType`) are re-exported from `sdk-rust::types` so CLI crates depend only on `sdk-rust`, not directly on `api-contracts`. Keeps the dependency graph clean: api-contracts → sdk-rust → cli-{name}.

## DEC-018 — Suppression tables renamed for naming consistency (2026-02-20)
`email_bounce_status` → `suppression_status`, `email_bounce_list` → `suppression_list`. Aligns DB naming with Rust types (`SuppressionStatus`, `SuppressedEmail`) and Postmark domain terminology. "Suppression" is the accurate umbrella term — the status covers bounces, spam complaints, manual blocks, and unsubscribes. Migration-only change; no Rust type renames needed.

## DEC-019 — Product table holds common columns; subtables dropped (2026-02-20)
**Source**: Shop/product catalog planning session
Expand `product` with name, description, price_cents, status_id, timestamps. Drop `digital_product` and `physical_product` — no FK references, no Rust types, no useful columns. The `product` table now serves all product types (add-ons, gift cards, merchandise) with `product_type_id` as discriminator.

## DEC-020 — ProductType enum: Addon=0, GiftCard=1, Merchandise=2 (2026-02-20)
**Source**: Shop/product catalog planning session
0-based enum-backed lookup (DEC-014 convention). `product_type` table modified to remove AUTO_INCREMENT (MySQL treats `INSERT id=0` with AUTO_INCREMENT as "generate next"). Addon = checkout items. GiftCard = gift certificates. Merchandise = future retail.

## DEC-021 — Category is a shared data table, not an enum (2026-02-20)
**Source**: Shop/product catalog planning session
Seeded with 8 business categories (Paintball, Parties, GellyBall, Corporate, Axe Throwing, Equipment, Paint & Ammo, Gift Cards). IDs start at 1 (MySQL AUTO_INCREMENT, content-managed data table, not enum-backed). No Rust `Category` enum — categories are managed via Workbench.

## DEC-022 — Cart tables dropped; redesigned in Phase 2 (2026-02-20)
**Source**: Shop/product catalog planning session
`cart_items` has confirmed FK bug (references `category` instead of `product`). `cart_session` has no user linkage. Both dropped. Cart will be redesigned in Phase 2 with person linkage, expiry, and proper FK relationships.

## DEC-023 — Shop table dropped; single-tenant assumption (2026-02-20)
**Source**: Shop/product catalog planning session
`shop` implies multi-tenant infrastructure that doesn't exist. Product status lives on `product.status_id`. Dropped with no replacement needed.

## DEC-024 — Shop system ships in three phases (2026-02-20)
**Source**: Shop/product catalog planning session
Phase 1 (current): Products + catalog CRUD, API endpoints, price snapshot. Phase 2 (future): Cart, orders, payments — gift card generation/redemption, `order` + `order_item` + `payment_transaction` tables, redesigned cart with person linkage, payment gateway integration. Phase 3 (future): Cross-sell, upsell recommendations, discount codes, promotional pricing.

## DEC-025 — SecretController takes &self uniformly; &mut self retired (2026-02-20)
**Source**: `handoffs/cli-tako/2026-02-20-master-password-rotation.md`
All `SecretController` methods take `&self`, writing through the internal `RwLock`. The `&mut self` pattern is retired for this type. Enables sharing via `AppState` without outer mutability. `PoisonedMasterPassword` error variant covers the lock-poisoned edge case.

## DEC-026 — Client::send() and Client::send_empty() are canonical SDK method patterns (2026-02-20)
**Source**: `handoffs/cli-api-testing/2026-02-20-shop-workflow-sdk-body-matchers.md`
`Client::send<T>(req)` (auth + build + execute + deserialize `ApiSuccess<T>`) and `Client::send_empty(req)` (auth + build + execute + status check, returns `Result<()>`) replace the manual 5-line chain. All new SDK client methods must use one of these two helpers. Both are public API.

## DEC-027 — Secrets use name-based routing, not ID-based (2026-02-20)
**Source**: `handoffs/crosscutting/2026-02-20-secret-crud-name-routing.md`
Secret CRUD endpoints use `/{name}` path parameters instead of `/{id}`. Names are the natural identifier for secrets (operators think in names like `STRIPE_KEY`, not database IDs). SDK methods changed from `id: i64` to `name: &str`. CLI args changed accordingly.

## DEC-028 — Secret name format: [A-Za-z0-9_-]{1,64} (2026-02-20)
**Source**: `handoffs/crosscutting/2026-02-20-secret-crud-name-routing.md`
Secret names are validated on create and rename with `[A-Za-z0-9_-]{1,64}`. Returns 422 with `SecretNameInvalid` (error code 1009). Validation is server-side — all consumers get consistent enforcement.

## DEC-029 — env.d.ts module augmentation for SvelteKit PUBLIC_* vars (2026-02-20)
**Source**: `handoffs/surface-website/2026-02-20-type-errors-and-reactivity.md`
SvelteKit surfaces declare `PUBLIC_*` environment variables via `env.d.ts` module augmentation of `$env/static/public`. Provides type checking independent of `.env` file presence. Convention applies to all `surface-{name}` SvelteKit crates.

## DEC-030 — ORDER BY tiebreaker: append `id DESC` when ordering by non-unique columns (2026-02-21)
**Source**: `handoffs/server/2026-02-21-secrets-guard-workflow-fix.md`
MySQL `DATETIME` has only second-level precision. Any `ORDER BY` on a non-unique column (e.g. `created_at`) must include `id DESC` as a tiebreaker for deterministic ordering. Convention applies to all server queries.

## DEC-031 — Bearer tokens must never reach client JS; web surfaces use SSR-only loads (2026-02-21)
**Source**: SKILL.md/build-plan.md alignment review, red-teamed
Bearer tokens and authentication credentials must never be serialized to client-side JavaScript in any surface. Web surfaces (surface-website) enforce via `+page.server.ts` for all load functions — no universal loads (`+page.ts`, `+layout.ts`). Four independent constraints make this permanent: (1) HTTP-only cookie readable only server-side via `locals.token`, (2) SDK uses global `fetch` not SvelteKit's context-aware `fetch`, (3) `API_BASE_URL` is `$env/static/private` unavailable in browser, (4) keeping tokens server-side is simply better security. Desktop surfaces (surface-command-center) use `adapter-static` with `ssr = false` — server loads are physically impossible; auth enforced via Tauri secure storage and IPC. "SSR-everywhere" applies to SvelteKit load functions only — client-side reactivity, WebSocket connections, and `+server.ts` API endpoints are unaffected. Session metadata (username, role, expiry) returned from server loads is permitted. Portal CSR migration is cancelled, not deferred — SSR is the correct and intentional pattern. SKILL.md and SVELTE_STYLE_GUIDE.md corrected to match.

## DEC-032 — Migrations are immutable once applied (2026-02-22)
**Source**: `handoffs/crosscutting/2026-02-22-fix-sqlx-migration-tracking.md`
SQL migrations must not be edited after being applied to any database. Post-apply edits cause checksum mismatches in `_sqlx_migrations`, breaking `sqlx migrate run`. If a migration's contents need correction after apply, create a new migration file with the fix. This was discovered when `seed_lookup_tables.sql` was modified post-apply to rebase `user_type` IDs, causing a checksum mismatch that required manual DB repair.

## DEC-033 — `.env` lives at monorepo root, not per-crate (2026-02-22)
**Source**: `handoffs/server/2026-02-22-integration-test-verification.md`
The `.env` file lives at the monorepo root (`uwz/.env`). The `dotenv` crate climbs the directory tree to find it, so per-crate or per-worktree `.env` files are unnecessary. Server, CLIs, and xtask all resolve from the same root file. Do not create `.env` files inside `server/` or other crate directories.

## DEC-034 — EntityStatus renamed from ShopStatus (2026-02-23)
**Source**: `handoffs/server/2026-02-23-albums-crud.md`, crosscutting rename session
Contract change. `ShopStatus` renamed to `EntityStatus` across api-contracts, server, sdk-rust, sdk-ts, and cli-api-testing. The enum is the shared active/inactive status for multiple domains. DB table `shop_status` and `status_id` FK columns are unchanged — the rename is code-only. Now lives in `common.rs` in api-contracts. Migration immutability (DEC-032) prevents renaming the DB table.

## DEC-035 — Exclusively-owned child tables use ON DELETE CASCADE (2026-02-23)
**Source**: `handoffs/server/2026-02-23-albums-crud.md`
Tables that exclusively own their children use `ON DELETE CASCADE` on the child FK. In practice these parent rows are never deleted (soft delete via status), so CASCADE is a GDPR safety net, not an operational path. Convention for new parent-child relationships where the child has no independent existence.

## DEC-036 — Data entities use status deactivation, not DELETE endpoints (2026-02-23)
**Source**: `handoffs/server/2026-02-23-albums-crud.md`
Entities with business history are deactivated via `PATCH status=inactive`, never deleted. No DELETE endpoints exist for these types. This preserves referential integrity, audit trails, and historical data. Only transient or join-table records (sessions) expose DELETE. Convention for all future data entity types.

## DEC-037 — Tauri invoke args use camelCase keys (2026-02-23)
**Source**: `handoffs/surface-command-center/2026-02-23-checkin-integration-test.md`
Tauri's `invoke()` bridge applies `serde(rename_all = "camelCase")` by default on the Rust command side. JavaScript callers must use camelCase keys in the args object, not snake_case. This is a Tauri framework convention, not a project choice — but it's a recurring source of silent failures (arg appears as `undefined` on the Rust side). Convention applies to all `surface-{name}` Tauri crates.

## DEC-038 — Svelte 5 controlled inputs: $state + bind:value (2026-02-24)
**Source**: `handoffs/surface-website/2026-02-24-login-fix-gallery-share.md`
In Svelte 5, `<input value={prop}>` makes the browser's constraint validation see the prop value, not user input — `required` silently blocks submission with no tooltip. All form components must use `let val = $state(value)` with `bind:value={val}` instead of passing `value` as a read-only prop. No `$effect` sync is needed when `use:enhance` keeps the component mounted.

## DEC-039 — docs/structured-data/ directory for shared reference data (2026-02-24)
**Source**: `handoffs/crosscutting/2026-02-24-structured-data-seo-skill-review.md`
`docs/structured-data/` is the convention for shared, non-branch-specific reference data files (business identity, location, etc.). First candidate: `business-identity.json` when ai-discoverability init runs. These files are consumed by skills and build tools, not by runtime code.

## DEC-040 — PostHog is the sole analytics service; reverse proxy at /ingest/ (2026-02-25)
**Source**: `handoffs/surface-website/2026-02-25-posthog-only-analytics.md`
GA4 and Facebook Pixel removed (dead code, never mounted). PostHog is the only analytics service across all web surfaces. Client JS configured with `api_host: '/ingest'` — a SvelteKit server route at `/ingest/[...path]/+server.ts` proxies all PostHog requests to `us.i.posthog.com`, defeating ad blockers. Session replay enabled with `maskAllInputs: true`. CSP trimmed to match (removed GA/FB script-src entries). Convention: no analytics JS loads from third-party domains; all analytics traffic routes through the reverse proxy.

## DEC-041 — 422 is the default HTTP status for unmapped client-facing errors (2026-02-26)
**Source**: `handoffs/server/2026-02-26-error-to-http-migration.md`
Validation and business-logic errors that don't fit a specific HTTP status category (404, 409, 400, 413, etc.) get 422 Unprocessable Entity via the `_ =>` fallback in `http_status()`. New client-facing error variants automatically receive a reasonable status without touching `http_status()`. Variants that need a different status get an explicit match arm.

## DEC-042 — Additive Serialize/Deserialize derives in api-contracts are contract-safe (2026-02-26)
**Source**: `handoffs/sdk-rust/2026-02-26-queue-client.md`
Adding `Serialize` to request body types and `Deserialize` to DTO types in api-contracts is an additive derive change with no wire format impact. Every SDK-consumed type already has both. This is a standing convention — future SDK work can add missing derives without treating them as contract changes.

## DEC-043 — Website color tokens: hex sRGB, OKLCH deferred, glass effects excluded (2026-02-26)
**Source**: `handoffs/surface-website/2026-02-26-color-token-foundation.md`
Hex sRGB values are acceptable for token definitions. OKLCH migration deferred until there's a perceptible reason. Glass effects, per-component shadows, form fields, and body gradient are intentionally excluded from the token system — they are intentional variation, not accidental duplication.

## DEC-044 — npm test is a functional gate for sdk-ts (2026-02-26)
**Source**: `handoffs/crosscutting/2026-02-26-sdk-ts-test-bootstrap.md`
vitest bootstrapped with coverage of all 5 `request()` branches. `cd sdk-ts && npm test` is now a functional build gate alongside the existing Rust gates. Should be added to CI when CI is configured.

## DEC-045 — Intent token name: `--color-intent-primary`, not `intent-action` (2026-02-27)
**Source**: `handoffs/surface-website/2026-02-26-intent-token-adoption.md`
`--color-intent-primary` is the settled name for the amber attention token. "Primary" means "the primary thing to pay attention to" — covers both interactive elements (CTAs, links) and decorative elements (eyebrows, accent lines, star ratings, scroll indicators). `intent-action` was rejected as semantically incorrect for decorative uses. All homepage files now consume this token; new components should use it instead of hardcoded `#f59e0b`.

## DEC-046 — Alpha variants via `color-mix()`, not raw `rgba()` (2026-02-27)
**Source**: `handoffs/surface-website/2026-02-26-intent-token-adoption.md`
`color-mix(in srgb, var(--token) N%, transparent)` is the convention for deriving alpha-variant border/glow values from design tokens. Keeps the base color tied to the token so palette changes propagate automatically. Don't reach for raw `rgba()` when a token covers the base color.

## DEC-047 — SessionMeDto.role is Option<Role> — nullable for non-standard bitmasks (2026-03-06)
**Source**: `handoffs/server/2026-03-06-session-me-endpoint.md`
`SessionMeDto.role` is `Option<Role>`. If a user's permission bitmask doesn't exactly match a known role (e.g., custom permissions granted manually), the client receives `null` instead of a 500. This is a safety valve — `from_role()` is currently the only assignment path so it should always resolve, but the contract protects against future edge cases. Note: `to_role()` was later fixed to use superset matching (bitmask & role == role), so admin users with extra bits now resolve correctly.

## DEC-048 — pnpm is the JS package manager for all monorepo JS/TS projects (2026-03-06)
**Source**: `handoffs/server/2026-03-06-xtask-sdk-ts-codegen.md`
Root `pnpm-workspace.yaml` lists `sdk-ts`, `surface-command-center`, `surface-website`. No npm lockfiles should exist in workspace members. `cargo xtask build-all` invokes `pnpm run generate` for sdk-ts codegen.

## DEC-049 — Build tools assume prerequisites are installed (2026-03-06)
**Source**: `handoffs/server/2026-03-06-xtask-sdk-ts-codegen.md`
xtask and other build tools fail with a clear message rather than auto-installing dependencies. `pnpm install`, `cargo`, and `sqlx` are manual prerequisites. Keeps the build deterministic and avoids surprise network fetches.

## DEC-050 — $app/state over $app/stores for Svelte 5 surfaces (2026-03-05)
**Source**: `handoffs/surface-command-center/2026-03-05-review-fixes-role-gating-gap.md`
All Svelte surfaces use `$app/state` (Svelte 5 runes-based API) instead of the legacy `$app/stores`. SvelteKit 2.12+ required. Applies to both web and Tauri surfaces.

## DEC-051 — Role rank model: linear hierarchy (2026-03-05)
**Source**: `handoffs/surface-command-center/2026-03-05-role-gated-nav.md`
`user(0) < editor(1) < sys_mod(2) < sys_admin(3)`. `hasRole(minRole)` checks `ROLE_RANK[userRole] >= ROLE_RANK[minRole]`. Matches server's `route-map.json` `min_role` convention. Used for nav visibility gating in Tauri surfaces and available for any surface that needs role-based UI filtering.

## DEC-052 — Opaque success responses on public POST endpoints (2026-03-06)
**Source**: `handoffs/surface-website/2026-03-06-call-ahead-queue.md`
Public POST endpoints return the same success response regardless of whether the email exists, the record was created, or the record was updated. Prevents email enumeration. Applies to any future public endpoint that accepts user-identifying input.

## DEC-053 — `to_role()` uses superset matching, not exact equality (2026-03-07)
**Source**: `handoffs/crosscutting/2026-03-07-to-role-superset-fix.md`
`to_role()` changed from exact bitmask equality (`self.mask == role.mask`) to superset matching (`self.mask & role.mask == role.mask`). This aligns display behavior with `has_permission()` — a user with admin+extra bits now correctly resolves to `SysAdmin` instead of returning `None`. Amends the safety note in DEC-047.

## DEC-054 — Date range filter params on workflow instance list (2026-03-07)
**Source**: `handoffs/crosscutting/2026-03-07-date-range-filter-instances.md`
`GET /v1/workflow-instances` accepts optional `created_after` and `created_before` query params (ISO 8601 datetime). Introduced `FilterParams` struct to replace positional args in the database query builder. Convention: list endpoints with temporal filtering should use this struct pattern.

## DEC-055 — SEO title template: "%s | Urban War Zone Houston" (2026-03-07)
**Source**: `handoffs/surface-website/2026-03-07-seo-audit-and-plan.md`
`seo.json` `defaults.titleTemplate` is `"%s | Urban War Zone Houston"` — "Paintball" dropped from the suffix to keep rendered titles under 60 characters. Content pages provide `%s` as their unique page title.

## DEC-056 — Testing strategy: layers 1-3, no E2E until pre-launch (2026-03-08)
**Source**: `handoffs/surface-command-center/2026-03-08-testing-infrastructure.md`
Testing scope covers layers 1-3: utilities, SDK query construction, and viewmodel error contracts. Layer 4 (component rendering) deferred. No E2E until pre-launch. Vitest 4 for TypeScript, Rust unit tests for SDK. Test pattern: `vi.mock('$lib/api/commands')` + `flushPromises()` + assert reactive state.

## DEC-057 — Postmark MessageStream enum maps 1:1 to dashboard stream names (2026-03-08)
**Source**: `handoffs/surface-website/2026-03-08-postmark-streams-queue-cinematic.md`
`MessageStream` enum variants map directly to Postmark dashboard stream names (`events-marketing`, `sales`, `subscriptions`, `internal`). Stream is specified only via serde `rename` — no `Display` impl, no HTTP header override. Single source of truth for stream routing.

## DEC-058 — Dev mode loads DB settings identically to production (2026-03-08)
**Source**: `handoffs/surface-website/2026-03-08-postmark-streams-queue-cinematic.md`
`dev_state()` calls `.with_database_settings()` to load DB-driven feature flags (e.g., `postmark_email_service`) the same way `prod_state()` does. Without this, flags silently default to `Disabled` in dev, masking real behavior. Any new `SystemFlag` added to `system_settings` must work in both startup paths.

## DEC-059 — Password length validation: 8 min, 72 max, enforced before bcrypt (2026-03-10)
**Source**: `handoffs/crosscutting/2026-03-10-server-security-hardening.md`
Server validates password length (8–72 characters) before hashing. The 72-byte ceiling is bcrypt's hard limit — bytes beyond 72 are silently truncated, so a 100-char password and its first-72-char prefix produce the same hash. All surfaces that collect passwords must enforce compatible limits. Server is the authority; client-side limits are UX hints only.

## DEC-060 — Error Display redaction for sensitive error variants (2026-03-10)
**Source**: `handoffs/crosscutting/2026-03-10-server-security-hardening.md`
The server error enum's `Display` impl redacts sensitive variants (`Sqlx`, `DatabaseError`, `IoError`, `DatabaseConnection`) to generic messages. This prevents SQL queries, connection strings, and file paths from leaking into HTTP responses or logs. Non-sensitive unit-type variants use `Debug` formatting. Full structured logging (tracing crate) is the eventual replacement for the remaining `_ => {self:?}` catch-all.

## DEC-061 — Session logout deletes DB row; GC sweeps expired sessions (2026-03-10)
**Source**: `handoffs/crosscutting/2026-03-10-server-security-hardening.md`
`POST /v1/auth/logout` deletes the session row from the database (not just the in-memory cache). The GC cycle sweeps expired DB rows each pass using a read lock for the scan phase. This ensures logout is durable across server restarts and that orphaned sessions are eventually cleaned up without holding a write lock during the scan.

## DEC-062 — epoch_check denies disabled users at 401 (2026-03-10)
**Source**: `handoffs/crosscutting/2026-03-10-server-security-hardening.md`
`epoch_check` (session refresh) uses `by_id_enabled` instead of `by_id_unchecked`. A user disabled after login is denied at the next epoch refresh with 401, not allowed to continue until their session expires naturally. Defense-in-depth: permission checks are the primary gate, but epoch refresh is the backstop that catches disabled accounts within one refresh cycle.

## DEC-063 — Epoch-based change detection replaces callback threading (2026-03-10)
**Source**: `handoffs/crosscutting/2026-03-10-epoch-change-detection.md`
Server maintains per-domain atomic epoch counters (`EpochDomain::Workflow | Queue`) bumped by `EpochBump` middleware on mutation scopes. Clients poll `GET /v1/epochs` with 1-5s jitter; refetch only when their domain epoch is stale. Replaces `onMutate` callback threading through 5+ component layers. Both SDKs (Rust, TypeScript) and Tauri commands wired. New domains require adding an `EpochDomain` variant and an `AppState` field.

## DEC-064 — Structured logging via tracing replaces all eprintln/println (2026-03-11)
**Source**: `handoffs/crosscutting/2026-03-11-structured-logging-server-audit.md`
The server uses `tracing` + `tracing-subscriber` + `tracing-actix-web` for all diagnostic logging. Dev mode: compact human-readable output. Prod mode: JSON lines (consumable by log aggregators without configuration). Default filter: `info,sqlx=warn`, overridable via `RUST_LOG`. `TracingLogger` middleware generates `x-request-id` on every request. One `println!` retained in the `database` crate (startup connection message) to avoid adding tracing as a dependency there.

## DEC-065 — FK references to person.id use INT, not BIGINT (2026-03-12)
**Source**: `handoffs/crosscutting/2026-03-12-booking-share-codes.md`
MySQL FK constraints require exact type match. `person.id` is `INT`. All migrations referencing `person.id` as a foreign key must use `INT`, not `BIGINT`. The Rust side uses `i64` (`User::id()`) which reads `INT` fine — the mismatch concern is purely at the DDL level.

## DEC-066 — deny_unknown_fields requires server-first deploy ordering (2026-03-11)
**Source**: `handoffs/surface-website/2026-03-11-queue-time-selector.md`
Request body types annotated with `#[serde(deny_unknown_fields)]` create a deploy ordering constraint: server must deploy before surfaces when new fields are added to those types. If a surface sends a field the server doesn't yet recognize, the request returns 400. After both are deployed, they are decoupled — server restarts don't require surface redeployment.

## DEC-067 — CI enforces fmt + clippy + tests on push/PR (2026-03-12)
**Source**: `handoffs/crosscutting/2026-03-12-ci-readiness-fmt-clippy-actions.md`
GitHub Actions CI runs two parallel jobs on push/PR to main/staging/dev: `check` (cargo fmt --check + clippy -D warnings for server + api-contracts) and `test` (MySQL 8.0 service container, migrations, full test suite). Codebase is `cargo clippy -D warnings` clean as of baseline commit. `.git-blame-ignore-revs` contains the formatting commit SHA.

## DEC-068 — Shared validators live in `api::validation` module (2026-03-12)
**Source**: `handoffs/crosscutting/2026-03-12-ci-readiness-cleanup.md`
`is_valid_email()` extracted to `crate::api::validation` as the single shared email validator. New handlers import from this module instead of defining inline copies. Convention: any reusable request-level validation logic belongs in `api::validation`, not duplicated per handler.

## DEC-069 — Unverified (4) separates registration lifecycle from admin-disabled (2026-03-13)
**Source**: `handoffs/crosscutting/2026-03-13-unverified-status-sweeper.md`
`UserAccountStatus::Unverified = 4` is a new variant in api-contracts, distinct from `Disabled = 0`. `Disabled` is now exclusively an admin action; `Unverified` is the initial state for self-registered accounts awaiting email verification. The sweeper deletes `Unverified` accounts after 24 hours. All surfaces rendering user status must handle the new variant. The admin PATCH endpoint rejects `Unverified` at handler level (not structurally) — sufficient until a third status-restricted operation appears.

## DEC-070 — Consumer-facing paths use uuid, staff paths use id (2026-03-14)
**Source**: `handoffs/crosscutting/2026-03-14-esign-phase2-record-access-audit.md`
Consumer-facing API paths (portal, public) use UUID path parameters for entity lookup; staff-gated paths (admin, SysMod) may use integer IDs. Sequential IDs on consumer paths create existence oracles (404 vs 403) and write amplification vectors on write-on-GET endpoints (e.g., audit-row insertion). If a future consumer-facing endpoint accepts `id` in a path, the UUID indirection is defeated.

## DEC-071 — No string interpolation in SQL statements (2026-03-14)
**Source**: `handoffs/crosscutting/2026-03-14-waiver-document-retrieval-integrity.md`
SQL queries must use literal strings with bind parameters, never `format!()` or string interpolation for table names, column names, or values. Discovered via SEC-3 remediation: audit trail insertion used `format!("INSERT INTO {table}")` in a loop. Replaced with explicit per-table `sqlx::query()` calls. Even when the interpolated value is not user-controlled, the pattern is banned — it defeats static analysis and sets a precedent for injection vectors.

## DEC-072 — `*OutOfBounds` DB-corruption errors are internal-only, no client-facing mapping (2026-03-16)
**Source**: `handoffs/server/2026-03-16-booking-source-slice01.md`
`BookingSourceOutOfBounds` and all other `*OutOfBounds` enum variants represent DB data corruption (invalid discriminant stored). They have no `to_api_error_message()` mapping and surface as generic 500 errors. This is intentional — clients have no meaningful action for corrupted data. New `*OutOfBounds` variants follow this convention.

## DEC-073 — Adopt `sqlx::QueryBuilder` for all dynamic SQL construction (2026-03-17)
**Source**: `handoffs/server/2026-03-17-querybuilder-migration.md`
All dynamic SQL sites must use `sqlx::QueryBuilder` instead of split `push_str`/`bind` patterns. The split pattern requires manual synchronization of clause ordering and bind ordering — a desync produces silent wrong-query or wrong-data bugs. `QueryBuilder` has been in the dependency tree since sqlx 0.6 (currently on 0.8.3).

## DEC-074 — Client IP via Railway `X-Real-IP`, not `X-Forwarded-For` (2026-03-18)
**Source**: `docs/DEV_AUDIT_RESULTS.md` (FINDING: Client IP Identification Is Broken)
Client IP identification uses Railway's `X-Real-IP` (public traffic, set by Railway's edge proxy, documented and authoritative) and BFF `X-Real-Client-IP` (private network, set by the SvelteKit BFF over Railway's WireGuard private network). `X-Forwarded-For` and Actix `ConnectionInfo::realip_remote_addr()` are banned — `X-Forwarded-For` is spoofable on platforms that append without stripping client-supplied values. Priority order: `X-Real-IP` first (always present on public requests via Railway's edge), `X-Real-Client-IP` second (only present on private-network BFF requests), `peer_addr` third (TCP socket address — local dev fallback, added 2026-03-20 via dispatch `DISPATCH_RATE_LIMIT.md`). Utility: `extract_client_ip()` in `api/validation.rs`, called by rate limit middleware and all 13 audit/rate-limit handler sites.

## DEC-075 — MySQL 8.4 as target database version (2026-03-19)
**Source**: `handoffs/server/2026-03-19-railway-deployment-infra.md`
CI, local Docker, and Cloud SQL all run MySQL 8.4. MySQL 8.0 EOL is April 2026. Tables with composite primary keys where another table's FK references a single column require an explicit `UNIQUE KEY` on the referenced column — MySQL 8.4 no longer infers uniqueness from the leftmost prefix of a composite PK. 8 tables were affected in the initial migration.

## DEC-076 — Per-service Dockerfiles for Railway deployment (2026-03-19)
**Source**: `handoffs/server/2026-03-19-railway-deployment-infra.md`
Auto-detection (Railpack/Nixpacks) cannot handle a mixed Rust+Node monorepo — both detect Node from `package.json`/`pnpm-workspace.yaml` at the root and ignore Rust. Each service gets its own Dockerfile (`server/Dockerfile`, `surface-website/Dockerfile`), referenced via `RAILWAY_DOCKERFILE_PATH` env var in the Railway UI. No root directory set on any service — build context is the full repo so cross-root dependencies (e.g., `api-contracts/` for the server) are accessible.

## DEC-077 — `PORT` replaces `SERVER_PORT`; `SHARDS` replaces `SERVER_THREADS` (2026-03-19)
**Source**: `handoffs/server/2026-03-19-railway-deployment-infra.md`
`PORT` is the standard Railway convention (Railway sets it automatically). `SHARDS` reflects actual usage — rate limiter and session controller sharding, not Actix worker threads. Production Actix workers auto-detect from CPU count; `SHARDS` controls internal data structure partitioning independently.

## DEC-078 — `DB_CERT` env var for hosted SSL (raw PEM) (2026-03-19)
**Source**: `handoffs/server/2026-03-19-railway-deployment-infra.md`
Priority: `DB_CERT` (raw PEM content, used on Railway where no filesystem cert access exists) > `DB_CERT_PATH` (file path, used in local dev) > no SSL (local Docker dev). Cloud SQL server CA cert is pasted directly into the env var including BEGIN/END markers.

## DEC-079 — `API_BASE_URL` uses `$env/dynamic/private` (2026-03-19)
**Source**: `handoffs/server/2026-03-19-railway-deployment-infra.md`
Switched from `$env/static/private` because the value differs per environment (local dev: `http://localhost:3000`, staging: `http://server.railway.internal:3000`, prod: same pattern with different service name). Read at runtime via `env.API_BASE_URL`, not baked into the SvelteKit build. `PUBLIC_*` vars remain static (baked at build time) since they're the same across environments.

## DEC-080 — Admin bootstrap via `uwz-server bootstrap` subcommand (2026-03-20)
**Source**: dev session, 2026-03-20
Initial admin user creation uses a `bootstrap` subcommand on the server binary, not manual SQL inserts or a seed migration. Reads `BOOTSTRAP_USERNAME`, `BOOTSTRAP_PASSWORD`, `BOOTSTRAP_EMAIL`, `BOOTSTRAP_FNAME` (required) and `BOOTSTRAP_LNAME` (optional) from env vars. Connects directly to the database — no HTTP server, no AppState. Idempotent: exits cleanly if a system user already exists. Hardcodes SysAdmin role (full permission bitmask). Runs locally against Cloud SQL, same as migrations. `BOOTSTRAP_*` vars are never set in production — the command cannot run without them, preventing rogue admin creation on hosted environments. Vars are deleted from `.env` after use.

## DEC-081 — Product catalog is operational data, lives in migrations (2026-03-21)
**Source**: `handoffs/crosscutting/2026-03-21-session-wrapup.md`
Products, resources, and prices are real operational data (the actual product line), not dev seed data. They belong in a versioned migration against the canonical baseline, not in `seed_dev_data.sql`. The seed script may reference IDs produced by that migration, but the authoritative product catalog is migration-managed.

## DEC-082 — Railway does not set HSTS; application must (2026-03-21)
**Source**: `handoffs/server/2026-03-21-server-audit-triage.md`
Railway's edge proxy does not set `Strict-Transport-Security` headers (confirmed empirically — Railway's own site omits it). The Rust server sets HSTS via Actix `DefaultHeaders` middleware. Any new surface that serves HTTP responses directly must also set HSTS at the application layer.

## DEC-083 — EmailID enum is canonical for all email metadata (2026-03-21)
**Source**: `handoffs/server/2026-03-21-server-audit-triage.md`
The `EmailID` enum is the single source of truth for email template names, subjects, and metadata. All email-sending code references `EmailID` variants rather than hardcoding template strings. New email types require a new `EmailID` variant.

## DEC-084 — CSP connect-src for API origin removed; superseded by BFF pattern (2026-03-20)
**Source**: `handoffs/surface-website/2026-03-20-api-guard-radius-unification.md`
The original decision to add `connect-src` for the API origin in CSP headers assumed the browser would make direct API calls. The BFF pattern (DEC-031) means all API traffic is server-to-server — the browser never needs `connect-src` for the API origin. The dynamic CSP append was removed entirely. Internal Railway hostnames are no longer exposed in browser-visible headers.

## DEC-085 — Loopback hostname check scoped to PRODUCTION/STAGING only (2026-03-20)
**Source**: `handoffs/surface-website/2026-03-20-api-guard-radius-unification.md`
The `API_BASE_URL` loopback/localhost check only runs when `PUBLIC_MODE` is `PRODUCTION` or `STAGING`. DEV and CONSTRUCTION legitimately use `localhost`. MAINTENANCE is handled by its own gate before the loopback check runs.

## DEC-086 — Invalid PUBLIC_MODE forces MAINTENANCE (2026-03-20)
**Source**: `handoffs/surface-website/2026-03-20-api-guard-radius-unification.md`
`PUBLIC_MODE` is validated at runtime against the `SiteMode` union type set. Unrecognized values (typos, empty strings) are treated as MAINTENANCE rather than silently passing through. This prevents a misconfigured env var from accidentally granting full access.

## DEC-087 — Sanitize WorkflowError at the choke point, not construction sites (2026-03-22)
**Source**: `handoffs/server/2026-03-22-workflow-error-sanitization.md`
`to_api_error_message()` is the single location where internal WorkflowError strings become HTTP response content. Logging and sanitization are co-located there. Future variants added to `WorkflowError` that carry internal strings must follow the same pattern — sanitize at the choke point, never at each call site.

## DEC-088 — Prerendering forbidden on `/prices` and `/book` (2026-03-22)
**Source**: `handoffs/surface-website/2026-03-22-book-prices-architecture.md`
Prices come from the product catalog and must be live. Stale structured data is a Google penalty risk. Both route trees are SSR-only.

## DEC-089 — Product `@id` deduplication across `/prices` and `/book` (2026-03-22)
**Source**: `handoffs/surface-website/2026-03-22-book-prices-architecture.md`
Canonical Product JSON-LD entities are defined on `/prices/[tier]` pages with stable `@id` attributes. `/book` references these `@id`s rather than defining duplicate Product entities. Prevents Google from seeing conflicting Product structured data.

## DEC-090 — `/prices` as pricing page slug (2026-03-22)
**Source**: `handoffs/surface-website/2026-03-22-book-prices-architecture.md`
Matches query language ("paintball prices," "how much does paintball cost"). Short, direct. Replaces `/rental-prices` which is the larger organic funnel (1,073 sessions vs 321 for reservations).

## DEC-091 — Authorize.Net as payment gateway (2026-03-23)
**Source**: `handoffs/server/2026-03-23-payments-plan-availability-fix.md`
Supersedes DEC-024's Stripe/Square reference. Authorize.Net selected for payment processing. Full integration plan (6 slices) in `docs/DISPATCH_PAYMENTS.md`.

## DEC-092 — Tax rate stored as basis points in system_settings (2026-03-23)
**Source**: `handoffs/server/2026-03-23-payments-plan-availability-fix.md`
`tax_rate_basis_points SMALLINT UNSIGNED` (e.g. 825 = 8.25%). Single rate, integer math, no floats. Queried via `with_database_settings` — no redeploy needed to change the rate.

## DEC-093 — SELECT ... FOR UPDATE on payment_transaction mutations (2026-03-24)
**Source**: `handoffs/server/2026-03-24-payment-slice4-void-refund.md`
All code that reads `payment_transaction` rows before making gateway calls (void, refund, webhook reconciliation) must lock the rows with `SELECT ... FOR UPDATE` to prevent concurrent reversals. Applies to any handler or background job that mutates financial records.

## DEC-094 — Tax calculation: integer-only with half-up rounding (2026-03-24)
**Source**: `handoffs/server/2026-03-24-slice3-charge-at-booking.md`
Tax computed as `(subtotal * rate_bp + 5000) / 10000` in u64. Single source of truth in `pricing.rs`. Both preview and charge paths use it. `api-contracts` types carry u32 cents; server computes in u64 to avoid overflow during multiplication.

## DEC-095 — rustfmt edition = source edition (2024) (2026-03-24)
**Source**: `handoffs/crosscutting/2026-03-24-rustfmt-edition-alignment.md`
`rustfmt.toml` edition must match crate `Cargo.toml` edition declarations. Aligned from 2021 to 2024 across all 17 crates. Prevents formatting drift where rustfmt applies older edition rules to newer edition code.

## DEC-096 — Raw Accept.js for payment tokenization (SAQ A-EP) (2026-03-24)
**Source**: `handoffs/surface-website/2026-03-24-accept-js-payment-form.md`
Client-side tokenization via Authorize.Net's Accept.js library (not hosted iframe). Card data tokenized via `Accept.dispatchData()` and never reaches UWZ server. SAQ A-EP compliance level accepted — owner confirmed full CSS control over payment form is the priority.

## DEC-097 — Payment errors as discriminated union, not exceptions (2026-03-24)
**Source**: `handoffs/surface-website/2026-03-24-accept-js-payment-form.md`
`createBooking` returns a discriminated union (`success | declined | held | error`), not thrown exceptions. Declined cards and held-for-review are expected control flow in payment processing, not exceptional conditions. Surfaces pattern-match on the variant to show appropriate UX.

## DEC-098 — Email images served from website domain (2026-03-25)
**Source**: `handoffs/server/2026-03-25-email-notifications-sdk-gap.md`
Transactional email images live in `surface-website/static/images/email/transactional/` and are referenced via `site_url` env var. Domain alignment (emails linking images from the same domain as the site) is a positive spam filter signal. Fallback to GCS bucket if deliverability issues arise. Affects all future email templates.

## DEC-099 — CAS pattern for gateway-then-record handlers (2026-03-25)
**Source**: `handoffs/server/2026-03-25-slice6-staff-payments.md`
Handlers that call an external gateway then update a local record must use compare-and-swap: `UPDATE ... WHERE status = expected_status`. No DB locks held during network calls, no reliance on external service idempotency. Applied to payment approve/decline; same pattern required for any future "call gateway, record locally, webhook reconciles" flow.

## DEC-100 — Case-sensitive code columns use utf8mb4_0900_as_cs, not utf8mb4_bin (2026-03-31)
**Source**: `handoffs/crosscutting/2026-03-31-collation-fix-handoffs-cleanup.md`, `handoffs/crosscutting/2026-03-30-dispatch-sweep-gateway-hardening.md`
`short_link.code` and `redirect_event.code` use `utf8mb4_0900_as_cs` collation for case-sensitive base62 comparison. `utf8mb4_bin` is banned for string columns — sqlx 0.8.x misinterprets MySQL's BINARY wire flag on `_bin` collation columns as actual binary data, crashing `String` decoding at runtime (sqlx#3387). `utf8mb4_0900_as_cs` provides identical case-sensitive semantics using MySQL 8.0's UCA 9.0 algorithm without the BINARY flag. This is the permanent fix, not a bridge to sqlx 0.9.0. Any future column requiring case-sensitive comparison must use `utf8mb4_0900_as_cs`.

## DEC-101 — sqlx 0.8 trigger migrations must use single-statement bodies (2026-03-29)
**Source**: `handoffs/crosscutting/2026-03-29-epoch-triggers-restored.md`
sqlx 0.8 enables `CLIENT_MULTI_STATEMENTS` in the MySQL handshake, splitting migration SQL on `;`. `BEGIN...END` compound trigger bodies break because internal semicolons are misinterpreted as statement boundaries. `DELIMITER` is a mysql CLI command, not server SQL, so it cannot help. All trigger migrations must use single-statement bodies. This constraint applies until sqlx changes its migration runner behavior.

## DEC-102 — Campaign status controls redirect behavior; link-level status deferred (2026-03-29)
**Source**: `handoffs/crosscutting/2026-03-29-link-cache-rewrite-review.md`
`CampaignStatus` (Draft, Active, Paused, Ended) determines whether a link redirects — all links in a campaign share its status. Individual link-level `status_id` on `short_link` is deferred until a product need for per-code pausing emerges. The gateway resolves campaign status via `CampaignStatus::is_redirectable()`. When link-level control is needed: add `status_id` to `short_link`, implement `Decode` for `LinkStatus`, and target it at the link's own column.
