# Architecture

## Intent

nvites.me is a QR code marketing analytics service. Clients create campaigns with hyper-short URLs that forward users to a destination. As users pass through the gateway, we capture device, location, and timing data. Analytics are delivered as daily/weekly email digests — no dashboards required.

Target market: small businesses tracking physical and digital marketing campaigns. Solo dev project. Experimental — market fit unvalidated.

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

## Surfaces

| Surface | Audience | Platform | SDK |
|---------|----------|----------|-----|
| website | Public — campaign landing, client portal | Web | sdk-ts |
| command-center | Admin (solo dev) | Desktop (Win/macOS) | sdk-rust |
| member | Clients — real-time campaign analytics | Mobile | sdk-rust |

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

## Payments

Recurring billing for client subscriptions. Authorize.Net gateway integration in the `authorizenet` crate. PCI SAQ-A compliant — client-side tokenization via Accept.js, raw card numbers never touch the server. `PaymentNonce` carries the opaque token from client to server.

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
