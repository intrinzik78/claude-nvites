# Build System Migration Spec: Type-Driven API Contract Enforcement

**Version:** 1.0  
**Purpose:** Migrate from manually maintained JSON schema + contract-checking tools to a compiler-enforced contract pipeline where the Rust type system is the single source of truth.  
**Intended executor:** Claude Code  
**Guiding principle:** If it compiles, the contract holds. If the contract is broken, nothing compiles.

---

## 1. Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     MONOREPO                                │
│                                                             │
│  crates/                                                    │
│  ├── api-types/        ← SINGLE SOURCE OF TRUTH             │
│  │   └── src/lib.rs    (all request/response/error types)   │
│  ├── server/           ← depends on api-types               │
│  │   └── handlers consume api-types, utoipa derives schema  │
│  ├── sdk-rust/         ← generated from openapi.json        │
│  └── schema-emitter/   ← tiny binary, depends only on       │
│      │                    api-types + utoipa                 │
│      └── emits dist/openapi.json                            │
│                                                             │
│  sdks/                                                      │
│  └── typescript/       ← generated from openapi.json        │
│                                                             │
│  dist/                                                      │
│  └── openapi.json      ← build artifact, never hand-edited  │
│                                                             │
│  xtask/                                                     │
│  └── src/main.rs       ← build orchestrator                 │
└─────────────────────────────────────────────────────────────┘
```

### Dependency Chain (Enforced by Build Order)

```
api-types  →  schema-emitter  →  dist/openapi.json  →  sdk-rust (generated)
                                                     →  sdk-typescript (generated)
                                                     →  server (validates against schema)
```

Nothing downstream can build against a stale upstream artifact. The chain is sequential and non-skippable.

---

## 2. Crate: `api-types`

This is the single source of truth. Every request body, response body, error variant, query parameter, and path parameter is a Rust type defined here.

### Rules

- Every public type derives `serde::Serialize`, `serde::Deserialize`, and `utoipa::ToSchema`.
- Every enum that represents an API error derives `utoipa::ToSchema` with discriminator metadata.
- No handler logic. No database types. No framework dependencies. Pure data types only.
- This crate has zero dependencies on `server`, `axum`, `sqlx`, or any runtime crate.
- New fields on existing response types MUST be `Option<T>` to maintain backward compatibility. Required new fields are a breaking change.

### Example Structure

```rust
// crates/api-types/src/lib.rs

pub mod auth;
pub mod payments;
pub mod inventory;
pub mod common;

// Re-export everything flat for ergonomic SDK use
pub use auth::*;
pub use payments::*;
pub use inventory::*;
pub use common::*;
```

```rust
// crates/api-types/src/payments.rs

use serde::{Serialize, Deserialize};
use utoipa::ToSchema;

/// Amount in the smallest currency unit (e.g., cents for USD).
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct AmountCents(pub i64);

#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct CreatePaymentRequest {
    pub amount: AmountCents,
    pub currency: CurrencyCode,
    pub description: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct PaymentResponse {
    pub id: PaymentId,
    pub amount: AmountCents,
    pub currency: CurrencyCode,
    pub status: PaymentStatus,
    pub created_at: chrono::DateTime<chrono::Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub enum PaymentStatus {
    Pending,
    Completed,
    Failed,
    Refunded,
}
```

### Semantic Encoding via Newtypes

Where a field's meaning is not fully captured by its primitive type, use a newtype. This is how semantic contracts survive codegen.

```rust
/// Newtype: prevents accidental use of raw i64 as a currency amount.
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct AmountCents(pub i64);

/// Newtype: ISO 4217 currency code.
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct CurrencyCode(pub String);

/// Newtype: opaque identifier, never constructed by consumers.
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct PaymentId(pub String);
```

These propagate through codegen as distinct types in the generated SDKs.

---

## 3. Crate: `schema-emitter`

A minimal binary whose only job is to produce `dist/openapi.json` from the types in `api-types`.

### Why a Separate Binary

- Decoupled from server compilation. If a handler has a bug, schema emission still works.
- Fast to compile. Links only `api-types` and `utoipa`, not `axum`, `sqlx`, `tower`, etc.
- Can be run independently in any worktree without starting the server.

### Implementation

```rust
// crates/schema-emitter/src/main.rs

use utoipa::OpenApi;

#[derive(OpenApi)]
#[openapi(
    info(title = "YourAPI", version = "1.0.0"),
    paths(
        // List all endpoint paths here — these reference handler
        // functions but only need the #[utoipa::path] metadata,
        // not the runtime implementation.
    ),
    components(schemas(
        // List all api-types types here
        api_types::CreatePaymentRequest,
        api_types::PaymentResponse,
        api_types::PaymentStatus,
        api_types::AmountCents,
        // ... every public type from api-types
    ))
)]
struct ApiDoc;

fn main() {
    let spec = ApiDoc::openapi().to_pretty_json()
        .expect("Failed to serialize OpenAPI spec");

    let out_path = std::env::args()
        .nth(1)
        .unwrap_or_else(|| "dist/openapi.json".to_string());

    std::fs::create_dir_all(
        std::path::Path::new(&out_path).parent().unwrap()
    ).unwrap();

    std::fs::write(&out_path, &spec).unwrap();
    eprintln!("Schema written to {out_path}");
}
```

### Cargo.toml

```toml
[package]
name = "schema-emitter"
version = "0.1.0"
edition = "2021"

[dependencies]
api-types = { path = "../api-types" }
utoipa = { version = "5", features = ["chrono"] }
```

No other dependencies. This compiles in seconds.

---

## 4. SDK Generation

### 4a. TypeScript SDK

**Generator:** `openapi-typescript` (for types) + `openapi-fetch` (for client).  
**Pinned version:** Lock the exact version in `package.json` at the repo root.

```jsonc
// package.json (repo root, workspace-level)
{
  "devDependencies": {
    "openapi-typescript": "7.6.1",  // pin exact
    "openapi-fetch": "0.13.5"       // pin exact
  }
}
```

**Generation command:**

```bash
npx openapi-typescript dist/openapi.json -o sdks/typescript/src/generated/schema.d.ts
```

**Generated output is NOT committed to the repo.** It is a build artifact. The `sdks/typescript/src/generated/` directory is in `.gitignore`. It is regenerated on every build.

**Consumer code (the thin client / surface) imports from the SDK package, which re-exports generated types:**

```typescript
// sdks/typescript/src/index.ts
export type { paths, components, operations } from './generated/schema';
export { default as createClient } from './client';
```

```typescript
// sdks/typescript/src/client.ts
import createClient from 'openapi-fetch';
import type { paths } from './generated/schema';

export default function create(baseUrl: string) {
  return createClient<paths>({ baseUrl });
}
```

**If the schema changes and a surface uses a removed field, TypeScript compilation fails.** This is the enforcement mechanism. No runtime check, no diff gate, no process.

### 4b. Rust SDK

The Rust SDK can take one of two approaches depending on your needs:

**Option A: Direct dependency on `api-types` (recommended for internal monorepo use)**

If your Rust consumers are inside the monorepo, skip codegen entirely. The Rust SDK is just a thin client crate that depends on `api-types` directly.

```rust
// crates/sdk-rust/src/lib.rs

use api_types::*;

pub struct Client {
    http: reqwest::Client,
    base_url: String,
}

impl Client {
    pub async fn create_payment(
        &self,
        req: CreatePaymentRequest,
    ) -> Result<PaymentResponse, ApiError> {
        let resp = self.http
            .post(format!("{}/payments", self.base_url))
            .json(&req)
            .send()
            .await?;

        // Type-safe deserialization. If the server response
        // doesn't match PaymentResponse, this fails at runtime
        // during development — but crucially, the TYPE is always
        // correct because it comes from the same api-types crate.
        Ok(resp.json().await?)
    }
}
```

This is the strongest guarantee: server and SDK literally share the same type definitions via `api-types`. There is zero drift by construction.

**Option B: Generated from OpenAPI (for external consumers)**

Use `openapi-generator` with the `rust` target pinned to an exact version. Same pattern as TypeScript — generated code is not committed, it's a build artifact.

---

## 5. Build Orchestrator: `cargo xtask`

The entire pipeline is one command: `cargo xtask build-all`.

### Implementation

```rust
// xtask/src/main.rs

use std::process::Command;

fn main() {
    let task = std::env::args().nth(1).unwrap_or_default();

    match task.as_str() {
        "build-all" => {
            step("Emit schema",     || emit_schema());
            step("Generate TS SDK", || gen_typescript_sdk());
            step("Build server",    || build_server());
            step("Build Rust SDK",  || build_rust_sdk());
            step("Build surfaces",  || build_surfaces());
            step("Semver check",    || semver_check());
            println!("\n✅ Full pipeline passed. Contract holds.");
        }
        "schema" => {
            step("Emit schema", || emit_schema());
        }
        "gen" => {
            step("Emit schema",     || emit_schema());
            step("Generate TS SDK", || gen_typescript_sdk());
        }
        "check" => {
            step("Semver check", || semver_check());
        }
        _ => {
            eprintln!("Usage: cargo xtask [build-all|schema|gen|check]");
            std::process::exit(1);
        }
    }
}

fn step(name: &str, f: impl FnOnce() -> Result<(), String>) {
    eprint!("  → {name}...");
    match f() {
        Ok(()) => eprintln!(" ✓"),
        Err(e) => {
            eprintln!(" ✗\n\nFailed at: {name}\n{e}");
            std::process::exit(1);
        }
    }
}

fn emit_schema() -> Result<(), String> {
    run("cargo", &[
        "run", "--bin", "schema-emitter", "--",
        "dist/openapi.json"
    ])
}

fn gen_typescript_sdk() -> Result<(), String> {
    run("npx", &[
        "openapi-typescript",
        "dist/openapi.json",
        "-o", "sdks/typescript/src/generated/schema.d.ts"
    ])
}

fn build_server() -> Result<(), String> {
    run("cargo", &["build", "-p", "server"])
}

fn build_rust_sdk() -> Result<(), String> {
    run("cargo", &["build", "-p", "sdk-rust"])
}

fn build_surfaces() -> Result<(), String> {
    // Add each surface build here.
    // For TypeScript surfaces:
    run("npm", &["run", "build", "--workspace=surfaces/web"])
}

fn semver_check() -> Result<(), String> {
    // Only relevant if you publish the Rust SDK as a crate.
    // Skip if internal monorepo only.
    run("cargo", &["semver-checks", "check-release", "-p", "api-types"])
}

fn run(cmd: &str, args: &[&str]) -> Result<(), String> {
    let status = Command::new(cmd)
        .args(args)
        .status()
        .map_err(|e| format!("Failed to run {cmd}: {e}"))?;

    if status.success() {
        Ok(())
    } else {
        Err(format!("{cmd} exited with {status}"))
    }
}
```

### What `build-all` Guarantees

If `cargo xtask build-all` exits 0:

1. The OpenAPI schema faithfully reflects the current Rust types (because it was just derived from them).
2. The TypeScript SDK types match the schema (because they were just generated from it).
3. The Rust SDK types match the server types (because they share `api-types`).
4. Every surface compiles against the current SDK (because it was just built).
5. No semver-incompatible changes were introduced without a version bump.

If any step fails, the pipeline halts with a clear error at the exact point of failure.

---

## 6. Worktree Synchronization

When running multiple agents in parallel worktrees:

### Rule: Each worktree is self-consistent at all times.

Before an agent pushes from a worktree, it runs `cargo xtask build-all`. This guarantees the worktree's contract state is internally consistent.

On merge to main, CI runs `cargo xtask build-all` again. If Agent A changed a type in `api-types` and Agent B built a surface against the old type, the merge build fails at the surface compilation step. This is the correct behavior — it surfaces the conflict immediately as a compiler error.

### Worktree-Local Development Shortcut

For fast iteration within a single worktree, agents can run individual steps:

```bash
# Just regenerate schema + SDK types (fast, no full build)
cargo xtask gen

# Full pipeline before push
cargo xtask build-all
```

---

## 7. Breaking Change Detection

### Automated: `cargo-semver-checks`

Install: `cargo install cargo-semver-checks`

This runs against the `api-types` crate and detects:

- Removed public types or fields
- Changed field types
- New required fields on existing structs
- Removed enum variants
- Changed function signatures

It does NOT detect semantic changes (a field that changes meaning without changing type). That remains a human review responsibility.

### Integration with `xtask`

The `semver-check` step in `build-all` compares the current `api-types` against the last published/tagged version. If a breaking change is detected, the build fails unless the version in `Cargo.toml` has been bumped.

---

## 8. Migration Checklist

Execute these steps in order. Each step should be a separate commit.

### Phase 1: Extract `api-types`

- [ ] Create `crates/api-types/` with its own `Cargo.toml`
- [ ] Move all request, response, and error types from server handlers into `api-types`
- [ ] Add `#[derive(ToSchema)]` to every public type
- [ ] Add `utoipa` as a dependency of `api-types`
- [ ] Update server handlers to import from `api-types` instead of local modules
- [ ] Verify: `cargo build -p api-types` succeeds independently
- [ ] Verify: `cargo build -p server` succeeds with the new import paths

### Phase 2: Build `schema-emitter`

- [ ] Create `crates/schema-emitter/` with the binary from Section 3
- [ ] Register all types from `api-types` in the `#[openapi(components(schemas(...)))]` list
- [ ] Register all endpoint paths in the `#[openapi(paths(...))]` list
- [ ] Run the emitter: `cargo run --bin schema-emitter -- dist/openapi.json`
- [ ] Verify: the output matches (or improves on) the current manually maintained schema
- [ ] Add `dist/openapi.json` to `.gitignore` — it is now a build artifact

### Phase 3: Wire SDK Generation

- [ ] Pin `openapi-typescript` version in `package.json`
- [ ] Add generation script: `npx openapi-typescript dist/openapi.json -o sdks/typescript/src/generated/schema.d.ts`
- [ ] Add `sdks/typescript/src/generated/` to `.gitignore`
- [ ] Update surface projects to import from the SDK package
- [ ] Verify: `npm run build` in each surface succeeds against generated types
- [ ] For Rust SDK: update to depend directly on `api-types` (Option A)

### Phase 4: Build `xtask` Orchestrator

- [ ] Create `xtask/` with the implementation from Section 5
- [ ] Wire all steps into `build-all`
- [ ] Run `cargo xtask build-all` end-to-end
- [ ] Verify: introduce a deliberate breaking change in `api-types` (rename a field) and confirm the surface build fails

### Phase 5: Remove Legacy Contract Tooling

- [ ] Remove manually maintained JSON schema files
- [ ] Remove contract-checking scripts/tools
- [ ] Remove any CI steps that diff generated code
- [ ] Remove any pact or snapshot infrastructure
- [ ] Update skill contracts: strip procedural steps, keep architectural intent only

### Phase 6: CI Integration

- [ ] CI runs `cargo xtask build-all` on every PR to main
- [ ] CI runs `cargo semver-checks` if `api-types` was modified
- [ ] Optional: CI runs `cargo xtask build-all` on merge to main as a post-merge verification

---

## 9. What You Delete

After migration, these are no longer needed:

| Artifact | Reason for Removal |
|---|---|
| Manually maintained `openapi.json` / JSON schemas | Replaced by derived output from `schema-emitter` |
| Contract-checking / validation tools | Replaced by compiler. If it compiles, the contract holds. |
| Schema diff CI gates | Replaced by `cargo-semver-checks` |
| Committed generated SDK code | Generated code is a build artifact, not source |
| Procedural steps in skill contracts | Build ordering handles sequencing |

---

## 10. What You Keep

| Artifact | Why It Survives |
|---|---|
| Skill contracts (gutted to architectural intent only) | Encode design decisions agents can't infer from the compiler |
| `cargo-semver-checks` | Catches structural breaking changes the compiler alone misses |
| Integration tests (SDK against live test server) | Validates runtime serialization correctness, not just type shape |
| Human review of semantic changes | Newtypes reduce but don't eliminate semantic drift |

---

## 11. Skill Contract Template (Post-Migration)

Skills should encode **decisions**, not **procedures**. Here is the template:

```markdown
## API Type Design Rules

- Every new response type goes in `crates/api-types/src/{domain}.rs`
- Every new field on an existing response MUST be `Option<T>`
- Every type with monetary value uses `AmountCents` newtype, never raw `i64`
- Every opaque ID is a newtype (`PaymentId`, `UserId`), never raw `String`
- Every enum that consumers match on must have a `#[serde(other)] Unknown` variant
  to prevent exhaustive match breakage when new variants are added
- Error types implement `ToSchema` and are registered in the OpenAPI components

## What NOT to put in skills

- "Remember to run codegen" → the build handles this
- "Update the schema file" → the schema is derived
- "Check the contract" → the compiler checks the contract
- "Regenerate the SDK" → the build regenerates the SDK
```

---

## 12. Failure Modes This Architecture Eliminates

| Original Finding | How It Dies |
|---|---|
| Schema merge conflicts | Schema is derived, not authored. No file to conflict on. |
| CI gate latency tax | No diff gate. Enforcement is compilation, which was already running. |
| Stale pact files | No pact files. SDK types are generated fresh on every build. |
| Schema emission coupled to server build | `schema-emitter` is a standalone binary with no server dependency. |
| Breaking change detection is manual | `cargo-semver-checks` detects structural breaks automatically. |
| Codegen tool version drift | Exact version pinned in `package.json` / lockfile. |

## 13. Failure Modes That Remain (Irreducible)

| Risk | Mitigation |
|---|---|
| Semantic drift (field changes meaning, not type) | Newtypes reduce surface area. Human review remains necessary. |
| Runtime serialization bugs | Integration tests against a live test server instance. |
| Agent builds surface against stale worktree SDK | `cargo xtask build-all` before push catches this. |
| New type added to `api-types` but not registered in `schema-emitter` | Compile-time check: add a test that asserts all public types in `api-types` appear in the OpenAPI output. |