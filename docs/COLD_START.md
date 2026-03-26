# Cold Start

Getting the UWZ monorepo running on a fresh machine. Assumes Docker, Git, and a browser are already installed.

## 0. System packages

sqlx-cli needs OpenSSL headers to compile. Install before the Rust step:

```bash
# Debian/Ubuntu
sudo apt install pkg-config libssl-dev
```

## 1. Rust toolchain

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

`rust-toolchain.toml` in the repo pins the version (currently 1.92.0) — rustup will install it automatically on first build.

Install sqlx-cli:

```bash
cargo install sqlx-cli --features mysql
```

## 2. Node + pnpm

Node >= 24.4.0 (pinned in `surface-website/package.json` engines field).

pnpm is not installed globally — it's activated via corepack. This must be done before any `pnpm` commands will work:

```bash
corepack enable
corepack prepare pnpm@9.15.4 --activate
```

## 3. Clone and set up worktrees

```bash
git clone https://github.com/intrinzik78/uwz.git monorepo
cd monorepo
git checkout dev

# See docs/WORKTREE_SETUP.md for full details
mkdir -p ../worktrees
git worktree add ../worktrees/server server
git worktree add ../worktrees/surface-command-center surface-command-center
git worktree add ../worktrees/surface-website surface-website
```

## 4. Symlink claude files

The `.claude/`, `docs/`, `archive/`, and `CLAUDE.md` are symlinked from a separate repo. Set those up from your SD card / second repo before running Claude Code.

## 5. Upload directories

The server creates upload directories on startup. These must exist and be writable by your user:

```bash
sudo mkdir -p /var/data/temp && sudo chown -R $(whoami):$(whoami) /var/data
```

The paths are configured via `EXTRACTOR_TEMP_DIR` and `EXTRACTOR_FINAL_DIR` in `.env`.

## 6. Database

See `docs/MYSQL_PLAYBOOK.md` for full details. Quick version:

```bash
docker run -d \
  --name mysql-local \
  -e MYSQL_ROOT_PASSWORD=localdev \
  -e MYSQL_DATABASE=uwz \
  -p 3306:3306 \
  mysql:8.4 \
  --character-set-server=utf8mb4 \
  --collation-server=utf8mb4_general_ci \
  --default-time-zone='+00:00'
```

Wait ~10 seconds for MySQL to initialize, then:

```bash
cd server && DATABASE_URL=mysql://root:localdev@127.0.0.1:3306/uwz sqlx migrate run
```

Or create a `.env` file in the monorepo root so sqlx picks it up automatically:

```env
DB_ENV=local
DATABASE_URL=mysql://root:localdev@127.0.0.1:3306/uwz
```

## 7. Bootstrap admin user

```bash
# Set bootstrap env vars (delete from .env after use)
BOOTSTRAP_USERNAME=admin
BOOTSTRAP_PASSWORD=<your-password>
BOOTSTRAP_EMAIL=<your-email>
BOOTSTRAP_FNAME=<first-name>

cd server && cargo run -- bootstrap
```

## 8. Install git hooks

```bash
cd server && cargo xtask install-hooks
```

Installs a pre-commit hook that runs `cargo fmt --check` across all Rust crates before each commit, matching what CI enforces. Works across worktrees automatically.

## 9. Build and run

```bash
# Install all JS dependencies first (sdk-ts needs node_modules for codegen)
pnpm install

# Server (from server/)
cargo xtask build-all
cargo run

# Website (from surface-website/)
pnpm install
pnpm dev

# Command center (from surface-command-center/)
pnpm install
pnpm tauri dev
```

## 10. Optional: seed dev data

```bash
docker exec -i mysql-local mysql -u root -plocaldev uwz < server/scripts/seed_dev_data.sql
```
