# Architecture

## Intent

TrakSent is a marketing accountability service for local service businesses (HVAC, roofing, plumbing, landscaping, pest control) that spend on offline advertising — door hangers, direct mail, truck wraps, yard signs. The product tells customers which of their advertising channels bring customers.

Clients create campaigns with hyper-short URLs via the `nvites.me` gateway. QR codes printed on ad collateral route through the gateway to a hosted offer landing page on `traksent.com`, where CTA interactions (tap-to-call, form submit, email click, SMS tap) are tracked as **engagement events**. Monthly reports delivered via email break down funnel performance per channel: scans → unique visitors → engagements → engagement rate.

**Domain split:** `nvites.me` is infrastructure (gateway/redirect only, never customer-facing). `traksent.com` is the client-facing brand (website, portal, landing pages, emails, marketing).

Target market: small and medium local businesses that have never had a way to measure offline ad effectiveness. Solo dev project. Experimental — market fit unvalidated. Pricing: $99/month per campaign (1 landing page + unlimited QR codes). See `docs/PRODUCT_DIRECTION.md` for full product detail.

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

Client IP is extracted via a multi-provider priority chain in `extract_client_ip()` (`server/api/src/api/validation.rs`). Cloud Run sets `X-Forwarded-For` on all public traffic with client-controlled earlier entries; only the rightmost hop is trustworthy. Earlier providers (Cloudflare, etc.) override XFF when present.

**Priority chain** (first match wins):
1. `CF-Connecting-IP` — Cloudflare origin header (if CF fronts the service)
2. `X-Real-IP` — legacy single-value header from non-CF edge proxies
3. `Fly-Client-IP` — Fly.io edge header (unused today, portability placeholder)
4. `X-Real-Client-IP` gated by `TRUSTED_PROXY_SECRET` — BFF promotes this above XFF by proving identity via shared secret, compared with `subtle::ConstantTimeEq` for timing-safe verification
5. `X-Forwarded-For` **rightmost entry only** — GCLB/Cloud Run appends without stripping client values; only the last hop is trustworthy
6. Untrusted `X-Real-Client-IP` (header present, no trusted-proxy secret) — treated as a hint
7. `peer_addr` — direct TCP peer
8. `"unknown"` — fallback

**Constraint:** `ConnectionInfo::realip_remote_addr()` must not be used — it reads `X-Forwarded-For` leftmost, which is client-controlled.

**Environment:** `TRUSTED_PROXY_SECRET` is set only on services that accept BFF traffic; absence disables the trusted-proxy path.

### SvelteKit IP Configuration

`ADDRESS_HEADER=X-Forwarded-For` tells SvelteKit's `event.getClientAddress()` to read from Cloud Run's default client IP header. The BFF sets `locals.clientIp` in `hooks.server.ts` and forwards it to the API server as `X-Real-Client-IP` via the SDK's `headers` option, gated by `TRUSTED_PROXY_SECRET` for trusted-proxy promotion above the XFF fallback.

### Hosting

Server and website deploy to **Google Cloud Run** in the `nvites-me` GCP project, region `us-east4`. Database is Cloud SQL (MySQL 8.0) in the same project, connected via Cloud SQL Auth Proxy (`--add-cloudsql-instances` flag, Unix socket at `/cloudsql/<instance-connection-name>`). Services scale to zero when idle.

**Custom domain mapping:**
- `nvites.me` → `nvites-server` Cloud Run service (gateway only — QR redirect endpoint, never customer-facing)
- `traksent.com` → `nvites-website` Cloud Run service (client portal, landing pages, marketing site)

DNS and TLS fronted by Cloudflare for both domains.

### Deployment Scope

All deployment work runs under the dedicated `nvites` Linux user account, not the primary developer user. Separation is enforced by OS-level home directory isolation: the `nvites` user has its own `~/.config/gcloud/`, its own credential store, its own Claude Code state, and physically cannot read files in other users' home directories. This eliminates an entire class of cross-project contamination risk between this project and any sibling GCP project that may also exist on the development machine.

**Anti-pattern:** running `gcloud`, `gsutil`, or `bq` without an explicit project specifier. Shell defaults and active configurations can silently drift; only the inline flag (`--project=<id>`, `-p <id>`, `--project_id=<id>`) is authoritative. Every invocation must include one. This rule applies regardless of shell state or user awareness — the command itself must carry its target.

See `docs/DEPLOYMENT.md` for the deployment ceremony and `docs/dispatches/CLOUD_RUN_DEPLOY_PREP.md` for the in-flight Cloud Run migration.

## Open Questions

- Per-crate architecture files: naming convention, discovery, drift detection (leaning: standalone per-crate, no inheritance).
