# MySQL Local Development Playbook

Setup for the UWZ Rust + MySQL + Google Cloud SQL stack. Works in any clone or worktree.

---

## Prerequisites

- Docker (for local MySQL)
- `sqlx-cli`: `cargo install sqlx-cli --features mysql`
- `gcloud` CLI (for Cloud SQL Auth Proxy)
- MySQL Workbench (optional — visual scratch pad only)

## 1. Local MySQL via Docker

Run a local MySQL instance pinned to match your Cloud SQL version:

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

**Important**: Pin the MySQL version tag to match your Cloud SQL instance exactly. Check with:
```bash
gcloud sql instances describe INSTANCE_NAME --format='value(databaseVersion)'
```

### Lifecycle commands

```bash
docker start mysql-local    # start
docker stop mysql-local     # stop
docker rm mysql-local       # destroy (loses data)
```

## 2. Environment Files

Create a `.env` in your project root (already gitignored):

```env
DB_ENV=local
DATABASE_URL=mysql://root:localdev@127.0.0.1:3306/uwz
```

Create a `.env.example` and commit it:

```env
DB_ENV=local
DATABASE_URL=mysql://root:CHANGEME@127.0.0.1:3306/uwz
```

### Environment values

| `DB_ENV` | `DATABASE_URL` target | Notes |
|----------|----------------------|-------|
| `local`  | `127.0.0.1:3306`    | Docker container |
| `staging`| Cloud SQL via Auth Proxy | `127.0.0.1:3307` (different port) |
| `prod`   | Cloud SQL via Auth Proxy or env var | Never connect directly |

## 3. SQLx Migration Setup

### Initialize migrations directory

```bash
sqlx migrate add initial_schema
```

This creates `migrations/<timestamp>_initial_schema.sql`. Write your DDL in it.

### Run migrations

```bash
sqlx migrate run
```

SQLx reads `DATABASE_URL` from `.env` automatically.

### Check migration status

```bash
sqlx migrate info
```

### Create a new migration

```bash
sqlx migrate add <descriptive_name>
```

Convention: one logical change per file. Descriptive names: `add_projects_table`, `add_archived_at_to_users`, `create_sessions_index`.

### Reversible migrations

```bash
sqlx migrate add -r <name>
```

This creates both `<timestamp>_<name>.up.sql` and `<timestamp>_<name>.down.sql`.

## 4. SQLx Offline Mode (for CI)

> **Project note:** This project does not currently use offline mode or generate `.sqlx/`. The section below documents the general pattern for when CI is introduced.

Compile-time query checking requires a database connection. For CI builds without a database:

```bash
# After writing/changing queries, regenerate offline data:
cargo sqlx prepare

# Commit the result:
git add .sqlx/
git commit -m "update sqlx offline query data"
```

CI builds with: `SQLX_OFFLINE=true cargo build`

After merge conflicts in `.sqlx/`, always regenerate: `cargo sqlx prepare`.

## 5. Cloud SQL Connection

### Install Auth Proxy

```bash
# Download (one-time)
curl -o cloud-sql-proxy https://storage.googleapis.com/cloud-sql-connectors/cloud-sql-proxy/v2.14.3/cloud-sql-proxy.linux.amd64
chmod +x cloud-sql-proxy
```

### Connect to staging/production

```bash
# Staging (port 3307 to avoid conflict with local)
./cloud-sql-proxy --port 3307 PROJECT:REGION:INSTANCE

# Then in another terminal, with staging .env:
# DATABASE_URL=mysql://user:pass@127.0.0.1:3307/uwz
sqlx migrate run
```

### Run migrations against cloud

```bash
DATABASE_URL=mysql://user:pass@127.0.0.1:3307/uwz sqlx migrate run
```

## 6. Daily Workflow

### Starting work

```bash
docker start mysql-local        # ensure MySQL is running
sqlx migrate info               # check for pending migrations
sqlx migrate run                # apply any new migrations from git pull
```

### Making a schema change

1. Design visually in Workbench (optional scratch pad)
2. `sqlx migrate add <descriptive_name>`
3. Write the SQL in the generated file
4. `sqlx migrate run` — apply locally
5. Update Rust code to use new schema
6. `cargo sqlx prepare` — update offline query data
7. Commit: migration file + `.sqlx/` changes

### After pulling changes

```bash
sqlx migrate run                # apply any migrations from teammates/other branches
```

### Before merging a branch with migrations

1. Rebase on target branch
2. Reset local DB: `docker rm -f mysql-local` → recreate container
3. `sqlx migrate run` — verify all migrations apply cleanly from scratch
4. Test application

## 7. Deploying Schema Changes

### Deploy order matters

| Change type | Order |
|------------|-------|
| Additive (new table, new column) | Migration first, then deploy app |
| Removal (drop column, drop table) | Deploy app first (stop using it), then migration |
| Rename / type change | Multi-phase: add new → migrate data → deploy app → drop old |

### Pre-deploy checklist

- [ ] Migration tested locally on fresh DB
- [ ] `cargo sqlx prepare` run and committed
- [ ] Manual Cloud SQL backup: `gcloud sql backups create --instance=INSTANCE`
- [ ] Migration tested on staging
- [ ] Rollback plan documented

## 8. Resetting Local Database

When you need a clean slate:

```bash
docker rm -f mysql-local

docker run -d \
  --name mysql-local \
  -e MYSQL_ROOT_PASSWORD=localdev \
  -e MYSQL_DATABASE=uwz \
  -p 3306:3306 \
  mysql:8.4 \
  --character-set-server=utf8mb4 \
  --collation-server=utf8mb4_general_ci \
  --default-time-zone='+00:00'

# Wait a few seconds for MySQL to initialize, then:
sqlx migrate run

# Optionally load seed data (generic pattern — this project seeds via migrations):
# docker exec -i mysql-local mysql -u root -plocaldev uwz < server/scripts/seed_dev_data.sql
```

## 9. Safeguards

### Wrong-environment protection

The biggest risk is running destructive commands against the wrong database. Every `.env` must include `DB_ENV=local|staging|prod`.

- **Seed scripts**: must check `DB_ENV` and refuse to run unless `local`
- **Revert commands**: never run `sqlx migrate revert` without confirming which `DATABASE_URL` is active
- **Staging vs local**: use different ports (3306 local, 3307 staging proxy) so URLs are visually distinct
- **Production**: require Auth Proxy — no direct TCP access, ever

### Migration safety

MySQL DDL is **not transactional**. A failed `ALTER TABLE` cannot be rolled back. This is the single most important thing to internalize.

- **One logical change per migration file.** If it fails, you know exactly what partial state you're in.
- **Migration files are immutable once merged.** Never edit, rename, or reorder. SQLx tracks by checksum.
- **Use `IF NOT EXISTS` / `IF EXISTS`** where possible to make migrations re-runnable.
- **Destructive changes are multi-phase:**
  1. Migration A: add new column/table
  2. Deploy app using new column
  3. Migration B: backfill data
  4. Migration C: drop old column (later, after verification)

### Failed migration recovery

When a migration fails partway through (and it will, eventually):

1. Check `_sqlx_migrations` table — was the migration marked complete?
2. Inspect actual schema to see what applied vs what didn't
3. Manually fix DB to reach the intended state, OR write a fixup migration
4. If you manually fixed: insert a row into `_sqlx_migrations` to mark it as applied
5. Verify with `sqlx migrate info`

### Cloud SQL drift prevention

- **Never manually alter Cloud SQL schema.** If you must (emergency), immediately create a migration file to document the change and mark it as applied in `_sqlx_migrations`.
- **Pin MySQL versions.** Local Docker tag must match Cloud SQL version exactly. Different versions have subtle behavior differences in JSON functions, generated columns, and SQL modes.
- **Match server settings.** `character_set_server`, `collation_server`, `time_zone`, and `sql_mode` must be identical between local and cloud. The Docker command in section 1 sets these.
- **Enable Cloud SQL audit logs** to detect unauthorized schema changes.

### Credential safety

- **Never commit `.env` files.** Commit `.env.example` with dummy values only.
- **Don't commit `.mwb` files.** Workbench is a scratch pad. Migrations are the source of truth.
- **Cloud SQL Auth Proxy service account keys**: store outside the repo, `chmod 600`, add `*-key.json` to `.gitignore`.
- **Connection strings in error logs**: configure your logger to redact `DATABASE_URL` from output.

### Backup protocol

- **Cloud SQL**: enable automated backups with 7-day point-in-time recovery. Enable deletion protection.
- **Before risky migrations**: `gcloud sql backups create --instance=INSTANCE`
- **Test restores quarterly.** Untested backups are not backups.
- **Local DB is disposable.** You can always recreate from migrations + seeds. Don't rely on local data surviving.

### Offline query data (`.sqlx/`)

- **Regenerate after merges.** Run `cargo sqlx prepare` after resolving any conflicts in `.sqlx/`.
- **Never hand-edit** `.sqlx/` files.
- **CI must use `SQLX_OFFLINE=true`** — don't give CI a database connection.
- **Workflow**: write migration → run it → update Rust code → `cargo sqlx prepare` → commit all together.

### Large table migrations (production)

Migrations that touch tables with significant row counts behave differently than on local dev with 100 rows:

- **Test on staging with production-scale data** before running on prod.
- For large `ALTER TABLE` operations, consider `pt-online-schema-change` (Percona Toolkit) or `ALTER TABLE ... ALGORITHM=INPLACE`.
- Schedule during maintenance windows if table locking is expected.
