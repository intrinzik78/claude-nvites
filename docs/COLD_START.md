# Cold Start

Getting the nvites monorepo running on a fresh machine.

## Prerequisites

- **System packages** (Debian/Ubuntu): `sudo apt install pkg-config libssl-dev` — required by `sqlx-cli` to compile against OpenSSL headers
- Rust (via rustup, stable channel)
- Node.js 24+ via corepack: `corepack enable && corepack prepare pnpm@latest --activate` (or pin a specific version — check `package.json` engines field)
- Docker (for local MySQL)
- `sqlx-cli`: `cargo install sqlx-cli --features mysql`

## Quick Start

```bash
# 1. Start MySQL
docker start mysql-local  # see MYSQL_PLAYBOOK.md for first-time setup

# 2. Create schema (first time only)
mysql -u root -p -e "CREATE DATABASE nvites;"

# 3. Run migrations
cd server && sqlx migrate run --source migrations

# 4. Install JS dependencies
cd .. && pnpm install

# 5. Build everything
cd server && cargo xtask build-all

# 6. Run the server
cargo run -p nvites-server -- dev

# 7. Install git hooks (first time only — if xtask target exists)
cd server && cargo xtask install-hooks
```

## Railway Build Variables

| Variable | Services | Purpose |
|----------|----------|---------|
| `CACHE_BUST` | server, surface-website | Forces Docker layer invalidation when Railway's cache is stale. Set to any changing value (e.g. `$RAILWAY_GIT_COMMIT_SHA` or a timestamp). Change manually when a deploy serves old code despite correct commit SHA in logs. |

## .env

The server loads environment variables via `dotenvy` (traverses up from server/). Create a `.env` file **outside** the monorepo (security — not in repo tree). Required variables documented in `server/api/src/types/env.rs`.
