# Architectural Decisions

<!-- next-id: DEC-169 -->

> Canonical log of architectural decisions promoted from session handoffs.
> Only edited on the integration branch (dev). See project-schema.json for protocol.

---

## DEC-001 — Product maps to resource type, not specific resource (2026-02-16)
**Source**: `handoffs/server/2026-02-16-bookings-build.md`
A booking product (e.g. "Birthday Blast 2hr") targets a `resource_type` (paintball_field), not a specific resource. The system assigns an available resource at booking time. This keeps products reusable and decouples inventory from catalog.

## DEC-002 — Price snapshot at booking creation (2026-02-16)
**Source**: `handoffs/server/2026-02-16-bookings-build.md`
`booking.price_cents` is copied from the product at creation time. Never accepted from the client. Protects against price manipulation and preserves historical accuracy when product prices change.

## DEC-003 — Anonymous and registered booking linking (2026-02-16)
**Source**: `handoffs/server/2026-02-16-bookings-build.md`
`booking.person_id` is nullable. Guest name/email/phone always populated. When a user creates an account, existing bookings are linked via email match (`UPDATE booking SET person_id = ? WHERE guest_email = ? AND person_id IS NULL`). Surfaces must handle both anonymous and linked bookings.

## DEC-004 — Operating hours: weekly recurring + per-date overrides (2026-02-16)
**Source**: `handoffs/server/2026-02-16-bookings-build.md`
`booking_operating_hours` stores weekly recurring hours (one row per open day; missing day = closed). `booking_schedule_override` stores per-date blackouts or modified hours. Availability checks consult both: override wins if present, else fall back to weekly schedule.

## DEC-005 — UUID reference codes: 16-char alphanumeric (2026-02-16)
**Source**: `handoffs/server/2026-02-16-bookings-build.md`
Booking reference codes use `Uuid::web_safe_with_nums(16)` — 16-character alphanumeric strings. Convention applies to all public-facing entity identifiers.

## DEC-006 — Booking table prefix convention (2026-02-16)
**Source**: `handoffs/server/2026-02-16-bookings-build.md`
All booking-related tables are prefixed with `booking_` (e.g. `booking_resource`, `booking_product`, `booking_status`) except the main `booking` table itself. Establishes naming convention for future domain table groups.

## DEC-007 — SELECT ... FOR UPDATE for overlap prevention (2026-02-16)
**Source**: `handoffs/server/2026-02-16-bookings-build.md`
Double-booking is prevented by `SELECT ... FOR UPDATE` inside a transaction, serializing concurrent writes to the same resource/time range. V1 treats any overlap as rejection; capacity-based counting deferred.

## DEC-008 — All DATETIME stored as UTC (2026-02-16)
**Source**: `handoffs/server/2026-02-16-bookings-build.md`
All DATETIME columns store UTC values. API layer handles timezone conversion for display. Cross-crate convention — all surfaces and SDKs must send/receive UTC.

## DEC-009 — Shared types crate named `api-contract` (2026-02-17)
**Source**: `handoffs/cross-cutting/2026-02-17-build-system-reorg.md`
*Superseded by DEC-012.*
The shared types crate is named `api-contract`, not `api-types`. By Phase 2 the crate holds both DTOs and OpenAPI path specs — "contract" accurately describes its purpose and aligns with project-schema.json vocabulary.

## DEC-010 — `api-contract` lives at monorepo root as standalone crate (2026-02-17)
**Source**: `handoffs/cross-cutting/2026-02-17-build-system-reorg.md`
*Superseded by DEC-012.*
`api-contract` has zero server dependencies and is consumed by server, sdk-rust, and sdk-ts. Placing it inside the server workspace would force cross-workspace reach from SDKs. Standalone crate with path deps is cleaner.

## DEC-011 — Committed `dist/openapi.json` as bootstrap artifact (2026-02-17)
**Source**: `handoffs/cross-cutting/2026-02-17-build-system-reorg.md`
`dist/openapi.json` is committed (not gitignored) so that `include_str!` in the API crate works on clone-and-build without running the pipeline first. Pipeline overwrites on run; CI catches staleness.

## DEC-012 — `api-contracts` extracted to monorepo root (2026-02-18)
**Source**: `server/handoffs/api-types-migration.md`
Supersedes DEC-009 and DEC-010. The shared types crate was renamed from `api-types` to `api-contracts` and moved from `server/api-types/` to the monorepo root at `api-contracts/`. Zero server/actix dependencies (only serde, utoipa, chrono). Standalone crate consumed by server workspace crates via path deps. SDKs will consume it directly when they become real — until then, YAGNI keeps it simple.

## DEC-013 — Workflow contract types live in api-contracts (2026-02-18)
**Source**: `handoffs/crosscutting/2026-02-18-workflow-engine-slice-4.md`
api-contracts is the contract boundary for workflow domain types, not just session/secret/extraction types. `ContextValue`, `ContextValueType`, `AdvanceResult`, `InstanceStatus`, request bodies (`EpochBody`, `UpdateContextBody`, `SetPositionBody`, `SplitBody`, `CancelBody`), and `WorkflowInstanceDto` all live in api-contracts. Server re-exports them. Engine-internal types (`StepDefinition`, `ContextFieldDef`) remain server-only until CLI/SDK consumers need them.

## DEC-014 — api-contracts types return Option, not Result (2026-02-18)
**Source**: `handoffs/crosscutting/2026-02-18-workflow-engine-slice-4.md`
api-contracts has zero server dependencies. Functions like `InstanceStatus::from_u8()` return `Option<Self>` instead of `Result<_, WorkflowError>` because `WorkflowError` lives in the server. Call sites in the server use `.ok_or(WorkflowError::...)` to convert. Convention: all fallible api-contracts functions use `Option`, never server error types.

## DEC-015 — Workflow engine is pure: no DB, no side effects (2026-02-18)
**Source**: `handoffs/crosscutting/2026-02-18-workflow-engine-slice-1.md`
`WorkflowEngine` is a zero-sized struct with pure functions: `(definition, instance, now) → (AdvanceResult, Mutation)`. No database access, no IO, no side effects. A separate service layer wraps engine calls with DB reads/writes. This boundary enables offline use (CLI simulation), deterministic testing, and future extraction to a shared crate.

## DEC-016 — Executor generic pattern for DB method deduplication (2026-02-18)
**Source**: `handoffs/crosscutting/2026-02-18-workflow-engine-slice-3.md`
DB types should use a shared inner function generic over `sqlx::Executor` instead of duplicating `foo()` + `foo_as_transaction()` methods. One copy of the logic, half the bug surface for column additions. Workflow instance pioneered this pattern; existing types (`secret.rs`, `person.rs`, `email_verification.rs`) can be migrated opportunistically. New types should follow this pattern.

## DEC-017 — Actor identity comes from auth context, not request body (2026-02-19)
**Source**: `handoffs/crosscutting/2026-02-19-cleanup-cancel-reason-jsonconfig.md`
`actor` in `CancelBody` and `created_by` in `CreateInstanceBody` must come from the authenticated user context, not the request body. Prevents identity spoofing. Delegation (who's assigned to a booking) is a database concept, not an API impersonation mechanism — no `on_behalf_of` field needed. This is a contract change affecting api-contracts request bodies; do it before more endpoints copy the pattern.

## DEC-018 — Definition contract types extracted to api-contracts (2026-02-19)
**Source**: Workflow engine slice 5
Definition-side types (`DefinitionStatus`, `ContextFieldDef`, `StepDefinition`, `StepType`, `AutoConfig`, `ContextSchema`) plus request bodies (`CreateWorkflowBody`, `UpdateWorkflowBody`, `CreateInstanceBody`) and response DTO (`WorkflowDefinitionDto`) extracted to api-contracts. Extends DEC-013 scope. Engine-internal types (`ComparisonOp`, `Operand`, `ConditionAst`) tagged along because step types embed them as `#[serde(skip)]` fields — extracting them avoids engine refactoring. These 3 types have no `ToSchema`, no wire visibility. Server re-exports all types; existing tests compile unchanged against re-exported types.

## DEC-019 — Person records are always created at booking time (2026-02-19)
**Source**: `handoffs/server/2026-02-19-open-questions-person-foundation-timezone-dedup.md`
`POST /bookings` calls `Person::find_or_create(email, ...)` before inserting the booking. `person_id` is required on `NewBooking` and enforced at the application layer; the DB column remains nullable to accommodate historical rows created before person-linking was introduced. The person table was empty when this change landed — no backfill needed. All rows going forward will have a `person_id`.

## DEC-020 — Timezone offset is env-only, not DB-persisted (2026-02-19)
**Source**: `handoffs/server/2026-02-19-open-questions-person-foundation-timezone-dedup.md`
Server timezone is configured via `TIMEZONE_OFFSET` in `.env` as a signed `i32` in minutes (e.g. `-300` = UTC-5). It is read into `Env::utc_offset_minutes` at startup with a range assertion (`[-840, 840]`) and flows into `Settings`. Not stored in `system_settings`. Changing timezone requires a server restart. If multi-timezone or per-location support is ever needed this decision must be revisited.

## DEC-021 — Booking confirmation email is fire-and-forget (2026-02-19)
**Source**: `handoffs/server/2026-02-19-open-questions-person-foundation-timezone-dedup.md`
The confirmation email is spawned via `actix_web::rt::spawn` after the booking row is committed. Email failure never fails the `201` response. Errors are written to `PostmarkLog` and `eprintln!`. This is the V1 position — acceptable at low traffic. Must be revisited before high load: options are a background email queue or accepting the inline latency.

## DEC-022 — All migrations live in server/migrations/ (2026-02-19)
**Source**: `handoffs/crosscutting/2026-02-19-seed-lookup-tables.md`
All SQL migrations (schema and seed data) live in `server/migrations/`. The initial 80-table schema was moved from `monorepo/migrations/` to consolidate. `cargo xtask db-reset` resolves `server/migrations/` via `workspace_dir()` — a separate `monorepo/migrations/` directory is invisible to it. New migrations always go in `server/migrations/`.

## DEC-023 — Lookup table seeds are migrations with values matching Rust enum discriminants (2026-02-19)
**Source**: `handoffs/crosscutting/2026-02-19-seed-lookup-tables.md`
Lookup tables with Rust enum counterparts (`booking_status`, `campaign_status`, `user_type`, `user_account_status`, `shop_status`, `server_mode`, `email`) are seeded via SQL migration with explicit IDs matching `repr(u8)`/`repr(u64)` discriminants. Comments in the migration reference the Rust source file. Tables without a Rust enum are left empty for population via Workbench. Adding a new enum variant requires a corresponding seed migration.

## DEC-024 — Role-based auth sufficient for internal phase; entity-level deferred (2026-02-19)
**Source**: `handoffs/crosscutting/2026-02-19-workflow-auth-audit.md`
Workflow endpoints use role-based authorization only (SysAdmin for mutations, Editor for reads/instance ops). No entity-level checks exist — any Editor can operate on any instance. This is acceptable while all users are internal staff. Entity-level auth (parent entity → organization resolution) is required before public launch but blocked on org tables, membership infrastructure, and entity resolvers that don't exist yet. Flag for pre-launch hardening.

## DEC-025 — CLI tools reject HTTP for non-localhost targets (2026-02-19)
**Source**: `handoffs/cli-tako/2026-02-19-vuln002-url-validation.md`
CLI tools that handle secrets or credentials must reject HTTP connections to non-localhost targets. No `--insecure` override flag — for a secrets manager there is no legitimate use case for plaintext HTTP to a remote host. Localhost (`127.0.0.1`, `localhost`, `::1`) is exempt for development. HTTPS is always allowed. Convention applies to all `cli-{name}` crates.

## DEC-026 — Booking resource contract types in api-contracts (2026-02-19)
**Source**: `handoffs/crosscutting/2026-02-19-booking-resource-crud.md`
`ShopStatus`, `CreateResourceBody`, `UpdateResourceBody`, and `ResourceDto` added to `api-contracts/src/bookings.rs`. `ResourceDto` derives both `Serialize` and `Deserialize` (SDK-ready). Three OpenAPI path stubs registered for GET/POST/PATCH `/v1/booking-resources`. Extends the booking contract surface in api-contracts — SDKs consume these types directly.

## DEC-027 — Per-field PATCH updates accepted despite COALESCE style guide (2026-02-19)
**Source**: `handoffs/crosscutting/2026-02-19-booking-resource-crud.md`
The style guide (`docs/RUST_STYLE_GUIDE.md`) prescribes single COALESCE UPDATEs for PATCH endpoints. No handler in the codebase follows this — both `users_patch.rs` and `resources_patch.rs` use individual UPDATE queries per field. The style guide is arguably more correct (atomicity), but the current pattern is acceptable at V1 scale. Style guide left as-is as the aspirational target. Future PATCH handlers may use either pattern; refactor to COALESCE is not urgent.

## DEC-028 — CLI display uses wire strings, not Debug format (2026-02-20)
**Source**: `handoffs/cli-tako/2026-02-20-user-commands.md`
`print_user` and future `print_*` helpers in CLI tools use API wire strings (matching serde serialization output, e.g. `"standard"`, `"disabled"`), not Rust `Debug` format. Output copy-pastes directly back into CLI flags. Convention applies to all `cli-{name}` crates.

## DEC-029 — sdk-rust re-exports domain types for CLI consumers (2026-02-20)
**Source**: `handoffs/cli-tako/2026-02-20-user-commands.md`
Types required to call SDK methods (request enums, DTOs like `UserDto`, `UserStatus`, `UserType`) are re-exported from `sdk-rust::types` so CLI crates depend only on `sdk-rust`, not directly on `api-contracts`. Keeps the dependency graph clean: api-contracts → sdk-rust → cli-{name}.

## DEC-030 — Double-entry password prompt for all CLI password inputs (2026-02-20)
**Source**: `handoffs/cli-tako/2026-02-20-user-commands.md`
All `cli-{name}` commands that accept a new password prompt twice (hidden input, zeroized on drop) before submission. No single-entry shortcut. Convention applies to `user create` and any future password-setting commands across CLI tools.

## DEC-031 — Suppression tables renamed for naming consistency (2026-02-20)
`email_bounce_status` → `suppression_status`, `email_bounce_list` → `suppression_list`. Aligns DB naming with Rust types (`SuppressionStatus`, `SuppressedEmail`) and Postmark domain terminology. "Suppression" is the accurate umbrella term — the status covers bounces, spam complaints, manual blocks, and unsubscribes. Migration-only change; no Rust type renames needed.

## DEC-032 — Product table holds common columns; subtables dropped (2026-02-20)
**Source**: Shop/product catalog planning session
Expand `product` with name, description, price_cents, status_id, timestamps. Drop `digital_product` and `physical_product` — no FK references, no Rust types, no useful columns. The `product` table now serves all product types (add-ons, gift cards, merchandise) with `product_type_id` as discriminator.

## DEC-033 — ProductType enum: Addon=0, GiftCard=1, Merchandise=2 (2026-02-20)
**Source**: Shop/product catalog planning session
0-based enum-backed lookup (DEC-023 convention). `product_type` table modified to remove AUTO_INCREMENT (MySQL treats `INSERT id=0` with AUTO_INCREMENT as "generate next"). Addon = booking checkout items. GiftCard = gift certificates. Merchandise = future retail.

## DEC-034 — Category is a shared data table, not an enum (2026-02-20)
**Source**: Shop/product catalog planning session
Seeded with 8 business categories (Paintball, Parties, GellyBall, Corporate, Axe Throwing, Equipment, Paint & Ammo, Gift Cards). IDs start at 1 (MySQL AUTO_INCREMENT, content-managed data table, not enum-backed). No Rust `Category` enum — categories are managed via Workbench.

## DEC-035 — Booking add-ons use a join table, not cart (2026-02-20)
**Source**: Shop/product catalog planning session
`booking_addon` links `booking` → `product` with quantity + unit_price_cents (snapshot per DEC-002). Add-ons attach during/after booking creation, not via cart. ON DELETE CASCADE on booking_id — bookings are never deleted (cancelled via status), CASCADE is GDPR safety net.

## DEC-036 — Cart tables dropped; redesigned in Phase 2 (2026-02-20)
**Source**: Shop/product catalog planning session
`cart_items` has confirmed FK bug (references `category` instead of `product`). `cart_session` has no user linkage. Both dropped. Cart will be redesigned in Phase 2 with person linkage, expiry, and proper FK relationships.

## DEC-037 — Shop table dropped; single-tenant assumption (2026-02-20)
**Source**: Shop/product catalog planning session
`shop` implies multi-tenant infrastructure that doesn't exist. Product status lives on `product.status_id`. Dropped with no replacement needed.

## DEC-038 — Shop system ships in three phases (2026-02-20)
**Source**: Shop/product catalog planning session
Phase 1 (current): Products + booking add-ons — catalog CRUD, 7 API endpoints, price snapshot. Phase 2 (future): Cart, orders, payments — gift card generation/redemption, `order` + `order_item` + `payment_transaction` tables, redesigned cart with person linkage, Stripe/Square integration. Phase 3 (future): Cross-sell, upsell recommendations, discount codes, promotional pricing.

## DEC-039 — Master password bounds: 8 min, 12 recommended, 24 max; CLI-enforced (2026-02-20)
**Source**: `handoffs/cli-tako/2026-02-20-master-password-rotation.md`
Master password length is validated in the CLI only: 8 minimum (hard reject), 12 recommended (warning), 24 maximum (hard reject). The server accepts any string from an authenticated SysAdmin — the trust boundary is authentication, not input validation.

## DEC-040 — SecretController takes &self uniformly; &mut self retired (2026-02-20)
**Source**: `handoffs/cli-tako/2026-02-20-master-password-rotation.md`
All `SecretController` methods take `&self`, writing through the internal `RwLock`. The `&mut self` pattern is retired for this type. Enables sharing via `AppState` without outer mutability. `PoisonedMasterPassword` error variant covers the lock-poisoned edge case.

## DEC-041 — Client::send() and Client::send_empty() are canonical SDK method patterns (2026-02-20)
**Source**: `handoffs/cli-api-testing/2026-02-20-shop-workflow-sdk-body-matchers.md`
`Client::send<T>(req)` (auth + build + execute + deserialize `ApiSuccess<T>`) and `Client::send_empty(req)` (auth + build + execute + status check, returns `Result<()>`) replace the manual 5-line chain. All new SDK client methods must use one of these two helpers. Both are public API.

## DEC-042 — Secrets use name-based routing, not ID-based (2026-02-20)
**Source**: `handoffs/crosscutting/2026-02-20-secret-crud-name-routing.md`
Secret CRUD endpoints use `/{name}` path parameters instead of `/{id}`. Names are the natural identifier for secrets (operators think in names like `STRIPE_KEY`, not database IDs). SDK methods changed from `id: i64` to `name: &str`. CLI args changed accordingly.

## DEC-043 — Secret name format: [A-Za-z0-9_-]{1,64} (2026-02-20)
**Source**: `handoffs/crosscutting/2026-02-20-secret-crud-name-routing.md`
Secret names are validated on create and rename with `[A-Za-z0-9_-]{1,64}`. Returns 422 with `SecretNameInvalid` (error code 1009). Validation is server-side — all consumers get consistent enforcement.

## DEC-044 — env.d.ts module augmentation for SvelteKit PUBLIC_* vars (2026-02-20)
**Source**: `handoffs/surface-website/2026-02-20-type-errors-and-reactivity.md`
SvelteKit surfaces declare `PUBLIC_*` environment variables via `env.d.ts` module augmentation of `$env/static/public`. Provides type checking independent of `.env` file presence. Convention applies to all `surface-{name}` SvelteKit crates.

## DEC-045 — CLI --credentials flag for credential-only secret updates; no secrets in argv (2026-02-21)
**Source**: `handoffs/cli-tako/2026-02-21-patch-credentials-flag.md`
`tako secret patch --credentials` enables credential-only rotation via prompted input. Secrets are never passed as command-line arguments (visible in process lists, shell history). Convention applies to all `cli-{name}` crates that handle secrets.

## DEC-046 — Epoch guard: BIGINT column, None skips check (2026-02-20)
**Source**: `handoffs/server/2026-02-20-epoch-guard.md`
`booking.epoch` is `BIGINT NOT NULL DEFAULT 0`, matching `i64` in the `EpochBody` contract type. When `epoch: None` in a request body, the guard is skipped — backward-compatible opt-out for clients that don't need optimistic concurrency. Existing clients continue to work without modification.

## DEC-047 — Operating hours are local time; availability slots are UTC (2026-02-21)
**Source**: `handoffs/surface-website/2026-02-21-e2e-booking-timezone-fix.md`
Operating hours in `booking_operating_hours` are stored as local `NaiveTime` values (e.g., 10:00 = 10am local). The availability endpoint converts to UTC using `utc_offset_minutes` from env config (`UTC = local - offset`). The booking POST handler converts incoming UTC `start_at` back to local for validation (`local = UTC + offset`). Both directions are consistent. Convention: all API wire times are UTC; local time is internal to the server.

## DEC-048 — ORDER BY tiebreaker: append `id DESC` when ordering by non-unique columns (2026-02-21)
**Source**: `handoffs/server/2026-02-21-secrets-guard-workflow-fix.md`
MySQL `DATETIME` has only second-level precision. Any `ORDER BY` on a non-unique column (e.g. `created_at`) must include `id DESC` as a tiebreaker for deterministic ordering. Convention applies to all server queries. Audited and applied to `booking.by_email`, `booking.by_person_id`, and `instance.all()`.

## DEC-049 — Entity-level auth audit: existing implementation sufficient for launch (2026-02-21)
**Source**: Closes DEC-024
Audit of all endpoints confirms entity-level authorization is already handled for launch scope:
- **Portal (User role)**: `GET /portal/bookings` filters by `person_id` from AuthContext; `POST /portal/bookings/{uuid}/cancel` checks `booking.person_id == user.id()` and returns 404 on mismatch.
- **Staff (Editor+)**: Unrestricted by design — single-venue model, all staff can manage all entities.
- **Public (no auth)**: `GET /bookings/{uuid}`, `POST /bookings/{uuid}/addons`, `GET /bookings/{uuid}/addons` use v4 UUID as capability token (128-bit, unguessable). Deliberate design for guest checkout flows.
- **Workflow**: Editor+ only, no customer access.
No org tables, membership infrastructure, or entity resolvers needed for launch. Deferred items: `GET/PATCH /portal/me` (user self-service) and addon endpoint auth hardening tracked in `server/NEXT.md`.

## DEC-050 — Bearer tokens must never reach client JS; web surfaces use SSR-only loads (2026-02-21)
**Source**: SKILL.md/build-plan.md alignment review, red-teamed
Bearer tokens and authentication credentials must never be serialized to client-side JavaScript in any surface. Web surfaces (surface-website) enforce via `+page.server.ts` for all load functions — no universal loads (`+page.ts`, `+layout.ts`). Four independent constraints make this permanent: (1) HTTP-only cookie readable only server-side via `locals.token`, (2) SDK uses global `fetch` not SvelteKit's context-aware `fetch`, (3) `API_BASE_URL` is `$env/static/private` unavailable in browser, (4) keeping tokens server-side is simply better security. Desktop surfaces (surface-command-center) use `adapter-static` with `ssr = false` — server loads are physically impossible; auth enforced via Tauri secure storage and IPC. "SSR-everywhere" applies to SvelteKit load functions only — client-side reactivity, WebSocket connections, and `+server.ts` API endpoints are unaffected. Session metadata (username, role, expiry) returned from server loads is permitted. Portal CSR migration is cancelled, not deferred — SSR is the correct and intentional pattern. SKILL.md and SVELTE_STYLE_GUIDE.md corrected to match.

## DEC-051 — Addon POST stays public; UUID capability token is the auth gate (2026-02-21)
**Source**: PRE_LAUNCH.md addon auth review
Addon attachment (`POST /v1/bookings/{uuid}/addons`) remains public, consistent with DEC-049's capability-token audit. Addons are part of the guest checkout flow — requiring auth would break guest checkout (DEC-003). Existing protections: per-addon quantity cap (100), per-booking addon cap (20), price snapshot (DEC-002), transactional insert with FOR UPDATE (VULN-001). DELETE stays Editor+ (staff operation). Residual risk: IP rate limiting not yet implemented — tracked separately in PRE_LAUNCH.md.

## DEC-052 — Migrations are immutable once applied (2026-02-22)
**Source**: `handoffs/crosscutting/2026-02-22-fix-sqlx-migration-tracking.md`
SQL migrations must not be edited after being applied to any database. Post-apply edits cause checksum mismatches in `_sqlx_migrations`, breaking `sqlx migrate run`. If a migration's contents need correction after apply, create a new migration file with the fix. This was discovered when `seed_lookup_tables.sql` was modified post-apply to rebase `user_type` IDs, causing a checksum mismatch that required manual DB repair.

## DEC-053 — `.env` lives at monorepo root, not per-crate (2026-02-22)
**Source**: `handoffs/server/2026-02-22-integration-test-verification.md`
The `.env` file lives at the monorepo root (`uwz/.env`). The `dotenv` crate climbs the directory tree to find it, so per-crate or per-worktree `.env` files are unnecessary. Server, CLIs, and xtask all resolve from the same root file. Do not create `.env` files inside `server/` or other crate directories.

## DEC-054 — SDK portal methods use `{verb}Portal{Entity}` naming (2026-02-22)
**Source**: `handoffs/surface-website/2026-02-22-portal-profile-page.md`
SDK methods for portal endpoints follow the pattern `{verb}Portal{Entity}` — e.g. `getPortalProfile`, `updatePortalProfile`, `getPortalBookings`, `cancelPortalBooking`. Matches the convention established by existing portal methods. Generic names like `getProfile` are ambiguous (admin vs. portal context). Convention applies to both sdk-ts and sdk-rust.

## DEC-055 — Photo upload CLI is `cli-idropr` (2026-02-23)
**Source**: session decision (user confirmation)
Photo/album upload tooling lives in `cli-idropr`, following the `cli-{name}` naming convention. This is the upload step in the gallery pipeline: server albums CRUD → sdk-rust album types → **cli-idropr uploads** → sdk-ts album types → surface-website gallery. Already listed in Architecture.md.

## DEC-056 — ShopStatus renamed to EntityStatus (2026-02-23)
**Source**: `handoffs/server/2026-02-23-albums-crud.md`, crosscutting rename session
Contract change. `ShopStatus` renamed to `EntityStatus` across api-contracts, server, sdk-rust, sdk-ts, and cli-api-testing. The enum was originally for shop products but became the shared active/inactive status for 4 domains (booking resources, booking products, shop products, albums/photos). DB table `shop_status` and `status_id` FK columns are unchanged — the rename is code-only. Migration immutability (DEC-052) prevents renaming the DB table.

## DEC-057 — Exclusively-owned child tables use ON DELETE CASCADE (2026-02-23)
**Source**: `handoffs/server/2026-02-23-albums-crud.md`
Tables that exclusively own their children use `ON DELETE CASCADE` on the child FK. `photo.album_id` → `album(id)` CASCADE, matching the `booking_addon.booking_id` → `booking(id)` pattern (DEC-035). In practice these parent rows are never deleted (soft delete via status), so CASCADE is a GDPR safety net, not an operational path. Convention for new parent-child relationships where the child has no independent existence.

## DEC-058 — Data entities use status deactivation, not DELETE endpoints (2026-02-23)
**Source**: `handoffs/server/2026-02-23-albums-crud.md`
Entities with business history (bookings, resources, shop products, albums, photos) are deactivated via `PATCH status=inactive`, never deleted. No DELETE endpoints exist for these types. This preserves referential integrity, audit trails, and historical data. Only transient or join-table records (booking addons, sessions) expose DELETE. Convention for all future data entity types.

## DEC-059 — Album error codes 1060–1066 (2026-02-23)
**Source**: `handoffs/server/2026-02-23-albums-crud.md`
Album/photo API errors allocated range 1060–1066, continuing the 10xx convention after shop products (1050–1059). Error code ranges: secrets 1000–1022, bookings 1024–1038, resources 1040–1045, shop 1050–1059, albums 1060–1066, workflows 2000–2014, users 3000–3004. New domains should allocate the next available block.

## DEC-060 — Tauri invoke args use camelCase keys (2026-02-23)
**Source**: `handoffs/surface-command-center/2026-02-23-checkin-integration-test.md`
Tauri's `invoke()` bridge applies `serde(rename_all = "camelCase")` by default on the Rust command side. JavaScript callers must use camelCase keys in the args object, not snake_case. This is a Tauri framework convention, not a project choice — but it's a recurring source of silent failures (arg appears as `undefined` on the Rust side). Convention applies to all `surface-{name}` Tauri crates.

## DEC-061 — Blake3 file hashing for uploads, stored as VARCHAR(64) nullable (2026-02-23)
**Source**: `handoffs/cli-idropr/2026-02-23-pre-handoff-fixes.md`
Blake3 is the file hashing algorithm for all file uploads (photos, extractions). Hash is hex-encoded (64 chars) and stored as `VARCHAR(64) NULL`. Nullable because metadata-only creates and pre-existing rows have no file. `Photo::create_from_upload()` requires `file_hash: &str` at compile time — any future upload path gets a compile-time reminder to hash. Consistency with extraction uploads was the driver; no alternative algorithms were evaluated.

## DEC-062 — Svelte 5 controlled inputs: $state + bind:value (2026-02-24)
**Source**: `handoffs/surface-website/2026-02-24-login-fix-gallery-share.md`
In Svelte 5, `<input value={prop}>` makes the browser's constraint validation see the prop value, not user input — `required` silently blocks submission with no tooltip. All form components must use `let val = $state(value)` with `bind:value={val}` instead of passing `value` as a read-only prop. No `$effect` sync is needed when `use:enhance` keeps the component mounted.

## DEC-063 — CSP connect-src includes dynamic API origin (2026-02-24)
**Source**: `handoffs/surface-website/2026-02-24-login-fix-gallery-share.md`
`hooks.server.ts` must dynamically append the `API_BASE_URL` origin to the CSP `connect-src` directive. In dev, API calls are same-origin and work without it; in staging/prod where `API_BASE_URL` points to a different domain (e.g. `data.domain.com`), missing `connect-src` silently kills fetch calls with no user-visible error. The origin is derived from the env var at request time, not hardcoded.

## DEC-064 — route-map.json / command-center.json scope split (2026-02-24)
**Source**: `handoffs/surface-command-center/2026-02-23-command-center-skill` conflict analysis
`route-map.json` and `command-center.json` had contradicting entity models for service fulfillment. route-map defined a 6-state `service_fulfillment` machine on a `service_status` table; command-center.json superseded it with an 8-state machine on `check_in_group`. Resolution: scope split. `route-map.json` owns routes, endpoints, data models, navigation, and booking/queue/order lifecycle state machines. `command-center.json` owns the check-in group entity, 8-state service machine, split mechanics, and `actions_by_role` operational model. Superseded sections in route-map.json replaced with pointer comments. All `service_status` references updated to `check_in_group`. `/api/service` renamed to `/api/groups`. No production code referenced `service_status` — purely spec-level reconciliation.

## DEC-065 — Command center: shell owns bottom zone, domain owns header + panels (2026-02-24)
**Source**: `handoffs/surface-command-center/2026-02-24-shell-layout.md`
In the command center, `(app)/+layout.svelte` renders the bottom nav buttons and gauges (shell chrome). Domain layouts render titles and breadcrumbs. Page components compose the content grid. This separation means adding a new domain (e.g. queue management) requires only `(app)/queue/+layout.svelte` + `+page.svelte` — the shell chrome comes free from the parent layout.

## DEC-066 — Search controls at page level, list components are results-only (2026-02-24)
**Source**: `handoffs/surface-command-center/2026-02-24-shell-layout.md`
BookingList is a pure results table; BookingSearch is composed at the page level alongside the title. This pattern applies to all future list views (queues, albums, orders). Rationale: search controls are page-level concerns (URL params, layout position), not list-component internals. Keeps list components reusable and testable.

## DEC-067 — Custom dropdowns over native `<select>` in Tauri surfaces (2026-02-24)
**Source**: `handoffs/surface-command-center/2026-02-24-shell-layout.md`
Native `<option>` elements cannot be reliably styled in dark webview UIs. All selectors in Tauri surfaces use the button+panel pattern (click-outside + positioned div), same as DatePicker. This is a technical constraint of the webview runtime, not a stylistic preference.

## DEC-068 — docs/structured-data/ directory for shared reference data (2026-02-24)
**Source**: `handoffs/crosscutting/2026-02-24-structured-data-seo-skill-review.md`
`docs/structured-data/` is the convention for shared, non-branch-specific reference data files (business identity, location, etc.). First candidate: `business-identity.json` when ai-discoverability init runs. These files are consumed by skills and build tools, not by runtime code.

## DEC-069 — Day-lock is client-side only; server guards ship independently (2026-02-24)
**Source**: `handoffs/surface-command-center/2026-02-24-day-lock.md`
Day-lock in the command center is a UI guardrail preventing accidental edits to past days. It is not a security boundary. Server-side mutation guards for temporal constraints ship independently as defense-in-depth. Surfaces must not rely on client-side locks as the sole enforcement mechanism.

## DEC-070 — Queue is public (unauthenticated), not portal-gated (2026-02-25)
**Source**: `handoffs/surface-website/2026-02-25-portal-ux-review.md`
Queue visibility is a public route at `(public)/queue/`, accessible without authentication. This contradicts `route-map.json` which listed queue as staff-facing (`min_role: operator`). Route map must be updated. Anonymous visitors can view queue status.

## DEC-071 — Surveys removed from customer portal; command-center only (2026-02-25)
**Source**: `handoffs/surface-website/2026-02-25-portal-ux-review.md`
Surveys are a staff tool, not a customer-facing feature. Removed from portal nav and routes (`portal/surveys/` deleted). Survey creation, distribution, and analysis live exclusively in the command center surface.

## DEC-072 — Status indicators use 4-state visual model, not per-domain palettes (2026-02-25)
**Source**: Command center design system review
Status indicators across all command center surfaces use a 4-state model: **green** (gated action passed — confirmed, completed, published, active, complete), **yellow** (needs attention — pending, paused, partial, draft), **red** (undone/time-sensitive/bad — cancelled, no_show, expired), **unlit** (neutral terminal/inactive — completed booking, split, archived, inactive). Replaces per-component rainbow palettes with an operational control-panel pattern. All mappings live in `surface-command-center/src/lib/utils/statusColor.ts` — changing any color is a one-line diff. Applies to BookingStatus, InstanceStatus, DefinitionStatus, WaiverCollectionStatus, and EntityStatus.

## DEC-073 — Queue entries use hard DELETE; ephemeral entity exception to DEC-058 (2026-02-25)
**Source**: `handoffs/server/2026-02-25-queue-entry-entity-api.md`
Queue entries are ephemeral daily records, not long-lived entities with referential dependents. `DELETE /v1/queue/{id}` physically removes the row. The `complete` status handles normal lifecycle termination. This intentionally departs from DEC-058 (status deactivation, no DELETE). The exception applies only to entities with no referential dependents and no business history value beyond the current operating day. If the pattern spreads to other entity types, revisit whether a formal "ephemeral entity" classification is needed.

## DEC-074 — Dynamic WHERE clause building for multi-filter list queries (2026-02-25)
**Source**: `handoffs/server/2026-02-25-queue-entry-entity-api.md`
Queue entry `by_date()` uses `push_str` + conditional `bind()` to build WHERE clauses with 2+ optional filters. This replaces the booking-era pattern of separate full SQL strings per filter combination (which scales as 2^N). Bind order must match push order — documented at the call site. New list queries with multiple optional filters should follow this pattern. Existing single-filter queries (bookings) don't need migration.

## DEC-075 — Error code range 5000–5007 for queue entry API (2026-02-25)
**Source**: `handoffs/server/2026-02-25-queue-entry-entity-api.md`
Queue entry errors allocated range 5000–5007. Updated allocation map: secrets 1000–1022, bookings 1024–1038, resources 1040–1045, shop 1050–1059, albums 1060–1066, workflows 2000–2014, users 3000–3004, waivers 4000–4009, queue 5000–5007. New domains should allocate the next available block.

## DEC-076 — PostHog is the sole analytics service; reverse proxy at /ingest/ (2026-02-25)
**Source**: `handoffs/surface-website/2026-02-25-posthog-only-analytics.md`
GA4 and Facebook Pixel removed (dead code, never mounted). PostHog is the only analytics service across all web surfaces. Client JS configured with `api_host: '/ingest'` — a SvelteKit server route at `/ingest/[...path]/+server.ts` proxies all PostHog requests to `us.i.posthog.com`, defeating ad blockers. Session replay enabled with `maskAllInputs: true`. CSP trimmed to match (removed GA/FB script-src entries). Convention: no analytics JS loads from third-party domains; all analytics traffic routes through the reverse proxy.

## DEC-077 — Waivers = 7 fills the lower-u64 Resource bitmask boundary (2026-02-26)
**Source**: `handoffs/server/2026-02-26-waivers-resource.md`
`Resource::Waivers = 7` occupies the 8th and final slot in the lower u64 of the permission bitmask. The next resource variant added will spill into the upper u64. The upper/lower split and u128 backing handle this correctly — no code changes needed — but the `create_upper_mask` test assertion will need updating when a 9th resource is added.

## DEC-078 — 422 is the default HTTP status for unmapped client-facing errors (2026-02-26)
**Source**: `handoffs/server/2026-02-26-error-to-http-migration.md`
Validation and business-logic errors that don't fit a specific HTTP status category (404, 409, 400, 413, etc.) get 422 Unprocessable Entity via the `_ =>` fallback in `http_status()`. New client-facing error variants automatically receive a reasonable status without touching `http_status()`. Variants that need a different status get an explicit match arm.

## DEC-079 — WaiverStaffPasswordInvalid is 401, not 422 (2026-02-26)
**Source**: `handoffs/server/2026-02-26-http-status-guardrail-tests.md`
Reclassified from the wildcard 422 fallback to explicit 401 (unauthorized). A failed password check is an authentication event, not a validation error. Security review caught this during guardrail test expansion.

## DEC-080 — parse_guardian_relationship stays as module fn, not FromStr on api-contracts (2026-02-26)
**Source**: `handoffs/server/2026-02-26-guardian-parsing-dedup.md`
Kept `parse_guardian_relationship` as a module-level `fn` in the server crate rather than implementing `FromStr` on `GuardianRelationship` in api-contracts. Avoids a contract crate change and keeps domain error semantics (`Error::WaiverGuardianRelationshipInvalid`) without a mapping layer.

## DEC-081 — Additive Serialize/Deserialize derives in api-contracts are contract-safe (2026-02-26)
**Source**: `handoffs/sdk-rust/2026-02-26-queue-client.md`
Adding `Serialize` to request body types and `Deserialize` to DTO types in api-contracts is an additive derive change with no wire format impact. Every SDK-consumed type already has both. This is a standing convention — future SDK work can add missing derives without treating them as contract changes.

## DEC-082 — Command center interactive primitives: focus-visible, transition-colors, tokens in CSS (2026-02-26)
**Source**: `handoffs/surface-command-center/2026-02-26-primitive-extraction.md`
Three conventions for command center primitives: (1) `focus-visible:ring` not `focus:ring` — desktop Tauri app, no mouse-click flash. (2) `transition-colors`/`transition-transform` not bare `transition` — functional-only motion. (3) Design token *values* belong in CSS `@theme`, not TypeScript — components pass typed props, `@theme` owns the palette.

## DEC-083 — Indicator palette is 5 colors: green, yellow, red, unlit, indigo (2026-02-26)
**Source**: `handoffs/surface-command-center/2026-02-26-theme-statusbadge-refactor.md`
Extends DEC-072's 4-state model with a 5th color: indigo, solely for `online_call_ahead` priority tier. Adding more semantic colors requires updating both the `Indicator` union type and the `@theme` block together.

## DEC-084 — Website color tokens: hex sRGB, OKLCH deferred, glass effects excluded (2026-02-26)
**Source**: `handoffs/surface-website/2026-02-26-color-token-foundation.md`
Hex sRGB values are acceptable for token definitions. OKLCH migration deferred until there's a perceptible reason. Glass effects, per-component shadows, form fields, and body gradient are intentionally excluded from the token system — they are intentional variation, not accidental duplication.

## DEC-085 — Waiver signing: typed name for v1, single form with minor toggle (2026-02-26)
**Source**: `handoffs/surface-website/2026-02-26-waiver-signing-form.md`
`signature_data` is the participant's typed full legal name. No canvas/SVG pad for v1 — legally standard for online waivers; canvas is a future enhancement. Single form with a checkbox that reveals DOB + guardian fields conditionally, rather than separate adult/child forms.

## DEC-086 — npm test is a functional gate for sdk-ts (2026-02-26)
**Source**: `handoffs/crosscutting/2026-02-26-sdk-ts-test-bootstrap.md`
vitest bootstrapped with coverage of all 5 `request()` branches. `cd sdk-ts && npm test` is now a functional build gate alongside the existing Rust gates. Should be added to CI when CI is configured.

## DEC-087 — Intent token name: `--color-intent-primary`, not `intent-action` (2026-02-27)
**Source**: `handoffs/surface-website/2026-02-26-intent-token-adoption.md`
`--color-intent-primary` is the settled name for the amber attention token. "Primary" means "the primary thing to pay attention to" — covers both interactive elements (CTAs, links) and decorative elements (eyebrows, accent lines, star ratings, scroll indicators). `intent-action` was rejected as semantically incorrect for decorative uses. All homepage files now consume this token; new components should use it instead of hardcoded `#f59e0b`.

## DEC-088 — Alpha variants via `color-mix()`, not raw `rgba()` (2026-02-27)
**Source**: `handoffs/surface-website/2026-02-26-intent-token-adoption.md`
`color-mix(in srgb, var(--token) N%, transparent)` is the convention for deriving alpha-variant border/glow values from design tokens. Keeps the base color tied to the token so palette changes propagate automatically. Don't reach for raw `rgba()` when a token covers the base color.

## DEC-089 — Hour-block boundary: floor-of-hour grouping for queue `expected_at` (2026-02-28)
**Source**: `handoffs/surface-command-center/2026-02-28-queue-expected-at-hour-blocks.md`
An `expected_at` value of `11:00` groups into the `11:00–12:00` block (floor of hour). Standard clock-hour grouping. This convention applies to any surface displaying queue data grouped by time.

## DEC-090 — SessionMeDto.role is Option<Role> — nullable for non-standard bitmasks (2026-03-06)
**Source**: `handoffs/server/2026-03-06-session-me-endpoint.md`
`SessionMeDto.role` is `Option<Role>`. If a user's permission bitmask doesn't exactly match a known role (e.g., custom permissions granted manually), the client receives `null` instead of a 500. This is a safety valve — `from_role()` is currently the only assignment path so it should always resolve, but the contract protects against future edge cases. Note: `to_role()` was later fixed to use superset matching (bitmask & role == role), so admin users with extra bits now resolve correctly.

## DEC-091 — pnpm is the JS package manager for all monorepo JS/TS projects (2026-03-06)
**Source**: `handoffs/server/2026-03-06-xtask-sdk-ts-codegen.md`
Root `pnpm-workspace.yaml` lists `sdk-ts`, `surface-command-center`, `surface-website`. No npm lockfiles should exist in workspace members. `cargo xtask build-all` invokes `pnpm run generate` for sdk-ts codegen.

## DEC-092 — Build tools assume prerequisites are installed (2026-03-06)
**Source**: `handoffs/server/2026-03-06-xtask-sdk-ts-codegen.md`
xtask and other build tools fail with a clear message rather than auto-installing dependencies. `pnpm install`, `cargo`, and `sqlx` are manual prerequisites. Keeps the build deterministic and avoids surprise network fetches.

## DEC-093 — Tauri surfaces: role stored in Svelte context, not per-nav IPC (2026-03-05)
**Source**: `handoffs/surface-command-center/2026-03-05-review-fixes-role-gating-gap.md`
Desktop surfaces fetch the user's role once via `getSessionMe()` IPC and store it in a Svelte context (`AuthContext`). Individual components access role via `getAuthContext()` — no per-component IPC calls. Security audit confirmed zero delta vs. per-call approach; context avoids latency and offline failure modes.

## DEC-094 — $app/state over $app/stores for Svelte 5 surfaces (2026-03-05)
**Source**: `handoffs/surface-command-center/2026-03-05-review-fixes-role-gating-gap.md`
All Svelte surfaces use `$app/state` (Svelte 5 runes-based API) instead of the legacy `$app/stores`. SvelteKit 2.12+ required. Applies to both web and Tauri surfaces.

## DEC-095 — Tauri auth context: synchronous init + async load (2026-03-05)
**Source**: `handoffs/surface-command-center/2026-03-05-role-gated-nav.md`
Svelte 5's `setContext` must be called synchronously during component init. Auth context is created empty during init via `createAuthContext()`, then populated via `auth.load(session)` inside `onMount`. Calling `setContext` inside an async callback triggers `lifecycle_outside_component`. This pattern applies to any Svelte 5 context that depends on async data.

## DEC-096 — Role rank model: linear hierarchy (2026-03-05)
**Source**: `handoffs/surface-command-center/2026-03-05-role-gated-nav.md`
`user(0) < editor(1) < sys_mod(2) < sys_admin(3)`. `hasRole(minRole)` checks `ROLE_RANK[userRole] >= ROLE_RANK[minRole]`. Matches server's `route-map.json` `min_role` convention. Used for nav visibility gating in Tauri surfaces and available for any surface that needs role-based UI filtering.

## DEC-097 — Role fetch failure is non-fatal in Tauri surfaces (2026-03-05)
**Source**: `handoffs/surface-command-center/2026-03-05-role-gated-nav.md`
If `getSessionMe()` fails (server unreachable, endpoint not deployed yet), the app loads with empty nav (role is undefined → `hasRole` returns false for all items). No redirect loop. Operators can still access routes directly by URL. This prevents version-skew between client and server from breaking the app entirely.

## DEC-098 — Native menu lifecycle is frontend-driven in Tauri (2026-03-07)
**Source**: `handoffs/surface-command-center/2026-03-07-signout-menu-gating.md`
`showAppMenu()` after auth resolves, `hideAppMenu()` on sign-out. Tauri setup starts with an empty menu. This avoids race conditions between menu rendering and auth state. `on_menu_event` is registered once in `setup()` and survives menu rebuilds.

## DEC-099 — Opaque success responses on public POST endpoints (2026-03-06)
**Source**: `handoffs/surface-website/2026-03-06-call-ahead-queue.md`
Public POST endpoints (e.g., `/v1/queue/call-ahead`) return the same success response regardless of whether the email exists, the record was created, or the record was updated. Prevents email enumeration. Applies to any future public endpoint that accepts user-identifying input.

## DEC-100 — Queue rate limiter shares addon config and SystemFlag gate (2026-03-07)
**Source**: `handoffs/server/2026-03-07-queue-hardening.md`
Queue endpoints (`/v1/queue/call-ahead`, `/v1/queue/confirm/{token}`) use the same rate limit config as the addon limiter (10 tokens/min/IP, 100 initial capacity, sharded). No dedicated SystemFlag — shares `load_rate_limiter_service` gate. Both queue endpoints share one limiter instance, so exhausting the bucket on submissions also blocks confirmations. If queue needs independent enable/disable control, add a dedicated flag later.

## DEC-101 — `to_role()` uses superset matching, not exact equality (2026-03-07)
**Source**: `handoffs/crosscutting/2026-03-07-to-role-superset-fix.md`
`to_role()` changed from exact bitmask equality (`self.mask == role.mask`) to superset matching (`self.mask & role.mask == role.mask`). This aligns display behavior with `has_permission()` — a user with admin+extra bits now correctly resolves to `SysAdmin` instead of returning `None`. Amends the safety note in DEC-090.

## DEC-102 — Date range filter params on workflow instance list (2026-03-07)
**Source**: `handoffs/crosscutting/2026-03-07-date-range-filter-instances.md`
`GET /v1/workflow-instances` accepts optional `created_after` and `created_before` query params (ISO 8601 datetime). Introduced `FilterParams` struct to replace positional args in the database query builder. Convention: list endpoints with temporal filtering should use this struct pattern.

## DEC-103 — 6-digit numeric code replaces URL token for queue confirmation (2026-03-06)
**Source**: `handoffs/surface-website/2026-03-06-confirmation-code-input.md`
Queue confirmation changed from clickable `{token}` URL path to a 6-digit numeric code entered manually. Contract: `POST /v1/queue/confirm` with `CallAheadConfirmBody { email, code }` replaces `POST /v1/queue/confirm/{token}`. Defeats email scanner prefetch (codes aren't URLs). Separate rate limit buckets for call-ahead vs. confirm (different threat profiles).

## DEC-104 — SEO title template: "%s | Urban War Zone Houston" (2026-03-07)
**Source**: `handoffs/surface-website/2026-03-07-seo-audit-and-plan.md`
`seo.json` `defaults.titleTemplate` is `"%s | Urban War Zone Houston"` — "Paintball" dropped from the suffix to keep rendered titles under 60 characters. Content pages provide `%s` as their unique page title.

## DEC-105 — Testing strategy: layers 1-3, no E2E until pre-launch (2026-03-08)
**Source**: `handoffs/surface-command-center/2026-03-08-testing-infrastructure.md`
Testing scope covers layers 1-3: utilities, SDK query construction, and viewmodel error contracts. Layer 4 (component rendering) deferred. No E2E until pre-launch. Vitest 4 for TypeScript, Rust unit tests for SDK. Test pattern: `vi.mock('$lib/api/commands')` + `flushPromises()` + assert reactive state.

## DEC-106 — Postmark MessageStream enum maps 1:1 to dashboard stream names (2026-03-08)
**Source**: `handoffs/surface-website/2026-03-08-postmark-streams-queue-cinematic.md`
`MessageStream` enum variants map directly to Postmark dashboard stream names (`events-marketing`, `sales`, `subscriptions`, `internal`). Stream is specified only via serde `rename` — no `Display` impl, no HTTP header override. Single source of truth for stream routing.

## DEC-107 — Dev mode loads DB settings identically to production (2026-03-08)
**Source**: `handoffs/surface-website/2026-03-08-postmark-streams-queue-cinematic.md`
`dev_state()` calls `.with_database_settings()` to load DB-driven feature flags (e.g., `postmark_email_service`) the same way `prod_state()` does. Without this, flags silently default to `Disabled` in dev, masking real behavior. Any new `SystemFlag` added to `system_settings` must work in both startup paths.

## DEC-108 — Waiver acceptance gate: Pending → Accepted lifecycle (2026-03-09)
**Source**: `handoffs/crosscutting/2026-03-09-waiver-acceptance-gate.md`
Online waivers start with status `Pending` (DB default 0). Only operator-accepted waivers (`Accepted`, status 1) count toward the workflow check-in gate. `sync_waiver_count` queries accepted waivers internally. Paper waivers auto-accept on creation. Batch acceptance via `POST /v1/bookings/{uuid}/waivers/accept` (SysMod permission). `WaiverDto` gains a `status` field; `WaiverNotPending` error (code 4011, HTTP 409) prevents double-acceptance. This is a cross-crate contract: server enforces, command center builds acceptance UI, portal can ignore status.

## DEC-109 — srcset over CSS background-image for responsive card photos (2026-03-09)
**Source**: `handoffs/surface-website/2026-03-09-mission-cards-mobile-srcset.md`
Card components serve responsive images via `<img srcset>` instead of CSS `background-image`. CardWrapper auto-detects the path: srcset when `imageSet()` output is provided, CSS background fallback otherwise. WebP variants generated at 400w/640w/800w by `scripts/generate-images.mjs`. Naming convention: `{name}-{width}w.webp`. CSS background path retained for unmigrated consumers.

## DEC-110 — Password length validation: 8 min, 72 max, enforced before bcrypt (2026-03-10)
**Source**: `handoffs/crosscutting/2026-03-10-server-security-hardening.md`
Server validates password length (8–72 characters) before hashing. The 72-byte ceiling is bcrypt's hard limit — bytes beyond 72 are silently truncated, so a 100-char password and its first-72-char prefix produce the same hash. All surfaces that collect passwords must enforce compatible limits. Server is the authority; client-side limits are UX hints only.

## DEC-111 — Error Display redaction for sensitive error variants (2026-03-10)
**Source**: `handoffs/crosscutting/2026-03-10-server-security-hardening.md`
The server error enum's `Display` impl redacts sensitive variants (`Sqlx`, `DatabaseError`, `IoError`, `DatabaseConnection`) to generic messages. This prevents SQL queries, connection strings, and file paths from leaking into HTTP responses or logs. Non-sensitive unit-type variants use `Debug` formatting. Full structured logging (tracing crate) is the eventual replacement for the remaining `_ => {self:?}` catch-all.

## DEC-112 — Session logout deletes DB row; GC sweeps expired sessions (2026-03-10)
**Source**: `handoffs/crosscutting/2026-03-10-server-security-hardening.md`
`POST /v1/auth/logout` deletes the session row from the database (not just the in-memory cache). The GC cycle sweeps expired DB rows each pass using a read lock for the scan phase. This ensures logout is durable across server restarts and that orphaned sessions are eventually cleaned up without holding a write lock during the scan.

## DEC-113 — epoch_check denies disabled users at 401 (2026-03-10)
**Source**: `handoffs/crosscutting/2026-03-10-server-security-hardening.md`
`epoch_check` (session refresh) uses `by_id_enabled` instead of `by_id_unchecked`. A user disabled after login is denied at the next epoch refresh with 401, not allowed to continue until their session expires naturally. Defense-in-depth: permission checks are the primary gate, but epoch refresh is the backstop that catches disabled accounts within one refresh cycle.

## DEC-114 — Epoch-based change detection replaces callback threading (2026-03-10)
**Source**: `handoffs/crosscutting/2026-03-10-epoch-change-detection.md`
Server maintains per-domain atomic epoch counters (`EpochDomain::Workflow | Queue`) bumped by `EpochBump` middleware on mutation scopes. Clients poll `GET /v1/epochs` with 1-5s jitter; refetch only when their domain epoch is stale. Replaces `onMutate` callback threading through 5+ component layers. Both SDKs (Rust, TypeScript) and Tauri commands wired. New domains require adding an `EpochDomain` variant and an `AppState` field.

## DEC-115 — Mutation::merge eliminates double-write advance+normalize (2026-03-10)
**Source**: `handoffs/crosscutting/2026-03-10-mutation-merge-epoch-fixes.md`
Workflow advance and normalize produce separate `Mutation` values via pure computation (no DB reads). `Mutation::merge(self, overlay)` combines them into a single DB write, eliminating the two-autocommit pattern that silently swallowed normalize failures. Applied to 6 callsites; `instances_split` retains its existing transaction for the parent+child multi-row write. Helper extraction rejected — Rust ownership makes it awkward; inline is clearer.

## DEC-116 — EpochGuard transactional CAS via SELECT FOR UPDATE (2026-03-10)
**Source**: `handoffs/crosscutting/2026-03-10-epoch-guard-atomic-cas.md`
All 8 non-split workflow mutation handlers use `EpochGuard::lock_for_update` inside a transaction instead of the old non-atomic check/increment pattern. Lock always acquired (even when `epoch: None`) — lock is serialization, epoch comparison is staleness. Increment failure rolls back the mutation. Latency budget: ~50-60ms lock hold time, acceptable at 2-3 concurrent operators. Client-side 412 resolution: re-fetch, compare against intent, surface only genuine conflicts.

## DEC-117 — All workflow mutation paths serialize through transactional CAS (2026-03-10)
**Source**: `handoffs/crosscutting/2026-03-10-checkin-service-transactional-cas.md`
All 3 `checkin_service.rs` helpers (`create_checkin_instance`, `sync_waiver_count`, `cancel_checkin_instances`) now use `EpochGuard::lock_for_update` + `increment_tx` inside transactions, closing the cross-domain epoch drift gap (Gap 3). Combined with DEC-116, every code path that mutates workflow instances for a booking — 9 API handlers, the background monitor, and 3 cross-domain helpers — serializes through the booking row lock. No remaining unguarded writers.

## DEC-118 — Structured logging via tracing replaces all eprintln/println (2026-03-11)
**Source**: `handoffs/crosscutting/2026-03-11-structured-logging-server-audit.md`
The server uses `tracing` + `tracing-subscriber` + `tracing-actix-web` for all diagnostic logging. Dev mode: compact human-readable output. Prod mode: JSON lines (consumable by log aggregators without configuration). Default filter: `info,sqlx=warn`, overridable via `RUST_LOG`. `TracingLogger` middleware generates `x-request-id` on every request. One `println!` retained in the `database` crate (startup connection message) to avoid adding tracing as a dependency there.

## DEC-119 — Share code returns full guest_name, no name parsing (2026-03-12)
**Source**: `handoffs/crosscutting/2026-03-12-booking-share-codes.md`
The share code resolve endpoint returns the full `guest_name` string as entered by the booker. No server-side parsing into first/last name — human-entered names are too varied (comma-separated, single names, cultural variations). Surfaces decide how to display or truncate. This avoids fragile `rsplit_once(' ')` logic in the API contract.

## DEC-120 — FK references to person.id use INT, not BIGINT (2026-03-12)
**Source**: `handoffs/crosscutting/2026-03-12-booking-share-codes.md`
MySQL FK constraints require exact type match. `person.id` is `INT`. All migrations referencing `person.id` as a foreign key must use `INT`, not `BIGINT`. The Rust side uses `i64` (`User::id()`) which reads `INT` fine — the mismatch concern is purely at the DDL level.

## DEC-121 — deny_unknown_fields requires server-first deploy ordering (2026-03-11)
**Source**: `handoffs/surface-website/2026-03-11-queue-time-selector.md`
Request body types annotated with `#[serde(deny_unknown_fields)]` create a deploy ordering constraint: server must deploy before surfaces when new fields are added to those types. If a surface sends a field the server doesn't yet recognize, the request returns 400. After both are deployed, they are decoupled — server restarts don't require surface redeployment.

## DEC-122 — 401 flows: SDK Unauthorized variant → Tauri event → frontend redirect (2026-03-11)
**Source**: `handoffs/surface-command-center/2026-03-11-401-session-redirect.md`
Three-layer 401 handling pattern: SDK maps HTTP 401 to a typed `SDKError::Unauthorized` variant. In Tauri surfaces, `map_sdk_err` emits an `auth:session-expired` event on Unauthorized. Frontend `+layout.svelte` listens and redirects to login. The SDK variant collapses all server 401 sub-causes (SessionNotFound, SessionExpired, UserAccountStatusNotEnabled) into one variant — sufficient for redirect but CLIs needing sub-cause discrimination would need the original message carried.

## DEC-123 — CI enforces fmt + clippy + tests on push/PR (2026-03-12)
**Source**: `handoffs/crosscutting/2026-03-12-ci-readiness-fmt-clippy-actions.md`
GitHub Actions CI runs two parallel jobs on push/PR to main/staging/dev: `check` (cargo fmt --check + clippy -D warnings for server + api-contracts) and `test` (MySQL 8.0 service container, migrations, full test suite). Codebase is `cargo clippy -D warnings` clean as of baseline commit. `.git-blame-ignore-revs` contains the formatting commit SHA.

## DEC-124 — Share code resolution requires authentication (2026-03-12)
**Source**: `handoffs/surface-website/2026-03-12-portal-consistency-waiver-nav.md`
`GET /v1/share-code/:code` is auth-gated. The `XXX-XXX` format has a small keyspace (~2.18B codes); making resolution public would expose guest names and booking times to enumeration. The auth step is a security gate, not UX friction. If marketing wants pre-login preview, a separate public endpoint with reduced fields would be needed.

## DEC-125 — guest_name returned unparsed; display is a frontend concern (2026-03-12)
**Source**: `handoffs/crosscutting/2026-03-12-booking-share-codes.md`
Server returns full `guest_name` without parsing into first/last components. Human-entered names are too varied (comma-separated, single names, cultural conventions) for reliable server-side splitting. Any truncation, masking, or formatting is a frontend decision.

## DEC-126 — Shared validators live in `api::validation` module (2026-03-12)
**Source**: `handoffs/crosscutting/2026-03-12-ci-readiness-cleanup.md`
`is_valid_email()` extracted to `crate::api::validation` as the single shared email validator. New handlers import from this module instead of defining inline copies. Convention: any reusable request-level validation logic belongs in `api::validation`, not duplicated per handler.

## DEC-127 — Unverified (4) separates registration lifecycle from admin-disabled (2026-03-13)
**Source**: `handoffs/crosscutting/2026-03-13-unverified-status-sweeper.md`
`UserAccountStatus::Unverified = 4` is a new variant in api-contracts, distinct from `Disabled = 0`. `Disabled` is now exclusively an admin action; `Unverified` is the initial state for self-registered accounts awaiting email verification. The sweeper deletes `Unverified` accounts after 24 hours. All surfaces rendering user status must handle the new variant. The admin PATCH endpoint rejects `Unverified` at handler level (not structurally) — sufficient until a third status-restricted operation appears.

## DEC-128 — Consumer-facing paths use uuid, staff paths use id (2026-03-14)
**Source**: `handoffs/crosscutting/2026-03-14-esign-phase2-record-access-audit.md`
Consumer-facing API paths (portal, public) use UUID path parameters for entity lookup; staff-gated paths (admin, SysMod) may use integer IDs. Sequential IDs on consumer paths create existence oracles (404 vs 403) and write amplification vectors on write-on-GET endpoints (e.g., audit-row insertion). `WaiverDto` exposes both `id` and `uuid` — surfaces pick the appropriate identifier for their audience. If a future consumer-facing endpoint accepts `id` in a path, the UUID indirection is defeated.

## DEC-129 — No string interpolation in SQL statements (2026-03-14)
**Source**: `handoffs/crosscutting/2026-03-14-waiver-document-retrieval-integrity.md`
SQL queries must use literal strings with bind parameters, never `format!()` or string interpolation for table names, column names, or values. Discovered via SEC-3 remediation: audit trail insertion used `format!("INSERT INTO {table}")` in a loop. Replaced with explicit per-table `sqlx::query()` calls. Even when the interpolated value is not user-controlled, the pattern is banned — it defeats static analysis and sets a precedent for injection vectors.

## DEC-130 — Post-sign document retrieval is operational, not an ESIGN validity gate (2026-03-14)
**Source**: `handoffs/crosscutting/2026-03-14-waiver-document-retrieval-integrity.md`
ESIGN §7001(c)(1)(A)(v) requires making records available and informing consumers how to access them — not that the consumer actually retrieves the record. The signature is legally valid at sign time. View audit logging on `GET /v1/portal/waivers/{uuid}` is operational practice for dispute support, not a compliance gate. Future design decisions should not treat retrieval as a validity prerequisite.

## DEC-131 — Waiver signing is a 4-step discrete flow, not a single transaction (2026-03-15)
**Source**: `handoffs/crosscutting/2026-03-15-waiver-audit-discrete-flow.md`
Online waiver creation follows a 4-step discrete flow: begin (collect info) → consent (checkbox) → confirm (review summary) → sign (capture signature). Each step has its own endpoint and captures timestamp, IP, and user agent independently. This replaces the prior single-shot `create_tx()` approach. The discrete steps produce a per-step audit trail that satisfies ESIGN evidentiary requirements without relying on a single composite record. Surfaces must implement a multi-step form matching this sequence — skipping or combining steps breaks the audit chain.

## DEC-132 — WaiverStatus enum: Draft=0, Pending=1, Accepted=2, Archived=3 (2026-03-15)
**Source**: `handoffs/crosscutting/2026-03-15-waiver-audit-discrete-flow.md`
`WaiverStatus` discriminants rebased to Draft=0/Pending=1/Accepted=2/Archived=3. Draft is the initial state created at `begin`; Pending is set at `sign` (awaiting staff acceptance); Accepted and Archived are staff-driven transitions. The old discriminant values are gone — all consumers (surfaces, SDK, staff tools) must use the new values. `CreateWaiverBody` and `CreateChildWaiverBody` types are removed from api-contracts; replaced by `BeginWaiverBody` and `SignWaiverBody`.

## DEC-133 — Waiver timestamps use Rust-side Utc::now(), never SQL NOW() (2026-03-15)
**Source**: `handoffs/crosscutting/2026-03-15-waiver-audit-discrete-flow.md`
All time-critical waiver operations pass `Utc::now()` as bind parameters rather than using MySQL `NOW()`. Server runs on Render, database on Google Cloud SQL — clock skew between them is real and observed. Using application-side timestamps ensures consistent ordering within a single request's audit trail. This convention applies to the waiver path specifically; extending it project-wide is a separate decision if needed.

## DEC-134 — Waiver gate advancement is always manual (2026-03-15)
**Source**: `archive/dispatches/DISPATCH_WAIVER_DESIGN_DECISIONS.md` (Decision 1)
Waiver records must be inspected by staff before advancing past a waiver gate. `sync_waiver_count()` updates context for display only — it never calls `normalize()`. This applies to all workflow instances (primary and split children alike). The production `ci_waivers` step is `type: "gate"` which was already manual-only; this decision formalizes the constraint and removes the normalize code path from the sync function. Auto-advance on waiver count was a design mistake — staff review is mandatory.

## DEC-135 — `*OutOfBounds` DB-corruption errors are internal-only, no client-facing mapping (2026-03-16)
**Source**: `handoffs/server/2026-03-16-booking-source-slice01.md`
`BookingSourceOutOfBounds` and all other `*OutOfBounds` enum variants represent DB data corruption (invalid discriminant stored). They have no `to_api_error_message()` mapping and surface as generic 500 errors. This is intentional — clients have no meaningful action for corrupted data. New `*OutOfBounds` variants follow this convention.

## DEC-136 — Queue activation does not create Person records (2026-03-17)
**Source**: `handoffs/server/2026-03-17-ghost-person-removal.md`
`Person::find_or_create` removed from queue activation. The guest owns the identity moment — it happens at waiver signing, not when staff enters queue data. Creating Person records from staff-entered data produced ghost contact stubs with no user account. Person resolution now occurs at enrichment time (waiver attach matches `guest_email` → sets `person_id`). `Person::find_or_create` remains correct in the online booking flow where authentication is required.

## DEC-137 — Parent waiver guard is booking-agnostic (2026-03-17)
**Source**: `handoffs/server/2026-03-17-ghost-person-removal.md`
`has_signed_adult_waiver(signer_user_id)` checks for ANY signed adult waiver (Pending or Accepted), not booking-scoped. `BeginChildWaiverBody` has no `booking_uuid` field and the handler has no booking context — adding booking scope would be a contract change. ESIGN goal (parent identity on file) is met without booking scope. Trade-off: returning parents pass the guard from a previous visit's waiver.

## DEC-138 — Pending waivers satisfy the parent waiver guard (2026-03-17)
**Source**: `handoffs/server/2026-03-17-ghost-person-removal.md`
Parent guard checks `waiver_status_id IN (1, 2)` (Pending, Accepted). Requiring staff-accepted status would create a blocking dependency — parents couldn't start child waivers until staff acts on theirs. This breaks the "fill out at home" flow where the family completes all waivers in one session.

## DEC-139 — ~5% enrichment gap accepted for queue entries without email (2026-03-17)
**Source**: `handoffs/server/2026-03-17-ghost-person-removal.md`
Staff-entered queue entries without email produce guest bookings (`person_id = NULL`, `guest_email = NULL`) with no enrichment path. These guests are physically present and interact through staff — portal visibility is not expected. Closable later via first-attach-wins fallback if needed. Operational flow unaffected.

## DEC-140 — Adopt `sqlx::QueryBuilder` for all dynamic SQL construction (2026-03-17)
**Source**: `handoffs/server/2026-03-17-querybuilder-migration.md`
All dynamic SQL sites must use `sqlx::QueryBuilder` instead of split `push_str`/`bind` patterns. The split pattern requires manual synchronization of clause ordering and bind ordering — a desync produces silent wrong-query or wrong-data bugs. Three sites identified: `QueueEntry::by_date()` (migrated), `WorkflowInstance::filtered()`, `WorkflowInstance::apply_mutation_into()`. `QueryBuilder` has been in the dependency tree since sqlx 0.6 (currently on 0.8.3).

## DEC-141 — Client IP via Railway `X-Real-IP`, not `X-Forwarded-For` (2026-03-18)
**Source**: `docs/DEV_AUDIT_RESULTS.md` (FINDING: Client IP Identification Is Broken)
Client IP identification uses Railway's `X-Real-IP` (public traffic, set by Railway's edge proxy, documented and authoritative) and BFF `X-Real-Client-IP` (private network, set by the SvelteKit BFF over Railway's WireGuard private network). `X-Forwarded-For` and Actix `ConnectionInfo::realip_remote_addr()` are banned — `X-Forwarded-For` is spoofable on platforms that append without stripping client-supplied values. Priority order: `X-Real-IP` first (always present on public requests via Railway's edge), `X-Real-Client-IP` second (only present on private-network BFF requests), `peer_addr` third (TCP socket address — local dev fallback, added 2026-03-20 via dispatch `DISPATCH_RATE_LIMIT.md`). Utility: `extract_client_ip()` in `api/validation.rs`, called by rate limit middleware and all 13 audit/rate-limit handler sites.

## DEC-142 — MySQL 8.4 as target database version (2026-03-19)
**Source**: `handoffs/server/2026-03-19-railway-deployment-infra.md`
CI, local Docker, and Cloud SQL all run MySQL 8.4. MySQL 8.0 EOL is April 2026. Tables with composite primary keys where another table's FK references a single column require an explicit `UNIQUE KEY` on the referenced column — MySQL 8.4 no longer infers uniqueness from the leftmost prefix of a composite PK. 8 tables were affected in the initial migration.

## DEC-143 — Per-service Dockerfiles for Railway deployment (2026-03-19)
**Source**: `handoffs/server/2026-03-19-railway-deployment-infra.md`
Auto-detection (Railpack/Nixpacks) cannot handle a mixed Rust+Node monorepo — both detect Node from `package.json`/`pnpm-workspace.yaml` at the root and ignore Rust. Each service gets its own Dockerfile (`server/Dockerfile`, `surface-website/Dockerfile`), referenced via `RAILWAY_DOCKERFILE_PATH` env var in the Railway UI. No root directory set on any service — build context is the full repo so cross-root dependencies (e.g., `api-contracts/` for the server) are accessible.

## DEC-144 — `PORT` replaces `SERVER_PORT`; `SHARDS` replaces `SERVER_THREADS` (2026-03-19)
**Source**: `handoffs/server/2026-03-19-railway-deployment-infra.md`
`PORT` is the standard Railway convention (Railway sets it automatically). `SHARDS` reflects actual usage — rate limiter and session controller sharding, not Actix worker threads. Production Actix workers auto-detect from CPU count; `SHARDS` controls internal data structure partitioning independently.

## DEC-145 — `DB_CERT` env var for hosted SSL (raw PEM) (2026-03-19)
**Source**: `handoffs/server/2026-03-19-railway-deployment-infra.md`
Priority: `DB_CERT` (raw PEM content, used on Railway where no filesystem cert access exists) > `DB_CERT_PATH` (file path, used in local dev) > no SSL (local Docker dev). Cloud SQL server CA cert is pasted directly into the env var including BEGIN/END markers.

## DEC-146 — `API_BASE_URL` uses `$env/dynamic/private` (2026-03-19)
**Source**: `handoffs/server/2026-03-19-railway-deployment-infra.md`
Switched from `$env/static/private` because the value differs per environment (local dev: `http://localhost:3000`, staging: `http://server.railway.internal:3000`, prod: same pattern with different service name). Read at runtime via `env.API_BASE_URL`, not baked into the SvelteKit build. `PUBLIC_*` vars remain static (baked at build time) since they're the same across environments.

## DEC-147 — Admin bootstrap via `uwz-server bootstrap` subcommand (2026-03-20)
**Source**: dev session, 2026-03-20
Initial admin user creation uses a `bootstrap` subcommand on the server binary, not manual SQL inserts or a seed migration. Reads `BOOTSTRAP_USERNAME`, `BOOTSTRAP_PASSWORD`, `BOOTSTRAP_EMAIL`, `BOOTSTRAP_FNAME` (required) and `BOOTSTRAP_LNAME` (optional) from env vars. Connects directly to the database — no HTTP server, no AppState. Idempotent: exits cleanly if a system user already exists. Hardcodes SysAdmin role (full permission bitmask). Runs locally against Cloud SQL, same as migrations. `BOOTSTRAP_*` vars are never set in production — the command cannot run without them, preventing rogue admin creation on hosted environments. Vars are deleted from `.env` after use.

## DEC-148 — Product catalog is operational data, lives in migrations (2026-03-21)
**Source**: `handoffs/crosscutting/2026-03-21-session-wrapup.md`
Booking products, booking resources, and prices are real operational data (the actual product line), not dev seed data. They belong in a versioned migration against the canonical baseline, not in `seed_dev_data.sql`. The seed script may reference IDs produced by that migration, but the authoritative product catalog is migration-managed.

## DEC-149 — Railway does not set HSTS; application must (2026-03-21)
**Source**: `handoffs/server/2026-03-21-server-audit-triage.md`
Railway's edge proxy does not set `Strict-Transport-Security` headers (confirmed empirically — Railway's own site omits it). The Rust server sets HSTS via Actix `DefaultHeaders` middleware. Any new surface that serves HTTP responses directly must also set HSTS at the application layer.

## DEC-150 — EmailID enum is canonical for all email metadata (2026-03-21)
**Source**: `handoffs/server/2026-03-21-server-audit-triage.md`
The `EmailID` enum is the single source of truth for email template names, subjects, and metadata. All email-sending code references `EmailID` variants rather than hardcoding template strings. New email types require a new `EmailID` variant.

## DEC-151 — DEC-063 superseded by DEC-050 (CSP connect-src removed) (2026-03-20)
**Source**: `handoffs/surface-website/2026-03-20-api-guard-radius-unification.md`
DEC-063 added `connect-src` for the API origin in CSP headers, assuming the browser would make direct API calls. DEC-050's BFF pattern means all API traffic is server-to-server — the browser never needs `connect-src` for the API origin. The dynamic CSP append was removed entirely. Internal Railway hostnames are no longer exposed in browser-visible headers.

## DEC-152 — Loopback hostname check scoped to PRODUCTION/STAGING only (2026-03-20)
**Source**: `handoffs/surface-website/2026-03-20-api-guard-radius-unification.md`
The `API_BASE_URL` loopback/localhost check only runs when `PUBLIC_MODE` is `PRODUCTION` or `STAGING`. DEV and CONSTRUCTION legitimately use `localhost`. MAINTENANCE is handled by its own gate before the loopback check runs.

## DEC-153 — Invalid PUBLIC_MODE forces MAINTENANCE (2026-03-20)
**Source**: `handoffs/surface-website/2026-03-20-api-guard-radius-unification.md`
`PUBLIC_MODE` is validated at runtime against the `SiteMode` union type set. Unrecognized values (typos, empty strings) are treated as MAINTENANCE rather than silently passing through. This prevents a misconfigured env var from accidentally granting full access.

## DEC-154 — Sanitize WorkflowError at the choke point, not construction sites (2026-03-22)
**Source**: `handoffs/server/2026-03-22-workflow-error-sanitization.md`
`to_api_error_message()` is the single location where internal WorkflowError strings become HTTP response content. Logging and sanitization are co-located there. Future variants added to `WorkflowError` that carry internal strings must follow the same pattern — sanitize at the choke point, never at each call site.

## DEC-155 — `/book` as booking page slug (2026-03-22)
**Source**: `handoffs/surface-website/2026-03-22-book-prices-architecture.md`
Data-backed: slug keywords don't drive rankings for this site (zero of the top 10 queries driving clicks to `/paintball-reservations/` contain "reservations"). `/book` is cleaner, matches CTA language ("Book Now"), and is future-proof.

## DEC-156 — `/prices` as pricing page slug (2026-03-22)
**Source**: `handoffs/surface-website/2026-03-22-book-prices-architecture.md`
Matches query language ("paintball prices," "how much does paintball cost"). Short, direct. Replaces `/rental-prices` which is the larger organic funnel (1,073 sessions vs 321 for reservations).

## DEC-157 — Two route trees for booking and pricing (2026-03-22)
**Source**: `handoffs/surface-website/2026-03-22-book-prices-architecture.md`
The old site's pricing and booking pages serve distinct search intent clusters with <10% query overlap. `/prices/[tier]` and `/book` are separate route trees. Preserving the separation under cleaner URLs is the lowest-risk migration path.

## DEC-158 — Prerendering forbidden on `/prices` and `/book` (2026-03-22)
**Source**: `handoffs/surface-website/2026-03-22-book-prices-architecture.md`
Prices come from the product catalog and must be live. Stale structured data is a Google penalty risk. Both route trees are SSR-only.

## DEC-159 — Product `@id` deduplication across `/prices` and `/book` (2026-03-22)
**Source**: `handoffs/surface-website/2026-03-22-book-prices-architecture.md`
Canonical Product JSON-LD entities are defined on `/prices/[tier]` pages with stable `@id` attributes. `/book` references these `@id`s rather than defining duplicate Product entities. Prevents Google from seeing conflicting Product structured data.

## DEC-160 — Authorize.Net as payment gateway (2026-03-23)
**Source**: `handoffs/server/2026-03-23-payments-plan-availability-fix.md`
Supersedes DEC-038's Stripe/Square reference. Authorize.Net selected for payment processing. Full integration plan (6 slices) in `docs/DISPATCH_PAYMENTS.md`.

## DEC-161 — 30-minute slot step interval for availability (2026-03-23)
**Source**: `handoffs/server/2026-03-23-payments-plan-availability-fix.md`
`SLOT_STEP_MINUTES = 30` in `availability_get.rs`. Fixed constant, not configurable. A 180-min product produces 11 start times per day. Change requires a code edit.

## DEC-162 — 90-day availability horizon (2026-03-23)
**Source**: `handoffs/server/2026-03-23-payments-plan-availability-fix.md`
`MAX_HORIZON_DAYS = 90` in `availability_get.rs`. Requests beyond 90 days return 422. Prevents unbounded calendar queries.

## DEC-163 — Tax rate stored as basis points in system_settings (2026-03-23)
**Source**: `handoffs/server/2026-03-23-payments-plan-availability-fix.md`
`tax_rate_basis_points SMALLINT UNSIGNED` (e.g. 825 = 8.25%). Single rate, integer math, no floats. Queried via `with_database_settings` — no redeploy needed to change the rate.

## DEC-164 — SELECT ... FOR UPDATE on payment_transaction mutations (2026-03-24)
**Source**: `handoffs/server/2026-03-24-payment-slice4-void-refund.md`
All code that reads `payment_transaction` rows before making gateway calls (void, refund, webhook reconciliation) must lock the rows with `SELECT ... FOR UPDATE` to prevent concurrent reversals. Applies to any handler or background job that mutates financial records.

## DEC-165 — Tax calculation: integer-only with half-up rounding (2026-03-24)
**Source**: `handoffs/server/2026-03-24-slice3-charge-at-booking.md`
Tax computed as `(subtotal * rate_bp + 5000) / 10000` in u64. Single source of truth in `pricing.rs`. Both preview and charge paths use it. `api-contracts` types carry u32 cents; server computes in u64 to avoid overflow during multiplication.

## DEC-166 — rustfmt edition = source edition (2024) (2026-03-24)
**Source**: `handoffs/crosscutting/2026-03-24-rustfmt-edition-alignment.md`
`rustfmt.toml` edition must match crate `Cargo.toml` edition declarations. Aligned from 2021 to 2024 across all 17 crates. Prevents formatting drift where rustfmt applies older edition rules to newer edition code.

## DEC-167 — Raw Accept.js for payment tokenization (SAQ A-EP) (2026-03-24)
**Source**: `handoffs/surface-website/2026-03-24-accept-js-payment-form.md`
Client-side tokenization via Authorize.Net's Accept.js library (not hosted iframe). Card data tokenized via `Accept.dispatchData()` and never reaches UWZ server. SAQ A-EP compliance level accepted — owner confirmed full CSS control over payment form is the priority.

## DEC-168 — Payment errors as discriminated union, not exceptions (2026-03-24)
**Source**: `handoffs/surface-website/2026-03-24-accept-js-payment-form.md`
`createBooking` returns a discriminated union (`success | declined | held | error`), not thrown exceptions. Declined cards and held-for-review are expected control flow in payment processing, not exceptional conditions. Surfaces pattern-match on the variant to show appropriate UX.
