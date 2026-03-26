# Cold Start

<!-- TODO: Rewrite for nvites project. Structure: system packages, Rust toolchain, Node/pnpm, Docker MySQL, .env setup, first build, seed data. -->

Getting the nvites monorepo running on a fresh machine. Assumes Docker, Git, and a browser are already installed.

## Prerequisites

- Rust (via rustup, stable channel)
- Node.js 24+ and pnpm
- Docker (for local MySQL)
- `sqlx-cli`: `cargo install sqlx-cli --features mysql`

## Quick Start

```bash
# 1. Start MySQL
docker start mysql-local  # see MYSQL_PLAYBOOK.md for first-time setup

# 2. Run migrations
cd server && sqlx migrate run --source migrations

# 3. Install JS dependencies
cd .. && pnpm install

# 4. Build everything
cd server && cargo xtask build-all
```
