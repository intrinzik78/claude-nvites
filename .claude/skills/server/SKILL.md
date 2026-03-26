---
name: server
description: Orient for Rust server work. Loads style conventions, handler patterns, type flow, and build sequence.
---

# Server

Every endpoint is a **contract**. Type safety at the boundary, validation before logic, clarity over cleverness.

## Anti-Patterns

- **Writing server code** without first reading `docs/RUST_STYLE_GUIDE.md`
- **Exploring or modifying architecture** without first reading `docs/DECISIONS.md`
- **Questioning crate roles or principles** without first reading `docs/Architecture.md`
- **Adding an error variant** without adding its `to_api_error_message()` mapping and updating `EXPECTED_CLIENT_FACING_COUNT` in `enums/error.rs` — the sentinel test will fail
- **Modeling new handlers on bookings/sessions** — those are early-era, logic-heavy (200-330 lines). New handlers should follow the workflow-era pattern: thin handler (~50 lines), business logic delegated to domain types/engines
- **Using `?` operator in handlers** — handlers return `impl Responder`, not `Result`. Errors go through `.to_http_response()` with early `return`, not `?`. The `Error` enum and `ToHttpResponse` trait handle conversion to HTTP status codes
- **Placing a handler file directly in `api/`** — handlers live in domain subdirectories (`api/queue_entries/`, `api/workflow_instances/`, etc.). Each subdirectory has a `mod.rs` that declares submodules and barrel-exports the handler structs
- **Using `sqlx::query!` compile-time macros** — this codebase uses `sqlx::query_as()` with string SQL throughout. Follow the existing pattern
- **Adding a new type** without checking `traits/` for existing `to_*` conversion traits to implement — the codebase has ~27 conversion traits (e.g. `ToHttpResponse`, `ToPermission`, `ToAuthorizationStatus`, `ToHash`, `ToEncryptedBuffer`). New types that participate in existing flows need the appropriate trait impls
- **Skipping review-rs skill use** as verification of a write block. the review-rs skill identifies patterns and conventions that were missed. skipping it forces the human user to remember to run the skill manually leading to convention and pattern drift.

## Type Flow

Types flow through three layers:

1. **api-contracts** — DTOs for JSON serialization (`CreateSessionBody`, `BookingDto`, `WorkflowDefinitionDto`), the `ApiResult` response envelope, and OpenAPI `#[utoipa::path]` stubs in `paths/`. Shared by server and SDK generators. **Any edit here is a contract change.**
2. **server/api/src/types/** — Business logic types. Own their table queries, implement validation, hold invariants. Organized by domain: `sessions/`, `workflow/`, `bookings/`, `queue_entries/`, etc.
3. **server/api/src/api/** — ~90 handlers across ~19 domain subdirectories. Zero-sized structs with `async fn logic()`. Extract, validate, delegate to types, return via `ApiResult` or `Error::to_http_response()`.

Supporting layers:
- **server/api/src/enums/** — `Error` (central, ~186 variants, `derive_more::From`), `ApiResult`, domain enums. Subdirectories for `workflow/`, `sessions/`
- **server/api/src/traits/** — ~27 conversion traits (`to_*` pattern) that define how types flow between layers. Check here before inventing inline conversions
- **server/api/src/services/** — 3 middleware services: `RouteLock` (auth), `EpochBump` (client invalidation), `RateLimitMiddleware`

## Handler Pattern

```rust
pub struct QueueEntryArrive;

impl QueueEntryArrive {
    pub async fn logic(
        _permissions: WereChecked,       // proves RouteLock passed
        id:           Path<i32>,         // URL path parameter
        shared:       Data<AppState>,    // DB pool, sessions, config
    ) -> impl Responder {
        let db = shared.database();
        let id = id.into_inner();

        // 1. Load and validate
        let entry = match QueueEntry::by_id(id, db).await {
            Ok(Some(e)) => e,
            Ok(None) => return Error::QueueEntryNotFound.to_http_response(),
            Err(e) => return e.to_http_response(),
        };

        if !is_valid_transition(entry.status(), QueueEntryStatus::Arrived) {
            return Error::QueueEntryInvalidTransition.to_http_response();
        }

        // 2. Delegate to type (owns the SQL)
        match QueueEntry::update_arrived(id, db).await {
            Ok(()) => {
                match QueueEntry::by_id(id, db).await {
                    Ok(Some(updated)) => {
                        ApiResult::ok(200, "ok")
                            .with_data(QueueEntryDto::from(&updated)).to_http()
                    }
                    Ok(None) => ApiResult::<()>::server_error().to_http(),
                    Err(e) => return e.to_http_response(),
                }
            }
            Err(e) => return e.to_http_response(),
        }
    }
}
```

Key patterns: `impl Responder` return (not `Result`), `Error::*.to_http_response()` for early returns, `ApiResult::ok().with_data().to_http()` for success.

## Handler Module Structure

Each domain subdirectory in `api/` follows the same pattern:

```rust
// api/queue_entries/mod.rs
mod queue_entry_arrive;
mod queue_entry_complete;
// ...

pub use queue_entry_arrive::QueueEntryArrive;
pub use queue_entry_complete::QueueEntryComplete;
// ...
```

This lets `route_collection.rs` reference `queue_entries::QueueEntryArrive` directly.

## Route Registration

`server/api/src/types/route_collection.rs` (~430 lines) — scopes per domain, middleware at scope/route level:

```rust
pub fn bookings(cfg: &mut web::ServiceConfig) {
    cfg.service(
        web::scope("/bookings")
            .wrap(EpochBump::new(EpochDomain::Booking))  // scope-level: bump epoch on non-GET
            .route("", web::post().to(BookingsPost::logic)
                .wrap(RouteLock::default(&editor)))       // route-level: auth + role
            .route("/{id}", web::get().to(BookingsGet::logic)
                .wrap(RouteLock::default(&user)))
    );
}
```

## Middleware Stack

Request path (Actix wraps inside-out, so last `.wrap()` runs first):
`RateLimitMiddleware` → `CORS` → `DefaultHeaders` → `TracingLogger` → per-scope `EpochBump` → per-route `RouteLock` → handler.

- **RouteLock** — extracts bearer token, verifies session (in-memory first, DB if stale), checks role permissions, injects `WereChecked` marker type
- **EpochBump** — on non-GET success, increments atomic epoch counter. Clients poll `/epochs` to detect changes
- **RateLimitMiddleware** — token-bucket rate limiting (3 separate limiters: general, addon, queue)

## Background Jobs

Spawned at startup in `main.rs`: `SessionSweeper`, `RateLimitSweeper`, `UserEpochSync`, `ScanSweeper`, `WorkflowSweeper`, `BookingSweeper`.

## xtask Commands

| Command | What it does |
|---------|-------------|
| `build-all` | schema → build server → gen TypeScript SDK |
| `schema` | schema-emitter → `dist/openapi.json` |
| `gen` | TypeScript SDK codegen only |
| `check` | schema + path stub count test + OpenAPI path registration test |
| `db-reset [--yes]` | DROP + recreate DB + run migrations + seed |
| `seed-dev` | Seed development data |

## New Endpoint Sequence

Start from the contract, work inward:

1. **api-contracts** — DTO struct + OpenAPI `#[utoipa::path]` stub in `paths/`
2. **server/api/src/types/** — business logic type (owns SQL via `sqlx::query_as()`)
3. **server/api/src/api/{domain}/` — handler file (zero-sized struct + `async fn logic`), add `mod` + `pub use` to the subdirectory's `mod.rs`
4. **server/api/src/enums/error.rs** — add error variants, map them in `to_api_error_message()`, bump `EXPECTED_CLIENT_FACING_COUNT`
5. **server/api/src/traits/** — implement any relevant `to_*` conversion traits for new types
6. **server/api/src/types/route_collection.rs** — route registration with middleware
7. **`cd server && cargo xtask build-all`** — must pass (api-contracts → schema-emitter → openapi.json → server → sdk-ts types)
8. **sdk-ts** — hand-written wrapper in `sdk-ts/src/api/` + barrel export. `build-all` regenerates types but **not** endpoint wrappers.

## Testing

- Unit tests: in-file `#[cfg(test)]` modules alongside the code they test
- Integration tests: `server/api/src/types/workflow/integration_tests.rs` — tests against real MySQL, not mocks
- Run: `cd server && cargo test -p uwz-server && cargo clippy`
- New domain types should include unit tests for helper functions, DTO mappings, and enum round-trips
- New workflow logic should extend the integration test file

## Hard Boundaries

- Structured logging via `tracing` (DEC-118) — use `tracing::{info, warn, error}`, not `println!`

$ARGUMENTS
