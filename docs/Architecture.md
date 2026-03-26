# Architecture

## Intent

<!-- TODO: Define nvites.me project purpose and business context in a dedicated session. -->

Stack: Rust (Actix-web) + Svelte + MySQL. Rust SDK for Tauri desktop apps, TypeScript SDK for website.

## Principles

- **sdk-only-access:** Surfaces connect to the server exclusively through SDKs. No direct DB connections or raw HTTP calls.
- **red-team-all-plans:** Implementation plans must be red-teamed before execution.
- **type-system-driven-design:** Use the Rust and TypeScript type systems to make bad state unrepresentable.
- **god-files:** Rust files that are larger than 400 LOC + tests should be decompositioned where possible or explicitly approved by the user since they place a heavy cognitive load on Claude.

## Crates

| Crate | Role |
|-------|------|
| server | Cargo workspace. `api` crate owns handlers and business logic. Sub-crates: api, database, email-template, rate-limit, postmark, schema-emitter, xtask, authorizenet, qr-frame. MySQL. |
| api-contracts | Shared types (DTOs, OpenAPI paths, security modifiers). Zero server deps. Monorepo root. |
| sdk-rust | Rust SDK for Tauri surfaces. |
| sdk-ts | TypeScript SDK for website. OpenAPI-generated types, auth/error handling. |
| cli-api-testing | API endpoint testing CLI. |

## Surfaces

| Surface | Audience | Platform | SDK |
|---------|----------|----------|-----|
| website | Public customers | Web | sdk-ts |
| command-center | Staff | Desktop (Win/macOS) | sdk-rust |
| member | Returning members | Desktop (Win/macOS) | sdk-rust |

## Mental Model

Server is the platform. Surfaces reach it only through SDKs. api-contracts is the contract boundary — types originate here and flow to server, SDKs, and surfaces.

## Build Pipeline

`cd server && cargo xtask build-all`: api-contracts → schema-emitter → dist/openapi.json → server (include_str!). Type changes in api-contracts are contract changes.

## Branching

Worktree branches → dev → staging → main. Cross-cutting on dev. Hotfixes: dev → staging → main.

## Reference Docs

| Doc | Purpose |
|-----|---------|
| `docs/RUST_STYLE_GUIDE.md` | Coding conventions for all server-side Rust |
| `docs/SVELTE_STYLE_GUIDE.md` | Svelte 5 code conventions for all surfaces |
| `docs/WEB_UX.md` | Web surface architecture, MVVM, 8-stage build workflow |
| `docs/APP_UX.md` | Tauri desktop surface architecture, IPC data flow, auth model |
| `docs/DEPLOYMENT.md` | Deployment guide — Dockerfiles, env vars, networking, database |
| `docs/DECISIONS.md` | Canonical log of promoted architectural decisions |

note: `docs` dir is symlinked

## Shop System

**product** — add-ons, gift cards, merchandise. Has `product_type_id` discriminator, category, price. CRUD at `/v1/shop/products`. FKs to `shop_status` for active/inactive state (`EntityStatus` in code). `category` is shared data table, not enum-backed.

## Payments

Authorize.Net via Accept.js (PCI SAQ-A compliant). Client-side tokenization — raw card numbers never touch the server. `PaymentNonce` carries the opaque token from client to server. Gateway integration in the `authorizenet` crate.

## Infrastructure

### Client IP Extraction

Client IP is extracted from Railway's `X-Real-IP` header (public traffic) or the BFF's `X-Real-Client-IP` header (private network). **`X-Forwarded-For` is banned** — platforms that append without stripping allow trivial spoofing.

| Traffic path | Trusted header | Why |
|-------------|---------------|-----|
| Direct (Tauri, CLI, public) | `X-Real-IP` | Set by Railway's edge proxy, documented, authoritative |
| BFF (surface-website) | `X-Real-Client-IP` | Set by BFF over Railway private network, unreachable from public internet |

**Priority:** `X-Real-IP` first, `X-Real-Client-IP` second. **Location:** `extract_client_ip()` in `server/api/src/api/validation.rs`.

**Constraint:** `ConnectionInfo::realip_remote_addr()` must not be used — it reads `X-Forwarded-For`.

### SvelteKit IP Configuration

`ADDRESS_HEADER=X-Real-IP` environment variable tells SvelteKit's `event.getClientAddress()` to read from Railway's header. The BFF sets `locals.clientIp` in `hooks.server.ts` and forwards it to the API server as `X-Real-Client-IP` via the SDK's `headers` option.

### Hosting

Server and website both deploy to Railway. Private networking via WireGuard (`http://service.railway.internal:PORT`) — zero-config service discovery, encrypted, no egress cost. Public traffic via Railway's edge proxy with auto TLS (LetsEncrypt).

## Open Questions

- Per-crate architecture files: naming convention, discovery, drift detection (leaning: standalone per-crate, no inheritance).
