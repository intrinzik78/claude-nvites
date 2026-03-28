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

## Database

See [MYSQL_PLAYBOOK.md](MYSQL_PLAYBOOK.md) for setup and migration procedures.
