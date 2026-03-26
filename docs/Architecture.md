# Architecture

## Intent

Paintball entertainment center. Software ecosystem for business operations, sales and marketing.

Stack: Rust (Actix-web) + Svelte + MySQL. Rust SDK for Tauri desktop apps, TypeScript SDK for website.

## Principles

- **sdk-only-access:** Surfaces connect to the server exclusively through SDKs. No direct DB connections or raw HTTP calls.
- **red-team-all-plans:** Implementation plans must be red-teamed before execution.
- **type-system-driven-design:** Use the Rust and TypeScript type systems to make bad state unrepresentable.
- **god-files:** Rust files that are larger than 400 LOC + tests should be decompositioned where possible or explicitly approved by the user since they place a heavy cognitive load on Claude.

## Crates

| Crate | Role |
|-------|------|
| server | Cargo workspace. `api` crate owns handlers and business logic. Sub-crates: api, database, email-template, rate-limit, postmark, schema-emitter, xtask, doc-extractor. MySQL. |
| api-contracts | Shared types (DTOs, OpenAPI paths, security modifiers). Zero server deps. Monorepo root. |
| sdk-rust | Rust SDK for Tauri surfaces. |
| sdk-ts | TypeScript SDK for website. OpenAPI-generated types, auth/error handling. |
| cli-idropr | Photo album upload CLI. |
| cli-tako | API secrets manager CLI. |
| cli-api-testing | API endpoint testing CLI. |

## Surfaces

| Surface | Audience | Platform | SDK |
|---------|----------|----------|-----|
| website | Public customers | Web | sdk-ts |
| command-center | Staff on-site | Desktop (Win/macOS) | sdk-rust |
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
| `docs/STARTUP_GATES.md` | Go-live prerequisites and deployment gate checklist |
| `docs/DEPLOYMENT.md` | Railway deployment guide — Dockerfiles, env vars, networking, database, troubleshooting |
| `docs/DECISIONS.md` | Canonical log of promoted architectural decisions |

note: `docs` dir is symlinked

## Shop System

Two product domains serve different purposes:

- **booking_product** — time-slot packages (e.g. "Birthday Blast 2hr"). Links to `resource_type`, has duration/guest limits, drives the availability engine. CRUD at `/v1/products`.
- **product** — add-ons, gift cards, merchandise. Has `product_type_id` discriminator, category, price. No time-slot or availability coupling. CRUD at `/v1/shop/products`.

Both FK to `shop_status` for active/inactive state (`EntityStatus` in code, DEC-056). `category` is shared across both (seeded data table, not enum-backed).

**Booking add-ons** (`booking_addon`) link a booking to a product with quantity + price snapshot (DEC-002). Endpoints at `/v1/bookings/{uuid}/addons`.

**Current phase:** Phase 1 — product catalog + booking add-ons (7 endpoints). Cart, orders, payments, gift card redemption deferred to Phase 2. See DEC-038.

## Infrastructure

### Client IP Extraction (DEC-141)

Client IP is extracted from Railway's `X-Real-IP` header (public traffic) or the BFF's `X-Real-Client-IP` header (private network). **`X-Forwarded-For` is banned** — platforms that append without stripping allow trivial spoofing.

| Traffic path | Trusted header | Why |
|-------------|---------------|-----|
| Direct (Tauri, CLI, public) | `X-Real-IP` | Set by Railway's edge proxy, documented, authoritative |
| BFF (surface-website) | `X-Real-Client-IP` | Set by BFF over Railway private network (`service.railway.internal`), unreachable from public internet |

**Priority:** `X-Real-IP` first, `X-Real-Client-IP` second. Railway serves public and private traffic on the same application port (private network is DNS-based via WireGuard). An attacker can send `X-Real-Client-IP` on a public request — checking `X-Real-IP` first ensures Railway's authoritative header always wins on public traffic. When `X-Real-IP` is absent (private network path, no edge proxy), `X-Real-Client-IP` is used.

**Location:** `extract_client_ip()` in `server/api/src/api/validation.rs`. Called by rate limit middleware and all audit/rate-limit handler sites.

**Constraint:** `ConnectionInfo::realip_remote_addr()` must not be used — it reads `X-Forwarded-For`.

### SvelteKit IP Configuration

`ADDRESS_HEADER=X-Real-IP` environment variable tells SvelteKit's `event.getClientAddress()` to read from Railway's header. The BFF sets `locals.clientIp` in `hooks.server.ts` and forwards it to the API server as `X-Real-Client-IP` via the SDK's `headers` option.

### Hosting

Server and website both deploy to Railway. Private networking via WireGuard (`http://service.railway.internal:PORT`) — zero-config service discovery, encrypted, no egress cost. Public traffic via Railway's edge proxy with auto TLS (LetsEncrypt).

## Open Questions

- Photo experience architecture for the website.
- Per-crate architecture files: naming convention, discovery, drift detection (leaning: standalone per-crate, no inheritance).
