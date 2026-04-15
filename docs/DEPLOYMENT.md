# Deployment Guide

Google Cloud Run hosts all services. Cloud SQL hosts the database. DNS and TLS via Cloudflare.

> **Status:** In-flight Cloud Run migration. The first deploy has not yet happened. See `docs/dispatches/CLOUD_RUN_DEPLOY_PREP.md` for phase-by-phase state and open questions.

## Scope

All deployment work runs under the dedicated `nvites` Linux user account. The primary developer user is not authorized to run gcloud commands against this project — it has no credentials for it. See [Architecture.md § Deployment Scope](Architecture.md).

**Anti-pattern:** running `gcloud`, `gsutil`, or `bq` without an explicit project specifier. Shell defaults can drift; only the inline flag (`--project=nvites-me`, `-p nvites-me`, `--project_id=nvites-me`) is authoritative. Every invocation must include one.

## Services

| Service | Cloud Run name | Custom domain | Role |
|---------|----------------|---------------|------|
| API server | `nvites-server` | `nvites.me` | Gateway (QR redirect) + API. Client-facing only via the domain; API calls from the BFF go over Cloud Run's internal routing. |
| Website | `nvites-website` | `traksent.com` | SvelteKit BFF + client portal + landing pages + marketing site. |

Region: `us-east4` (co-located with Cloud SQL).

Registry: `us-east4-docker.pkg.dev/nvites-me/nvites-containers/`.

## Database

**Cloud SQL** — MySQL 8.0, `db-f1-micro` shared-core tier, located in the `nvites-me` GCP project. Connected via the Cloud SQL Auth Proxy using the `--add-cloudsql-instances` flag; connection path is a Unix socket at `/cloudsql/<instance-connection-name>`. No VPC connector required.

See [MYSQL_PLAYBOOK.md](MYSQL_PLAYBOOK.md) for schema, migration procedures, and connection workflows.

## Key environment variables

### Server (`nvites-server`)

| Variable | Source | Value / notes |
|---|---|---|
| `DB_HOST` | env | `/cloudsql/nvites-me:us-east4:<instance-name>` (Unix socket path) |
| `DB_PORT` | env | `3306` |
| `DB_USER` | Secret Manager | `nvites` |
| `DB_PASSWORD` | Secret Manager | strong, generated fresh — not reused from other environments |
| `DB_DATABASE` | Secret Manager | `nvites` (schema name) |
| `MASTER_PASSWORD` | Secret Manager | encryption key for API secrets, ≥12 chars, generated fresh |
| `POSTMARK_SECRET` | Secret Manager | Postmark server token for the dedicated TrakSent server |
| `TRUSTED_PROXY_SECRET` | Secret Manager | shared secret gating BFF's `X-Real-Client-IP` header promotion |
| `SITE_URL` | env | `https://traksent.com` |
| `CORS_ALLOWED_ORIGINS` | env | `https://traksent.com` |
| `IP_ADDRESS` | env | `0.0.0.0` |
| `PORT` | env | set by Cloud Run automatically |
| `SHARDS` | env | `2` |
| `LIMITER_*` | env | rate limit tuning (see `env.rs`) |
| `SESSIONS_INITIAL_CAPACITY` | env | `100` |

### Website (`nvites-website`)

| Variable | Source | Value / notes |
|---|---|---|
| `ORIGIN` | env | `https://traksent.com` |
| `API_BASE_URL` | env | internal Cloud Run URL of `nvites-server`, or `https://nvites.me` for public path |
| `ADDRESS_HEADER` | env | `X-Forwarded-For` (Cloud Run default, not `X-Real-IP`) |
| `PUBLIC_HOSTNAME` | build-arg | `https://traksent.com` (baked into client bundle at build time) |
| `PUBLIC_TRADE_NAME` | build-arg | `TrakSent` |
| `PUBLIC_MODE` | build-arg | from Secret Manager at build time |
| `PUBLIC_POSTHOG_ANALYTICS` | build-arg | from Secret Manager at build time (analytics platform decision pending) |

## Deploy ceremony

Deploy skill to be ported to `.claude/skills/deploy/SKILL.md` during Phase 2 of the Cloud Run migration. Skill will enforce:

1. Apply migrations to the target schema
2. Local CI pass (`cargo xtask build-all`, tests)
3. Staging push (if a staging environment exists)
4. Build and push images (dual-tag verification: `:latest` + `:SHA`, registry tag drift check)
5. Red-team gate before deploy
6. Deploy with digest-pinned image reference (not `:latest` or `:SHA`)
7. Verify deployed revision serves healthy

Until the skill lands, follow the dispatch at `docs/dispatches/CLOUD_RUN_DEPLOY_PREP.md` step-by-step.

## Migration ordering

Default order: **apply pending migrations first, deploy new code second.** Correct for additive or backward-compatible migrations (new tables, new columns, widened columns) where the old code continues to function against the new schema.

For **destructive migrations** (dropped columns, dropped tables, removed constraints), **reverse the order**: deploy the new code first, verify it's serving healthy, then apply the migration. The new code — with references to the dropped schema already removed — can safely run against either the old or the new schema; the old code would fail the moment the migration lands. Reverse order keeps the vulnerable state (old binary + new schema) from ever existing.

## Domain setup

- `nvites.me` — DNS at Cloudflare, points at the `nvites-server` Cloud Run service via custom domain mapping. TLS managed by Cloud Run + Cloudflare.
- `traksent.com` — DNS at Cloudflare, points at the `nvites-website` Cloud Run service. TLS same pattern.

Cloud Run custom domain mappings use `gcloud run domain-mappings create`. Required DNS records (CNAME or A/AAAA, varies by domain type) are reported by gcloud at creation time — follow the instructions emitted by the command.
