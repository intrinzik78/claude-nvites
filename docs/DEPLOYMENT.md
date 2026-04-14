# Deployment Guide

Railway hosts all deployed services. Google Cloud SQL hosts the database.

## Services

| Service | Railway | Notes |
|---------|---------|-------|
| API server | `nvites-server` | Rust binary, auto TLS |
| Website | `surface-website` | SvelteKit, BFF pattern |

## Environment

See `.env.example` (when created) for required variables. Key ones:

- `DATABASE_URL` — MySQL connection string (Cloud SQL)
- `MASTER_PASSWORD` — encryption key for API secrets
- `SITE_URL` — public URL (no trailing slash)
- `CORS_ALLOWED_ORIGINS` — comma-separated allowed origins
- `PORT` — server port (Railway sets this)

## Deploy

Railway auto-deploys from `main`. Manual:

```bash
cd server && cargo xtask build-all  # verify build
git push origin main                # triggers deploy
```

## Migration Ordering

Default order: **apply pending migrations first, deploy new code second**. This is correct for additive or backward-compatible migrations (new tables, new columns, widened columns) where the old code continues to function against the new schema.

For **destructive migrations** (dropped columns, dropped tables, removed constraints), **reverse the order**: deploy the new code first, verify it's serving healthy, then apply the migration. The new code — with references to the dropped schema already removed — can safely run against either the old or the new schema; the old code, which still references the dropped schema, would fail the moment the migration lands. Reverse order keeps the vulnerable state (old binary + new schema) from ever existing.

## Database

See [MYSQL_PLAYBOOK.md](MYSQL_PLAYBOOK.md) for setup and migration procedures.
