# Build System Migration: Type-Driven API Contract Enforcement

## Context

The current contract enforcement relies on `project-schema.json` + GUARDIAN skill (process-based). The migration replaces this with a compiler-enforced pipeline: `cargo xtask build-all` becomes the single contract system where breaking the contract breaks the build.

This happens **before** bookings slices 2-5 so new types are born in the right place.

Reference spec: `server/plan.md`

## Target Architecture (revised 2026-02-17)

```
monorepo/                            <- repo root
|-- api-contract/                    <- NEW: crosscutting — API types + path specs (standalone crate)
|-- .cargo/
|   +-- config.toml                  <- NEW: xtask alias
|-- dist/
|   +-- openapi.json                 <- build artifact (.gitignored)
|-- server/                          <- Cargo workspace root
|   |-- Cargo.toml                   <- [workspace] adds schema-emitter, xtask
|   |-- api/                         <- existing server, depends on api-contract
|   |-- database/                    <- unchanged
|   |-- schema-emitter/              <- NEW: sole OpenAPI derivation, emits dist/openapi.json
|   |-- xtask/                       <- NEW: build orchestrator
|   |-- doc-extractor/               <- unchanged
|   |-- email-template/              <- unchanged
|   |-- postmark/                    <- unchanged
|   +-- rate-limit/                  <- unchanged
|-- sdk-rust/                        <- exists externally, separate migration
+-- sdk-ts/                          <- exists externally, separate migration
```

Dependency chain: `api-contract -> schema-emitter -> dist/openapi.json -> sdks -> surfaces`

**Key structural decision:** `api-contract` lives at the monorepo root as a standalone crate, NOT inside the server workspace. It has zero server dependencies and is consumed by server, sdk-rust, and sdk-ts. Cargo path dependencies (`path = "../../api-contract"` from server crates, `path = "../api-contract"` from SDKs) handle cross-workspace resolution. The server workspace's `Cargo.lock` governs dependency versions when building server crates; `api-contract` is rebuilt automatically when its sources change.

---

## Phase 0: Spike — Validate utoipa stub pattern

**PREREQUISITE. Completed 2026-02-17 — PASSED.**

Validated that utoipa 5.4.0 accepts `#[utoipa::path]` on empty `fn() {}` stubs without `actix_extras`. Tested: request bodies, response bodies with `$ref`, path params, security modifiers, `#[schema(inline)]` wrappers, generic types (`ApiResult<T>`). All produced valid OpenAPI 3.1.0 output.

Key finding from spike: generic types produce schema names like `ApiError_ErrorReason`, `ApiResult_AccessToken`. Pin schema names with `#[schema(as = ...)]` if the current codebase expects different names.

---

## Phase 1: Create `api-contract` crate + extract types

### Phase 1a: Create crate + move types via re-export facade

**Commit 1a — repo stays green, zero handler changes**

Create `api-contract/Cargo.toml` at the **monorepo root** (standalone, not a server workspace member):

```toml
[package]
name = "api-contract"
version = "0.1.0"
edition = "2024"

[dependencies]
serde = { version = "1", features = ["derive"] }
utoipa = { version = "5", features = ["chrono"] }
chrono = { version = "0.4", features = ["serde"] }
```

Zero dependencies on actix-web, sqlx, database, or any runtime crate.

Add path dependency in `server/api/Cargo.toml`:
```toml
api-contract = { path = "../../api-contract" }
```

**Do NOT add `api-contract` to `server/Cargo.toml` workspace members** — it is standalone.

#### Complete DTO extraction list (verified)

**Common envelope types** (from `api/src/types/` and `api/src/enums/`):

| Type | Current location | Notes |
|---|---|---|
| `ApiSuccess<T>` | `types/api_success.rs` | Pure serde+utoipa. Moves as-is. |
| `ApiError<ErrorReason>` | `types/api_error.rs` | Pin schema name — spike showed utoipa generates `ApiError_ErrorReason`. |
| `ErrorReason` | `enums/error.rs:178-182` | Only the struct, NOT the `Error` enum (too coupled). |
| `ApiResult<T>` | `enums/api_result.rs` | Enum + pure-data methods. NOT `to_http()`. See Phase 1b. |

**Session types:**

| Type | Current location |
|---|---|
| `CreateSessionBody` | `api/sessions/sessions_post.rs:15-19` |
| `AccessToken` | `api/sessions/sessions_post.rs:22-26` — make owned (`String` not `&'a str`). No consumers yet. |
| `ApiResultToken` | `api/sessions/sessions_openapi_spec.rs:82-83` |

**Secret types:**

| Type | Current location |
|---|---|
| `CreateSecretBody` | `api/secrets/secrets_post.rs:10-14` |

**Email verification types:**

| Type | Current location |
|---|---|
| `EmailVerificationPost` | `api/verifications/email/email_post.rs:22-25` |
| `PatchReqPath` | `api/verifications/email/email_patch.rs:14-17` |
| `SuccessMessage` | `api/verifications/email/email_verifications_openapi_spec.rs:117` |

**Extraction types:**

| Type | Current location |
|---|---|
| `NewScanSession` | `api/extractions/sessions/sessions_post.rs:28-31` |
| `ReqPath` | `api/extractions/sessions/sessions_post.rs:33-36` |
| `BatchIngestItem` | `api/extractions/sessions/sessions_post.rs:38-45` |
| `BatchIngestResponse` | `api/extractions/sessions/sessions_post.rs:47-50` |
| `NoData` | `api/extractions/extraction_openapi_spec.rs:250` |
| `ApiResultNewScanSession` | `api/extractions/extraction_openapi_spec.rs:57-58` |
| `ApiResultBatchIngestResponse` | `api/extractions/extraction_openapi_spec.rs:174-175` |
| `ApiResultProcessing` | `api/extractions/extraction_openapi_spec.rs:252-253` |

**Consolidated `ApiResultError`:**

Currently defined 4 times as 2 different shapes:
- **struct** (sessions:86, email:111): `struct ApiResultError { #[serde(rename = "Error")] pub error: ApiError<ErrorReason> }`
- **enum** (secrets:52, extractions:246): `enum ApiResultError { Error(ApiError<ErrorReason>) }`

Both serialize to `{"Error": {...}}` but produce different utoipa schemas (object vs oneOf). **Canonical definition:** use the struct with `#[serde(rename = "Error")]` — it produces a cleaner OpenAPI schema (plain object, not a oneOf with one variant).

**Do NOT move:**
- `Error` enum — coupled to actix-web, sqlx, database, doc-extractor, postmark, email-template
- `AppState`, `Settings`, `Env`, `Cli`, `RouteCollection`, `ApiServer` — server internals
- `AuthorizationToken`, `HeaderSettings`, `RateLimitSweeper` — server internals
- `CreateEmailVerification` — unit struct used as handler namespace, not an API type
- Domain enums not in API responses (`MasterPassword`, `PrimaryCommand`, `ServerMode`, etc.)

#### Re-export facade pattern

Keep server modules as re-exports so zero handler imports change in this commit:
```rust
// server/api/src/types/api_success.rs becomes:
pub use api_contract::ApiSuccess;
```

Handlers still use `crate::types::ApiSuccess` — facades redirect to api-contract.

#### Module structure

```
api-contract/src/
|-- lib.rs           <- re-exports all public types
|-- common.rs        <- ApiResult, ApiSuccess, ApiError, ErrorReason, ApiResultError
|-- sessions.rs      <- CreateSessionBody, AccessToken, ApiResultToken
|-- secrets.rs       <- CreateSecretBody
|-- verifications.rs <- EmailVerificationPost, PatchReqPath, SuccessMessage
+-- extractions.rs   <- NewScanSession, ReqPath, BatchIngestItem, BatchIngestResponse,
                        NoData, ApiResultNewScanSession, ApiResultBatchIngestResponse,
                        ApiResultProcessing
```

#### Verify

```bash
cd api-contract && cargo build       # standalone build
cd server && cargo build -p api      # server builds via re-export facades
cd server && cargo test -p api       # existing tests pass (including OpenAPI snapshot tests)
```

---

### Phase 1b: Make `with_data`/`with_code` infallible

**Commit 1b — repo stays green, 2 handler call sites change**

The red team flagged this as touching "13+ files" — **verified as overstated**. Actual `with_data` external call sites: **2** (`sessions_post.rs:128`, `extractions/sessions/sessions_post.rs:263`). `with_code` is internal to `api_result.rs` only. Total blast radius: 3 files.

The original plan proposed `Option<Self>` or `Result<Self, ()>`. Both have semantic problems:
- `Option`: communicates "absent" not "failed"
- `Result<Self, ()>`: drops context about what went wrong

**Better: make it infallible.** The Error variant on `with_data` is a logic bug (calling on wrong variant), not a real error. No caller ever handles it meaningfully — both sites just fall through to a generic error response.

In `api-contract/src/common.rs`:
```rust
/// Attach data to an Ok variant. No-op on Error variant (passes through unchanged).
pub fn with_data(self, d: T) -> Self {
    match self {
        Self::Ok(s) => Self::Ok(s.with_data(d)),
        Self::Error(e) => Self::Error(e),
    }
}

/// Override status code on an Ok variant. No-op on Error variant.
pub fn with_code(self, code: u16) -> Self {
    match self {
        Self::Ok(s) => Self::Ok(s.with_code(code)),
        Self::Error(e) => Self::Error(e),
    }
}
```

Handler call sites simplify from:
```rust
match ApiResult::ok(200,"ok").with_data(response) {
    Ok(s) => s.to_http(),
    Err(_) => ApiResult::unauthorized().to_http()
}
```
to:
```rust
ApiResult::ok(200, "ok").with_data(response).to_http()
```

The match was never doing anything useful — the `Ok` path always calls `to_http()`, and the `Err` path creates a different `ApiResult` and calls `to_http()`. Making `with_data` infallible eliminates the branch entirely.

**Note:** `extractions/sessions/sessions_post.rs:263` uses `ApiResult::server_error()` as its fallback. After making infallible, this branch disappears. If a future case genuinely needs different behavior on Ok vs Error variants, the caller can `match` on the `ApiResult` enum directly.

#### Verify

```bash
cd server && cargo build -p api && cargo test -p api
```

---

### Phase 1c: Create extension trait + update imports

**Commit 1c — repo stays green, 61 `.to_http()` calls across 12 files get the trait import**

Create `server/api/src/extensions/mod.rs` with `IntoHttpResponse`:
```rust
use actix_web::{http::StatusCode, HttpResponse};
use api_contract::ApiResult;
use serde::Serialize;
use utoipa::ToSchema;

pub trait IntoHttpResponse {
    fn to_http(self) -> HttpResponse;
}

impl<T: Serialize + ToSchema> IntoHttpResponse for ApiResult<T> {
    fn to_http(self) -> HttpResponse {
        // existing to_http logic from api_result.rs
    }
}
```

Create a prelude:
```rust
// api/src/prelude.rs
pub use api_contract::*;
pub use crate::extensions::IntoHttpResponse;
```

Update all handler files:
1. Add `use crate::prelude::*;` (or selective `api_contract::` imports)
2. Remove the re-export facades from Phase 1a
3. Delete emptied server modules or reduce to server-only types

#### Verify

```bash
cd api-contract && cargo build
cd server && cargo build -p api && cargo test -p api
```

---

## Phase 2: Move path specs to `api-contract`

**Commit 2 — repo stays green**

### Pre-work: Capture baseline OpenAPI output

Before any changes, capture the current runtime OpenAPI JSON for diffing:
```bash
cargo test -p api -- --ignored openapi_snapshot 2>/dev/null  # or start server + curl
```

### 2a. Create path spec stubs in api-contract

In `api-contract/src/paths/`, create stub functions with `#[utoipa::path]` metadata. Empty bodies, no actix-web dependency.

```rust
// api-contract/src/paths/sessions.rs
use crate::{CreateSessionBody, ApiResultToken, ApiResultError};

#[utoipa::path(
    post,
    path = "/v1/sessions",
    operation_id = "createSession",
    tags = ["sessions"],
    security([]),
    request_body(content = CreateSessionBody, content_type = "application/json"),
    responses(
        (status = 200, description = "OK", body = ApiResultToken,
            content_type = "application/json"),
        (status = 401, description = "unauthorized",
            content_type = "application/json",
            body = ApiResultError),
        (status = 429, description = "rate limited",
            content_type = "application/json",
            body = ApiResultError),
    )
)]
pub fn post_sessions() {}
```

**Explicit `content_type = "application/json"`** on all request/response bodies. The current spec files get this inferred from `actix_extras` + `web::Json<T>`. Without that feature, it must be explicit or utoipa defaults to `application/json` anyway — but being explicit prevents any ambiguity.

#### Multipart upload handling

`post_extraction_session_batch_upload` uses `content_type = "multipart/form-data"` in its `request_body(...)`. This works in stubs — utoipa reads content_type from the attribute, not the function signature. No actix-web dependency needed.

#### Path parameters

Endpoints with path params (`{session_id}`, `{uuid}`, `{id}`) use `params(("session_id" = i64, Path, ...))` in the attribute. Verified in Phase 0 spike: this works on empty stubs. The `Path` keyword is utoipa-native, not actix-specific.

#### Register ALL paths (fix pre-existing gap)

The current `open_api_doc.rs` only registers 6 paths. Two extraction endpoints are defined but **not registered**:
- `post_extraction_session_batch_upload` (upload batch)
- `post_extraction_session_process` (process session)

Fix this during migration — register all paths in the stubs.

Module structure:
```
api-contract/src/
+-- paths/
    |-- mod.rs
    |-- sessions.rs        <- post_sessions, delete_sessions
    |-- secrets.rs         <- post_secrets
    |-- verifications.rs   <- post_email_verification, patch_email_verification
    +-- extractions.rs     <- post_extraction_session, post_extraction_session_batch_upload,
                              post_extraction_session_process
```

### 2b. Update server's `ApiDoc` to reference api-contract paths

Edit `server/api/src/types/open_api_doc.rs`:
```rust
#[openapi(
    paths(
        api_contract::paths::sessions::post_sessions,
        api_contract::paths::sessions::delete_sessions,
        api_contract::paths::secrets::post_secrets,
        api_contract::paths::verifications::post_email_verification,
        api_contract::paths::verifications::patch_email_verification,
        api_contract::paths::extractions::post_extraction_session,
        api_contract::paths::extractions::post_extraction_session_batch_upload,
        api_contract::paths::extractions::post_extraction_session_process,
    ),
    components(schemas(...)),  // same as before, types now from api-contract
    ...
)]
pub struct ApiDoc;
```

This keeps the server's `ApiDoc` compiling. OpenAPI test suites (`open_api_session_tests.rs`, etc.) continue to pass since they reference `crate::types::open_api_doc::ApiDoc`.

### 2c. Delete/gut openapi_spec.rs files

Remove `#[utoipa::path]` functions and response wrapper types from:
- `api/sessions/sessions_openapi_spec.rs`
- `api/secrets/secrets_openapi_spec.rs`
- `api/verifications/email/email_verifications_openapi_spec.rs`
- `api/verifications/sms/sms_verifications_openapi_spec.rs` (placeholder — 1 line, just delete)
- `api/extractions/extraction_openapi_spec.rs`

Wrapper types (`ApiResultToken`, `ApiResultError`, etc.) already moved in Phase 1a. The `#[utoipa::path]` functions are not used as route handlers (`route_collection.rs` uses `Handler::logic` directly). Safe to delete entirely.

### 2d. Post-migration OpenAPI diff

Diff the server's OpenAPI output against the baseline captured in pre-work. Expected changes:
- Two new extraction paths appear (previously unregistered)
- Schema names may change if `#[schema(as = ...)]` wasn't applied — fix before committing

#### Verify

```bash
cd api-contract && cargo build    # stubs compile standalone
cd server && cargo build -p api   # server builds with updated ApiDoc
cd server && cargo test -p api    # OpenAPI tests pass
```

---

## Phase 3: Create `schema-emitter`

**Commit 3 — repo stays green**

### 3a. Create `server/schema-emitter/Cargo.toml`

```toml
[package]
name = "schema-emitter"
version = "0.1.0"
edition = "2024"

[dependencies]
api-contract = { path = "../../api-contract" }
utoipa = { version = "5" }
serde = { version = "1", features = ["derive"] }
```

### 3b. Create `server/schema-emitter/src/main.rs`

The schema-emitter's `ApiDoc` references the same api-contract paths and schemas as the server's `ApiDoc`. Since Phase 5 will eliminate the server's `ApiDoc`, schema-emitter becomes the **sole derivation**.

Extract the `Security` modifier to `api-contract` (it only depends on utoipa + serde). Both schema-emitter and server (temporarily) can reuse it.

### 3c. Add to workspace + .gitignore

- Add `"schema-emitter"` to workspace members in `server/Cargo.toml`
- Add `dist/` to root `.gitignore`

### 3d. Path registration coverage test

The "new path not registered" risk is **more reducible than the red team suggested**. Add a grep-based test in schema-emitter:

```rust
#[test]
fn all_path_stubs_registered() {
    // Count #[utoipa::path] annotations in api-contract/src/paths/
    let stub_count = count_utoipa_paths_in("../../api-contract/src/paths/");

    // Count paths in the emitted OpenAPI
    let spec = ApiDoc::openapi();
    let path_count: usize = spec.paths.paths.values()
        .map(|item| item.operations.len())
        .sum();

    assert_eq!(stub_count, path_count,
        "Mismatch: {stub_count} #[utoipa::path] stubs but {path_count} registered operations. \
         Did you add a path stub without registering it in schema-emitter's #[openapi(paths(...))]?");
}
```

This is crude but effective. If someone adds a `#[utoipa::path]` stub in api-contract but forgets to register it in schema-emitter, this test catches it.

### 3e. Verify

```bash
cd server && cargo run -p schema-emitter -- ../dist/openapi.json  # emits valid spec
cd server && cargo test -p schema-emitter                          # coverage test passes
cd server && cargo build -p api                                    # server still works
```

---

## Phase 4: Create `xtask` orchestrator

**Commit 4 — repo stays green**

### 4a. Create `server/xtask/Cargo.toml`

```toml
[package]
name = "xtask"
version = "0.1.0"
edition = "2024"
```

### 4b. Create `server/xtask/src/main.rs`

Commands:
- `cargo xtask build-all` — full sequential pipeline
- `cargo xtask schema` — emit schema only
- `cargo xtask gen` — schema + TS SDK gen (stub until sdk-ts migrated)
- `cargo xtask check` — semver check (stub until api-contract is published)

Pipeline steps for `build-all`:
1. Emit schema (`cargo run -p schema-emitter -- <repo-root>/dist/openapi.json`)
2. Build server (`cargo build -p api`)
3. Build Rust SDK (stub — sdk-rust migration separate)
4. Generate TS SDK (stub — sdk-ts migration separate)
5. Build surfaces (stub — surfaces are empty)

**Repo root resolution:** Walk up from `CARGO_MANIFEST_DIR` looking for `.git`. In worktrees, `.git` is a file (not directory), so check `path.exists()` not `path.is_dir()`. Use the located root for `dist/` path and future `npx`/`npm` calls.

**Stub steps:** Steps 3-5 print a skip message and exit 0. The contract system is NOT fully enforced end-to-end until stubs become real. SDKs exist externally and will be migrated as separate work. Mark as blocking before considering the pipeline "complete."

### 4c. Add to workspace + cargo alias

Add `"xtask"` to workspace members in `server/Cargo.toml`.

Create `.cargo/config.toml` at the **monorepo root**:
```toml
[alias]
xtask = "run --manifest-path server/xtask/Cargo.toml --"
```

This enables `cargo xtask build-all` from the monorepo root. Always run xtask from the monorepo root — the alias path is relative to the working directory.

### 4d. Deliberate break test

1. Rename a field in `api_contract::CreateSessionBody`
2. Run `cargo xtask build-all`
3. Confirm server build step fails with clear error at the exact point of breakage
4. Revert

### 4e. Verify

```bash
cargo xtask build-all  # exits 0, run from monorepo root
```

---

## Phase 5: Eliminate dual-ApiDoc — server serves `dist/openapi.json`

**Commit 5 — repo stays green**

After Phase 3, there are two independent `#[derive(OpenApi)]` invocations: the server's `ApiDoc` in `open_api_doc.rs` and schema-emitter's `ApiDoc`. Both reference the same api-contract paths and schemas, but they are two separate lists that can silently diverge if someone updates one and forgets the other. **This is the biggest latent drift risk in the plan.**

**Fix:** Remove the server's `#[derive(OpenApi)]` entirely. The server serves the pre-built `dist/openapi.json` instead of deriving its own.

### 5a. Replace `ApiDoc` with static file serving

```rust
// server/api/src/types/open_api_doc.rs — replace the entire derive

const OPENAPI_JSON: &str = include_str!("../../../../dist/openapi.json");
const OPENAPI_YAML: &str = ...; // convert at build time, or drop yaml endpoint

pub struct ApiDoc;

impl ApiDoc {
    pub async fn json() -> HttpResponse {
        HttpResponse::Ok()
            .content_type("application/json")
            .body(OPENAPI_JSON)
    }

    // Keep the doc() method for existing test compatibility
    pub fn doc() -> utoipa::openapi::OpenApi {
        serde_json::from_str(OPENAPI_JSON)
            .expect("dist/openapi.json must be valid")
    }
}
```

`include_str!` embeds `dist/openapi.json` at compile time. This means `cargo build -p api` requires `dist/openapi.json` to exist — which `cargo xtask build-all` guarantees by running schema-emitter first. If someone runs `cargo build -p api` without running the pipeline, the build fails with a clear error pointing at the missing file.

**This is a feature, not a bug** — it enforces the build ordering.

### 5b. Bootstrap `dist/openapi.json` for DX

After Phase 5 completes, run `cargo xtask schema` once and **commit `dist/openapi.json`** (remove the `.gitignore` entry for `dist/`). This ensures:
- `cargo build -p api` works immediately after clone — no bootstrapping step
- `cargo test -p api` works without running the pipeline first
- New contributors don't hit a cryptic `include_str!` error
- CI only needs `cargo xtask build-all` to regenerate — the committed file is the fallback

The committed file may go stale, but `cargo xtask build-all` always overwrites it. Staleness is caught by CI running the full pipeline and diffing.

### 5c. Update xtask pipeline order

The `build-all` pipeline already runs schema emission before server build. No change needed — but make the dependency explicit in xtask output:

```
  -> Emit schema... done
  -> Build server (requires dist/openapi.json)... done
```

### 5d. Migrate existing OpenAPI tests

The 4 test suites (`open_api_session_tests.rs`, `open_api_secrets_tests.rs`, `open_api_email_tests.rs`, `open_api_extractions_tests.rs`) use `ApiDoc::doc()`. Since `doc()` now deserializes from the included JSON, these tests continue to work — they test the schema-emitter's output, not a separate derivation.

**Prerequisite:** `dist/openapi.json` must exist before running `cargo test -p api`. With the committed bootstrap file (5b), this is always true.

### 5e. Remove utoipa derive from server

After this phase, the server's `api/Cargo.toml` no longer needs utoipa in its dependencies (except for `ToSchema` derives on types — but those are now in api-contract). Remove `utoipa-swagger-ui` if swagger-ui is being served as static HTML against the JSON file.

### 5f. Verify

```bash
cargo xtask schema                  # emit dist/openapi.json
cd server && cargo build -p api     # compiles with included JSON
cd server && cargo test -p api      # OpenAPI tests pass against schema-emitter output
rm ../dist/openapi.json && cargo build -p api  # FAILS — proves enforcement
cargo xtask schema                  # restore
```

---

## Red Team Summary (verified + corrected)

### HIGH severity findings

| # | Finding | Mitigation | Phase | Status |
|---|---------|------------|-------|--------|
| 5.3 | utoipa stub pattern unvalidated | Phase 0 spike | Pre | **PASSED** |
| 5.1 | Phase 1 is 3-4 commits forced into one | Split into 1a/1b/1c | 1 | Addressed |
| 1.1 | `ApiError` schema name changes | Pin with `#[schema(as = ...)]`, diff output | 1a | Addressed |
| 1.2 | `with_data`/`with_code` cascade | ~~"13+ files"~~ **Corrected: 2 call sites + 1 internal.** Make infallible. | 1b | Corrected |
| 1.4 | utoipa stubs without `actix_extras` | Phase 0 spike validates. Explicit content_type. | 2 | **PASSED** |
| 1.5 | `ApiResultError` 4x, 2 shapes | Canonical struct definition. Verified identical JSON serialization. | 1a | Addressed |
| 2.1 | Deleting spec files breaks `ApiDoc` | Update ApiDoc to api-contract paths in same commit | 2 | Addressed |
| 3.1 | Runtime swagger-ui drift | **Phase 5 eliminates the second derivation entirely.** | 5 | **NEW** |
| NEW | Dual-ApiDoc drift risk | Phase 5: server serves `dist/openapi.json` via `include_str!`. Single derivation. | 5 | **NEW** |

### MEDIUM severity findings

| # | Finding | Mitigation | Phase | Status |
|---|---------|------------|-------|--------|
| 4.1 | Incomplete DTO list | **Full verified list: 18 types** (see Phase 1a table) | 1a | Corrected |
| 4.2 | OpenAPI tests not accounted for | Tests use `ApiDoc::doc()` which works in both Phase 2 and Phase 5 | 2, 5 | Addressed |
| 3.2 | Wrapper types scattered | Accept clutter, canonical list in Phase 1a | 1a | Addressed |
| 5.2 | xtask repo root resolution | Walk up to `.git` (file or dir). Use `path.exists()`. | 4 | Addressed |
| 1.3 | AccessToken lifetime removal | No consumers exist. Verify schema name in diff. | 1a | Addressed |
| NEW | Pre-existing unregistered paths | 2 extraction endpoints not in `open_api_doc.rs`. Fix during Phase 2. | 2 | **NEW** |
| NEW | SDK stubs mask contract gaps | Stubs exit 0. SDKs exist but migrated separately. Pipeline not enforced e2e until stubs become real. | 4 | **NEW** |

### LOW severity findings

| # | Finding | Mitigation | Phase |
|---|---------|------------|-------|
| 1.6 | Extension trait import boilerplate | Server prelude module | 1c |
| 4.3 | Security modifier not extracted | Move to api-contract (utoipa+serde only) | 3 |
| 4.4 | Edition 2024 must be explicit | Set in all new Cargo.toml files | 1a |

### Irreducible risks

| Risk | Mitigation |
|---|---|
| Semantic drift (field changes meaning, not type) | Newtypes + human review |
| Runtime serialization bugs | Integration tests against live test server |
| New type added but not registered in schema-emitter | Coverage test (Phase 3d) |
| New path added but not registered | Grep-based count test (Phase 3d) — **reduced from "irreducible"** |

---

## Files Modified Per Phase

**Phase 1a:**
- NEW: `api-contract/Cargo.toml`, `api-contract/src/{lib,common,sessions,secrets,verifications,extractions}.rs`
- EDIT: `server/api/Cargo.toml` (add api-contract path dep)
- EDIT: server type/enum modules (re-export facades)

**Phase 1b:**
- EDIT: `api-contract/src/common.rs` (with_data/with_code now infallible)
- EDIT: `server/api/src/api/sessions/sessions_post.rs` (remove match, direct chain)
- EDIT: `server/api/src/api/extractions/sessions/sessions_post.rs` (remove match, direct chain)

**Phase 1c:**
- NEW: `server/api/src/extensions/mod.rs` (IntoHttpResponse)
- NEW: `server/api/src/prelude.rs`
- EDIT: 12 handler files (import migration, 61 `.to_http()` calls gain trait import)
- DELETE/GUT: emptied server type/enum modules

**Phase 2:**
- NEW: `api-contract/src/paths/{mod,sessions,secrets,verifications,extractions}.rs`
- EDIT: `server/api/src/types/open_api_doc.rs` (ApiDoc refs api-contract paths)
- DELETE: `server/api/src/api/{sessions,secrets,extractions}/*openapi_spec.rs`
- DELETE: `server/api/src/api/verifications/{email,sms}/*openapi_spec.rs`

**Phase 3:**
- NEW: `server/schema-emitter/{Cargo.toml,src/main.rs}`
- EDIT: `server/Cargo.toml` (workspace member: schema-emitter)
- EDIT: `.gitignore` (add dist/)

**Phase 4:**
- NEW: `server/xtask/{Cargo.toml,src/main.rs}`
- NEW: `.cargo/config.toml` (xtask alias)
- EDIT: `server/Cargo.toml` (workspace member: xtask)

**Phase 5:**
- EDIT: `server/api/src/types/open_api_doc.rs` (replace derive with `include_str!`)
- EDIT: `server/api/Cargo.toml` (remove utoipa derive dependency if possible)
- EDIT: `.gitignore` (remove dist/ entry — committed bootstrap file)
- NEW: `dist/openapi.json` (committed bootstrap, regenerated by pipeline)

---

## Verification (end state after Phase 5)

```bash
# Full pipeline (from monorepo root)
cargo xtask build-all          # exits 0: schema -> server -> stubs

# Contract enforcement
# 1. Rename field in api-contract -> cargo xtask build-all fails at server build
# 2. Add path stub without registering -> coverage test fails
# 3. Remove dist/openapi.json -> cargo build -p api fails (include_str!)
# 4. All three prove single-derivation enforcement

# Existing tests
cd server && cargo test -p api              # all pass (reading from dist/openapi.json)
cd server && cargo test -p schema-emitter   # coverage test passes

# Schema quality
diff dist/openapi.json <baseline>  # endpoints, types, security match
                                    # plus 2 previously-unregistered extraction paths
```

---

## Session Planning

This migration spans multiple sessions. Recommended session boundaries:

| Session | Phases | Commit(s) | Key risk |
|---------|--------|-----------|----------|
| 1 | 1a | Create api-contract + facades | Schema name pinning |
| 2 | 1b + 1c | Infallible with_data + extension trait + import migration | 12-file import sweep |
| 3 | 2 | Path spec stubs + OpenAPI migration | Baseline diff accuracy |
| 4 | 3 + 4 | schema-emitter + xtask | Coverage test wiring |
| 5 | 5 | Eliminate dual-ApiDoc + bootstrap commit | include_str! path correctness |

Each session should start with `/orient`, read this plan, and pick up from the noted phase. Write a handoff at session end.
