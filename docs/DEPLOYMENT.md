# Deployment Guide

Railway hosts all deployed services. Google Cloud SQL hosts the database. This document captures everything learned during initial deployment setup (2026-03-19) so future sessions don't rediscover it.

---

## Architecture Overview

```
Browser → surface-website (Railway, Node) → server (Railway, Rust) → Cloud SQL (Google Cloud, MySQL 8.4)
                                          ↑ internal WireGuard network
```

- **Server:** Rust/Actix-web binary. Handles all API requests, auth, session management.
- **Website:** SvelteKit with `adapter-node`. SSR server-side load functions act as BFF, calling the server over Railway's internal network.
- **Database:** Google Cloud SQL, MySQL 8.4 LTS. Single instance, separate databases per environment when needed.

## Railway Service Configuration

### Per-Service Dockerfiles

Railway cannot auto-detect the correct language in a mixed Rust+Node monorepo. Nixpacks and Railpack both pick up Node from `package.json`/`pnpm-workspace.yaml` at the monorepo root, ignoring Rust entirely.

**What failed:**
- `railpack.json` at root with `"provider": "rust"` — works for the server but breaks the website (forces Rust globally).
- `nixpacks.toml` with `providers = ["rust"]` — Nixpacks still detected and installed Node alongside Rust. Exit code 127 (`cargo` not found) because the Rust toolchain wasn't installed correctly.
- Railpack with root directory set to `server/` — `api-contracts/` (at monorepo root) is outside the build context, breaking `cargo build`.

**What works:** Per-service Dockerfiles. No root directory set on any service. Build context is the entire repo.

### Service: Server (Rust)

| Setting | Value |
|---------|-------|
| Dockerfile | `server/Dockerfile` |
| `RAILWAY_DOCKERFILE_PATH` | `server/Dockerfile` (service env var) |
| Root directory | *(blank — must not be set)* |
| Watch paths | `server/`, `api-contracts/` |
| Custom build command | *(none — Dockerfile handles it)* |
| Custom start command | *(none — Dockerfile ENTRYPOINT handles it)* |

**Dockerfile notes:**
- Multi-stage build. Stage 1 compiles on `rust:1.92-slim-bookworm`. Stage 2 runs on `debian:bookworm-slim`.
- `dist/openapi.json` is generated during the Docker build by running `schema-emitter` before compiling the server. The `include_str!("../../../../dist/openapi.json")` in `api/src/types/open_api_doc.rs` requires this file to exist at compile time.
- Runtime image only contains the server binary and `ca-certificates` (for TLS to Cloud SQL).
- The binary takes a subcommand: `uwz-server prod` or `uwz-server dev`. `prod` auto-detects Actix workers from CPU count and uses JSON structured logging. `dev` uses 2 hardcoded workers and compact logging. The Dockerfile's `CMD ["prod"]` sets production mode by default.
- `Cargo.lock` must be copied into the build context for reproducible builds. The Dockerfile copies it from `server/Cargo.lock`.

**Required env vars (Railway service variables):**

| Var | Purpose | Example |
|-----|---------|---------|
| `PORT` | Actix bind port | `3000` |
| `IP_ADDRESS` | Actix bind address | `0.0.0.0` |
| `MASTER_PASSWORD` | AES key for api_secrets encryption | *(secret)* |
| `SERVER_MODE` | `DEVELOPMENT` / `PRODUCTION` / `MAINTENANCE` | `PRODUCTION` |
| `SHARDS` | Shard count for rate limiter + session controller | `2` |
| `DB_HOST` | Cloud SQL IP | `8.228.84.130` |
| `DB_PORT` | MySQL port | `3306` |
| `DB_USER` | Database user | *(secret)* |
| `DB_PASSWORD` | Database password | *(secret)* |
| `DB_DATABASE` | Schema name | `uwz` |
| `DB_CERT` | Raw PEM content of Cloud SQL server CA cert | *(paste full cert)* |
| `DB_MAX_CONNECTIONS` | Connection pool max | `10` |
| `DB_MIN_CONNECTIONS` | Connection pool min | `1` |
| `LIMITER_INITIAL_CAPACITY` | Rate limiter hashmap capacity (usize) | `100` |
| `LIMITER_TOKENS_PER_BUCKET` | Tokens per bucket (u32) | `100` |
| `LIMITER_INITIAL_TOKENS_PER_BUCKET` | Initial tokens per bucket (u32) | `1000` |
| `LIMITER_REFILL_RATE` | Token refill rate (f32) | `100.0` |
| `LIMITER_REFILL_WINDOW` | Refill window: `SECOND`, `MINUTE`, `HOUR`, `DAY` | `HOUR` |
| `SESSIONS_INITIAL_CAPACITY` | Session controller capacity | `100` |
| `EXTRACTOR_TEMP_DIR` | Temp file directory | `/tmp/uwz-temp` |
| `EXTRACTOR_FINAL_DIR` | Final file directory | `/tmp/uwz-final` |
| `TIMEZONE_OFFSET` | UTC offset in minutes | `-300` (Central) |
| `SITE_URL` | Public-facing site URL | `https://www.urbanwarzonepaintball.com` |
| `CORS_ALLOWED_ORIGINS` | Comma-separated origins | `https://www.urbanwarzonepaintball.com` |
| `POSTMARK_SECRET` | Postmark API key | *(secret)* |

### Service: Website (SvelteKit)

| Setting | Value |
|---------|-------|
| Dockerfile | `surface-website/Dockerfile` |
| `RAILWAY_DOCKERFILE_PATH` | `surface-website/Dockerfile` (service env var) |
| Root directory | *(blank — must not be set)* |
| Watch paths | `surface-website/`, `sdk-ts/` |

**Dockerfile notes:**
- Multi-stage build. Stage 1 builds on `node:24-slim`. Stage 2 runs on `node:24-slim`.
- `PUBLIC_*` env vars are declared as `ARG`/`ENV` pairs in the Dockerfile. SvelteKit's `$env/static/public` bakes these into the client bundle at build time. Changing any public value (phone number, address, trade name) requires a full rebuild.
- `API_BASE_URL` uses `$env/dynamic/private` — read at runtime, not baked in. This allows the same build to point at different servers.

**Required env vars (Railway service variables):**

| Var | Purpose | Example |
|-----|---------|---------|
| `PORT` | adapter-node listen port | `3000` |
| `ORIGIN` | SvelteKit CSRF origin check | `https://staging.urbanwarzonepaintball.com` |
| `API_BASE_URL` | Internal server URL | `http://uwz-server.railway.internal:3000` |
| `ADDRESS_HEADER` | SvelteKit client IP header | `X-Real-IP` |
| `PUBLIC_MODE` | Site mode (`LIVE`, `MAINTENANCE`, `DEVELOPMENT`) | `LIVE` |
| `PUBLIC_HOSTNAME` | Public URL for OG tags, etc. | `https://urbanwarzonepaintball.com` |
| `PUBLIC_TRADE_NAME` | Business display name | `Urban Warzone Paintball` |
| `PUBLIC_PHONE_NUMBER` | Display phone | *(value)* |
| `PUBLIC_PHONE_E164` | E.164 phone format | *(value)* |
| `PUBLIC_STREET_ADDRESS` | Business address | *(value)* |
| `PUBLIC_CITY` | City | *(value)* |
| `PUBLIC_STATE_LONG` | State (full) | `Texas` |
| `PUBLIC_STATE_SHORT` | State (abbr) | `TX` |
| `PUBLIC_ZIPCODE` | ZIP | *(value)* |
| `PUBLIC_COUNTRY` | Country | `US` |
| `PUBLIC_POSTHOG_ANALYTICS` | PostHog project key | *(value)* |

## Internal Networking

Railway services communicate over WireGuard private networking. **The port is required** — unlike the public edge proxy, internal DNS does not auto-route to the service's port.

```
http://<service-name>.railway.internal:<PORT>
```

The `<service-name>` is whatever you named the service in Railway's dashboard. This is not derived from the repo or Dockerfile — it's set in the Railway UI. If the server service is named `uwz-server`, the URL is `http://uwz-server.railway.internal:3000`. If renamed, the website's `API_BASE_URL` must be updated to match.

**PORT isolation:** Railway isolates ports per service. Both services can use `PORT=3000` without conflict — they run in separate containers.

The public edge proxy (`*.up.railway.app`) handles TLS termination and port routing automatically. Internal traffic is plain HTTP — encryption is provided by the WireGuard tunnel.

**Key detail:** `X-Real-IP` is only set by Railway's edge proxy on public requests. Internal (BFF → server) requests don't pass through the edge proxy, so the BFF forwards the client IP via `X-Real-Client-IP` header instead.

## Database

### Cloud SQL (MySQL 8.4)

- Instance IP is in the server's `DB_HOST` env var.
- **Authorized networks:** Railway's outbound IPs must be whitelisted in Cloud SQL → Connections → Authorized networks. Find Railway's outbound IPs in the Railway dashboard under the service's Settings → Networking. If Railway doesn't show static IPs, you may need the "Static Outbound IPs" add-on. Also whitelist your local IP for running migrations from your machine.
- **Server CA certificate:** Download from Google Cloud Console → SQL → Instance → Connections → Security → "Manage SSL mode" → download server CA cert. Or via CLI: `gcloud sql ssl server-ca-certs list --instance=<instance-name>`. Paste the full PEM content (including `-----BEGIN CERTIFICATE-----` and `-----END CERTIFICATE-----` lines) into the `DB_CERT` env var on Railway.
- **SSL modes:** The server supports:
  - `DB_CERT` env var: raw PEM content (used on Railway — no filesystem access to cert files).
  - `DB_CERT_PATH` env var: relative path to PEM file (used in local dev).
  - Neither set: SSL disabled (local Docker dev).

### Migrations

Run against Cloud SQL from your local machine:

```bash
DATABASE_URL='mysql://<user>:<password>@<host>:3306/uwz' sqlx migrate run --source server/migrations
```

**Password escaping:** Wrap the entire `DATABASE_URL` in single quotes. Special characters in the password won't be interpreted by bash. The only character that breaks single quotes is a single quote itself.

**Partial migration recovery:** If a migration fails partway, sqlx records a partial application. Fix the migration, then delete the partial row:

```sql
DELETE FROM _sqlx_migrations WHERE version = <timestamp>;
```

### MySQL 8.4 FK Constraint

MySQL 8.4 requires an explicit unique index on any column referenced by a foreign key, even if that column is the first column of a composite primary key. MySQL 8.0 allowed this implicitly via the PK's leftmost prefix.

If a future migration adds a table with a composite PK and another table's FK references just one column of it, add `UNIQUE KEY id_UNIQUE (id)` to the referenced table. This is enforced by CI (which runs MySQL 8.4).

### Environment Seed

The flattened migration `20260320000000_initial_schema.sql` includes the `system_settings` row the server requires to boot. This runs automatically with `sqlx migrate run`.

**Not covered by migrations:**

- **`api_secrets` rows.** Environment-specific, encrypted with `MASTER_PASSWORD`. Must be inserted via `cli-tako` or directly.

- **Admin user.** Created via the `bootstrap` subcommand. Add the following to your local `.env` (the same file with `DB_*` vars), then run against Cloud SQL:

  ```
  BOOTSTRAP_USERNAME=<username>
  BOOTSTRAP_PASSWORD=<password>
  BOOTSTRAP_EMAIL=<email>
  BOOTSTRAP_FNAME=<first_name>
  BOOTSTRAP_LNAME=<last_name>   # optional
  ```

  ```bash
  cargo run -p uwz-server -- bootstrap
  ```

  This creates a System user with SysAdmin permissions. It is idempotent — if a system user already exists, it prints a message and exits. Remove the `BOOTSTRAP_*` vars from `.env` after running.

  The bootstrap command connects directly to the database (no HTTP server needed) and validates inputs using the same rules as the user creation API endpoint. It must be run locally — the `BOOTSTRAP_*` vars are never set in production environments (DEC-147).

### Local Docker

```bash
docker run -d --name mysql-local -p 3306:3306 -e MYSQL_ROOT_PASSWORD=localdev -e MYSQL_DATABASE=uwz mysql:8.4
```

Reset and migrate:

```bash
cd server && cargo xtask db-reset --seed
```

## `.dockerignore`

Shared between both services (both use the monorepo root as Docker build context). Cannot exclude `surface-website/` or `sdk-ts/` because the website Dockerfile needs them. The server build context is larger than strictly necessary as a result. Not a performance concern at current repo size.

## Deployment Ordering

Server must deploy before surfaces when new request body fields are added (DEC-121). `api-contracts` types are annotated with `#[serde(deny_unknown_fields)]` — if a surface sends a field the server doesn't recognize, the request returns 400.

## Cost Estimates (per service, monthly)

| Resource | Rate |
|----------|------|
| vCPU | ~$20/vCPU |
| RAM | ~$10/GB |
| Egress | $0.10/GB |

Staging (1 vCPU / 512MB per service): ~$50/month total.
Production (2 vCPU / 1GB server + 1 vCPU / 512MB website): ~$75/month total.

Rust server idles at ~8MB RAM. Node/SvelteKit idles higher but well within 512MB.

## Troubleshooting

**Build picks up Node instead of Rust:** `RAILWAY_DOCKERFILE_PATH` is not set, or the service has a root directory configured. Remove the root directory and set the env var.

**`cargo` not found (exit 127):** Nixpacks/Railpack failed to install Rust toolchain. Switch to Dockerfile.

**`include_str!` fails for `openapi.json`:** The schema-emitter step was skipped or the `dist/` directory doesn't exist in the Docker build context. The server Dockerfile must run `cargo run --release -p schema-emitter -- dist/openapi.json` before `cargo build`.

**502 from Railway public URL:** The server isn't binding to `0.0.0.0` (set `IP_ADDRESS=0.0.0.0`), or the port doesn't match what Railway expects. Ensure `PORT` is set.

**Internal networking timeout:** Port not specified in the URL. Use `http://service.railway.internal:3000`, not `http://service.railway.internal`.

**Migration checksum mismatch:** The migration file was modified after a previous run. On a fresh database, this is fine. On an existing database, delete the row from `_sqlx_migrations` and re-run, or reset the database entirely if in dev/staging.

**`$env/static/public` build error:** `PUBLIC_*` env vars are missing during the Docker build. They must be declared as `ARG`/`ENV` pairs in the website Dockerfile. Railway automatically forwards service env vars as Docker build args when using `RAILWAY_DOCKERFILE_PATH` — so setting them as normal service variables is sufficient.

**`UserEpochNotFound` / 500 on authenticated requests after manual DB user insert:** The epoch controller loads user epochs at startup. Users inserted directly into the DB after the server started won't be in the epoch map. Restart the server, or wait for the epoch sweeper to pick them up. Users created through the API are added to the epoch map immediately.

## First Deploy Checklist

Order matters — later steps depend on earlier ones.

1. **Create Cloud SQL instance** (MySQL 8.4). Note the instance IP.
2. **Download the server CA cert** from Cloud Console. Keep the PEM content handy.
3. **Create the `uwz` database** on Cloud SQL (via Workbench, CLI, or Console).
4. **Whitelist IPs** in Cloud SQL authorized networks: Railway outbound IPs + your local IP.
5. **Run migrations** from your local machine against Cloud SQL (see Migrations section above).
6. **Bootstrap admin user** — add `BOOTSTRAP_*` vars to local `.env`, run `cargo run -p uwz-server -- bootstrap` against Cloud SQL (see Environment Seed section). Remove vars after.
7. **Insert `api_secrets`** via `cli-tako` or direct SQL.
8. **Create Railway project.** Add two services from the same repo.
9. **Name the services** deliberately — the server's name becomes the internal networking hostname.
10. **Set `RAILWAY_DOCKERFILE_PATH`** on each service (service env var, not build arg).
11. **Set all required env vars** on each service (see tables above). Ensure `API_BASE_URL` on the website matches the server's service name and port.
12. **Remove any root directory setting** on both services (must be blank).
13. **Deploy server first** (deployment ordering — server before surfaces).
14. **Verify server** — `POST /v1/sessions` with admin credentials returns 200 + access token.
15. **Deploy website.**
16. **Verify website** — hit a page that calls the server (e.g., `/book`). Check Railway logs for connection errors.
17. **Configure watch paths** per service to avoid unnecessary rebuilds.
