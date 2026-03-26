---
name: db-start
description: Start local MySQL Docker container and verify database readiness. Run before building or running the server.
---

Start the local MySQL development database. Reference `docs/MYSQL_PLAYBOOK.md` for the canonical setup, but use these hardcoded local-dev values:

- Container: `mysql-local`
- Image: `mysql:8.0.35`
- Credentials: `root` / `localdev`
- Database: `uwz`
- Port: `3306`
- DATABASE_URL: `mysql://root:localdev@127.0.0.1:3306/uwz`

## Steps

1. **Check container state:**
   ```bash
   docker ps -a --filter "name=mysql-local" --format "{{.Names}} {{.Status}}"
   ```
   - **Running** → skip to step 3
   - **Exists but stopped** → `docker start mysql-local`, continue to step 2
   - **Does not exist** → create it:
     ```bash
     docker run -d \
       --name mysql-local \
       -e MYSQL_ROOT_PASSWORD=localdev \
       -e MYSQL_DATABASE=uwz \
       -p 3306:3306 \
       mysql:8.0.35 \
       --character-set-server=utf8mb4 \
       --collation-server=utf8mb4_unicode_ci \
       --default-time-zone='+00:00'
     ```
     A fresh container needs ~15 seconds to initialize. Continue to step 2.

2. **Wait for MySQL to accept connections** (max 30 seconds):
   ```bash
   for i in $(seq 1 30); do
     docker exec mysql-local mysqladmin ping -u root -plocaldev --silent 2>/dev/null && break
     sleep 1
   done
   ```
   If it doesn't respond after 30 seconds, report the failure and suggest checking `docker logs mysql-local`.

3. **Check migration status** from the monorepo root:
   ```bash
   DATABASE_URL=mysql://root:localdev@127.0.0.1:3306/uwz sqlx migrate info --source server/migrations/
   ```
   Report the output. Do **not** auto-run migrations — let the user decide.

4. **Report status:**
   - Container state (created / started / already running)
   - MySQL connection (confirmed / failed)
   - Pending migrations (count, or "all applied")
   - If migrations are pending, suggest: `DATABASE_URL=mysql://root:localdev@127.0.0.1:3306/uwz sqlx migrate run --source server/migrations/`

$ARGUMENTS
