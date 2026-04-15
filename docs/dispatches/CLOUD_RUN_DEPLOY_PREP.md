# Cloud Run Deploy Prep

**Branch:** dev
**Date:** 2026-04-15 (revised from 2026-04-14)
**Deploy target:** 2026-05-30
**Status:** Phase 0 complete (committed 2026-04-14). Phases 1–4 pending. Separation architecture decided 2026-04-15; dispatch fully revised.

---

## Setup — read this first if resuming cold

This dispatch is the authoritative starting point for the Cloud Run migration. The following structural decisions landed on 2026-04-15 and supersede earlier versions of this document:

1. **TrakSent is the client-facing brand.** `traksent.com` is the customer-facing domain (website, portal, landing pages, emails, marketing). `nvites.me` is infrastructure only — the QR code redirect gateway, never customer-visible. See `docs/PRODUCT_DIRECTION.md` for the product framing.
2. **Nvites has its own Cloud SQL instance.** The original plan to share `idropr-dev:us-east4:uwz-sandbox` via cross-project IAM has been abandoned. Nvites uses `db-f1-micro` in the `nvites-me` GCP project. Cost: ~$10–12/mo. Eliminates catastrophic blast radius of shared DB.
3. **Nvites deployment runs under a dedicated `nvites` Linux user.** Not the primary developer account. The user has its own `~/.config/gcloud/`, its own Claude Code state, its own credential store, and physically cannot read files in other users' home directories. This makes cross-project contamination structurally impossible rather than discipline-dependent.
4. **No persistent `uwz-ref` symlink or directory.** UWZ reference files are brought in via an explicit **alignment session** pattern (see below) only when porting patterns from UWZ. They are transient artifacts, never committed, and never persist between sessions.
5. **Separate Postmark server inside the existing Postmark account.** Nvites has its own sender signature for `traksent.com` and its own suppression/bounce state. Shares account-level billing.
6. **gcloud anti-pattern: every command must carry its project flag.** `gcloud`, `gsutil`, and `bq` invocations without `--project=nvites-me` (or equivalent) are banned. Shell defaults and active configurations can drift; only the inline flag is authoritative. This rule is reinforced at every level — `CLAUDE.md`, `docs/Architecture.md`, `docs/DEPLOYMENT.md`, and the `deploy` skill when it lands.

---

## Why

The nvites repo was template-copied from UWZ and has never been deployed. Deploy infrastructure was partially present (Dockerfiles exist) but triple-broken from the copy. This dispatch directs the work to reach a working first deploy to Google Cloud Run in a new, isolated GCP project, with zero cross-contamination against UWZ infrastructure.

**Primary safety invariant:** no change may leave UWZ-specific identifiers anywhere that would cause nvites code or artifacts to push against UWZ infrastructure. Verify with grep after every slice.

---

## What was done in Phase 0 (committed 2026-04-14)

- **`0214961` Remove SERVER_MODE env var and ServerMode enum** — granular service flags in `system_settings` cover runtime gating. Mirror of uwz migration.
- **`7193b85` Extract client IP via multi-provider priority chain** — replaces the Railway-era 2-header function with CF-Connecting-IP → X-Real-IP → Fly-Client-IP → trusted-proxy → X-Forwarded-For rightmost → untrusted X-Real-Client-IP → peer_addr. Added `TRUSTED_PROXY_SECRET` + `subtle::ConstantTimeEq`. 143 tests pass.
- **`8a8568b` Purge UWZ from Dockerfiles and alert templates**:
  - `server/Dockerfile` — 5-stage cargo-chef build with `nvites-server` package name and correct nvites crate list (api, authorizenet, database, email-template, postmark, qr-frame, rate-limit, schema-emitter, xtask). Removed anthropic, doc-extractor. Dropped Railway CACHE_BUST.
  - `surface-website/Dockerfile` — stripped UWZ defaults (`PUBLIC_HOSTNAME`, `PUBLIC_TRADE_NAME`). Reduced 12 ARGs to 5. CACHE_BUST removed.
  - `system_alert/v1/en.text` and `en.mjml` footer updated.

### Decisions locked in (apply across all phases)

| Decision | Value | Why |
|---|---|---|
| GCP project | `nvites-me` (project number `1083207796199`, already provisioned) | IAM blast radius, billing clarity, scaling isolation, easier spin-off |
| Cloud SQL | **Separate `db-f1-micro` in `nvites-me` project**, MySQL 8.0 | Structural isolation from UWZ data. ~$10–12/mo is cheap insurance. No cross-project IAM complexity. |
| Cloud SQL connection path | `--add-cloudsql-instances` (built-in proxy) | Unix socket, no VPC connector needed |
| Region | `us-east4` | Standard, co-located with Cloud SQL |
| Artifact Registry | `nvites-containers` repo in `nvites-me` project | Separate project → separate registry naturally |
| GCS | Separate nvites buckets in `nvites-me` project (when needed) | Clean separation; nvites may not need media hosting early |
| Client domain | `traksent.com` (owned, DNS at Cloudflare) | Client-facing brand |
| Gateway domain | `nvites.me` (owned) | Gateway/redirect only, never customer-facing |
| Trade name | `TrakSent` | Client-facing brand string |
| Phone number | dropped from website client bundle | Not needed at launch |
| Cookie name | `traksent_token` | Symmetric with prior project naming convention |
| Email domain | `{address}@traksent.com` | All transactional mail verified and signed for traksent.com |
| Postmark | Separate server inside existing Postmark account, new sender signature for `traksent.com` | Isolates nvites suppression/bounce state from UWZ's |
| Analytics platform | **Deferred** — PostHog vs GA4 decision pending | Not blocking Phase 1–4; `PUBLIC_POSTHOG_ANALYTICS` can be set empty or placeholder at first deploy |
| Timezone strategy | UTC server-side, per-customer IANA tz string at render time | Multi-tenant service across US timezones; single server-level offset is wrong at category level. Implementation deferred until customer/campaign schema work. |
| `TIMEZONE_OFFSET` env var | **Eliminate** | Replaced by per-customer tz; legacy from UWZ template |
| `PUBLIC_TRADE_NAME` | `TrakSent` | Brand decision made 2026-04-15 |
| IP extraction | Multi-provider chain with `TRUSTED_PROXY_SECRET` | Cloud Run (`X-Forwarded-For` rightmost), CF migration readiness, BFF trust |
| Website `PUBLIC_*` vars | 4 confirmed: `PUBLIC_MODE`, `PUBLIC_HOSTNAME`, `PUBLIC_TRADE_NAME`, `PUBLIC_POSTHOG_ANALYTICS` | Reduced from UWZ's 15. Dropped `PUBLIC_PHONE_NUMBER` (not needed at launch). |

### Open questions

Only one remains:

1. **Analytics platform: PostHog vs GA4.** Not blocking the first deploy — `PUBLIC_POSTHOG_ANALYTICS` can be set empty or with a placeholder value and wired up once a decision lands. Separate design conversation, deferred.

---

## Separation architecture

### The `nvites` Linux user model

All nvites deployment work runs under a dedicated Linux user account (`nvites`). The primary developer account has no credentials for this project's GCP resources. The separation is enforced at the OS level — the `nvites` user has its own `$HOME`, its own `~/.config/gcloud/`, its own credential store, its own Claude Code state, and physically cannot read files in other users' home directories (default $HOME mode 700).

**Workflow:**
1. In a tmux pane: `su - nvites` once at the top
2. From the resulting shell: `cd ~/programming/nvites-me/monorepo && claude`
3. All subsequent work in that pane inherits the nvites user context

**What this eliminates structurally:**
- No shared `~/.config/gcloud/active_config` file between UWZ and nvites work — the two users have physically separate gcloud state directories
- No shared credential store — `gcloud auth login` under one user does not affect the other
- No shared Claude Code memory/settings — nvites Claude sessions load no UWZ context because there's no UWZ content in the nvites user's filesystem to load
- No shared shell history, no shared dotfiles, no file read access across user boundaries

**What it does not eliminate** (residual shared state):
- Docker daemon socket (if the nvites user is in the `docker` group). Mitigation: build scripts hard-code the `nvites-containers` registry path with no variable substitution from env.
- X display, if running GUI apps. Not relevant for CLI-only workflows.

### Alignment session pattern (for porting from UWZ)

When work genuinely requires reading UWZ reference files — specifically Phase 1 (build script port) and Phase 2 (deploy skill port) — use this explicit pattern:

1. **Declare the alignment session.** In the Claude prompt at the start of the session, say something like: "this is an alignment session — we're porting [specific artifact] from UWZ." The session is opt-in and explicitly scoped.
2. **Human prepares a transient reference directory.** Outside the Claude session, the developer (acting as whichever user has access to the UWZ repo) copies the specific files needed into `/tmp/uwz-alignment/` with world-readable permissions:
   ```
   mkdir -p /tmp/uwz-alignment
   chmod 755 /tmp/uwz-alignment
   cp /path/to/uwz/scripts/build-server.sh /tmp/uwz-alignment/
   cp /path/to/uwz/scripts/build-website.sh /tmp/uwz-alignment/
   cp /path/to/uwz/docs/DEPLOYMENT.md /tmp/uwz-alignment/
   chmod -R a+r /tmp/uwz-alignment
   ```
3. **Nvites Claude session reads from the transient dir.** During the alignment session, Claude reads the reference files from `/tmp/uwz-alignment/`, ports them with substitutions into the nvites repo, and commits the ported artifacts.
4. **Human removes the transient dir at session end.** `rm -rf /tmp/uwz-alignment/` once the port is verified. The nvites user's filesystem never retains UWZ reference files.

**What this pattern preserves:**
- No `uwz-ref` symlink living in the repo across sessions
- No UWZ files in the nvites user's $HOME at rest
- Alignment work is explicit (marked in the session, logged in the handoff), not implicit
- The nvites Claude session still operates within its normal scope — it just has permission to read one specific `/tmp` directory during the alignment

---

## Pre-requisites checklist (must be true before Phase 1)

- [ ] The `nvites` Linux user exists (`useradd -m -s /bin/bash nvites`)
- [ ] The nvites user is authenticated to GCP: `gcloud auth login` as `josh@idropr.com` completed inside `su - nvites`
- [ ] A gcloud configuration named `traksent` (or equivalent) exists with `project=nvites-me` set
- [ ] `gcloud projects describe nvites-me --project=nvites-me` returns the project (project number `1083207796199`)
- [ ] The nvites user has cloned the repo: `/home/nvites/programming/nvites-me/monorepo/`
- [ ] `cd server && cargo xtask build-all` passes inside the nvites user's shell
- [ ] `cargo test -p nvites-server` passes inside the nvites user's shell
- [ ] The nvites user has its own git credentials (SSH key added to GitHub account, or HTTPS credentials cached)
- [ ] Claude Code is installed and configured in the nvites user's environment
- [ ] `gcloud config list --project=nvites-me` shows `josh@idropr.com` account and `nvites-me` project
- [ ] The previous nvites clone under the primary dev user's home has been removed (verify no `/home/<dev>/programming/nvites-me/` remains)

---

## Phase 1 — Build scripts

**Alignment session required.** Port `scripts/build-server.sh` and `scripts/build-website.sh` from UWZ reference.

### Reference files needed in `/tmp/uwz-alignment/`

- `build-server.sh` — server build script template (dual-tag verification, registry check, digest-pinned deploy command emission, 3 exit codes)
- `build-website.sh` — website build script template (secret fetch from Secret Manager before docker build, hardcoded business info as build-args)
- `check-image-refs.sh` — website pre-deploy image reference verifier (skip this one; nvites doesn't have GCS media delivery yet)

### Gotchas from uwz build scripts — preserve in nvites versions

These are field-tested. Do not drop them when porting:

1. **Dual-tag verification** — both `:latest` and `:SHA` tagged; verify local tags point at the same image ID AFTER build AND in the registry AFTER push. Catches `:latest` drift.
2. **`gcloud --filter=tag=` is broken** — gcloud's filter expression warns "does not currently match but will in the future." Parse unfiltered output with awk instead.
3. **Three exit codes**: `0` = success or user-declined-push, `1` = build or local-tag-mismatch failure, **`2` = push succeeded but registry `:latest` did not update — DO NOT DEPLOY**.
4. **Digest-pinned deploy command emission** — print `gcloud run deploy ... --image=...@sha256:<digest> --project=nvites-me` at the end. Immune to tag drift. Never construct the deploy command by hand.
5. **Non-interactive graceful exit** — if stdin isn't a TTY and `--push` flag is absent, skip push cleanly.
6. **Website script: secret fetch before docker build** — SvelteKit `$env/static/public` vars are baked into the client bundle at build time, so secrets must exist when `docker build` runs. Fetch from Secret Manager via gcloud, pass as `--build-arg`.
7. **Hardcoded business info in website script** — brand/trade name are hardcoded in `build-website.sh`, not stored as secrets. Secrets rotate; brand strings don't.
8. **Every gcloud command in the script must include `--project=nvites-me`.** No exceptions. Catch the anti-pattern before it reaches a live script.

### `scripts/build-server.sh`

Adapt from the reference. Substitutions:

- `uwz-server` → `nvites-server`
- `uwz-containers` → `nvites-containers`
- `idropr-dev` → `nvites-me`
- Keep `us-east4` (same region)
- **Add `--project=nvites-me` to every gcloud invocation** even if the shell has it as default
- Keep the entire verification and tagging structure verbatim

Verification: after writing, `./scripts/build-server.sh` (without `--push`) must build the image locally and exit 0 without pushing. Grep-verify the script is clean of UWZ identifiers:

```
grep -E "uwz|urbanwarzone|idropr" scripts/build-server.sh
```

Must return empty.

### `scripts/build-website.sh`

Adapt from the reference. Substitutions:

- `uwz-website` → `nvites-website`
- `uwz-containers` → `nvites-containers`
- `idropr-dev` → `nvites-me`
- **Secret fetches: reduce to 2** — keep `PUBLIC_MODE`, `PUBLIC_POSTHOG_ANALYTICS`; drop any Accept.js secrets
- **Hardcoded build-args: 3** — `PUBLIC_HOSTNAME=https://traksent.com`, `PUBLIC_TRADE_NAME=TrakSent`, dropped `PUBLIC_PHONE_NUMBER`
- Drop address/locale build-args not used by nvites client bundle
- **Add `--project=nvites-me` to every gcloud invocation**
- Keep verification and tagging structure verbatim

Verification: same pattern. `grep -E "uwz|urbanwarzone|idropr" scripts/build-website.sh` must return empty after writing.

### `scripts/check-image-refs.sh`

**SKIP.** Not relevant until nvites adopts a GCS-media-delivery pattern.

---

## Phase 2 — Adopt the `deploy` skill

**Alignment session required.** Port `SKILL.md` from UWZ reference into `.claude/skills/deploy/SKILL.md`.

Substitutions:

- `uwz-server` → `nvites-server`
- `uwz-website` → `nvites-website`
- `idropr-dev` → `nvites-me`
- **Remove any UWZ-specific enforcement** (e.g., if the reference cites a UWZ-specific DEC, remove or replace with the equivalent nvites constraint)
- Cloud Run service URLs stay as `<TBD>` placeholders until after Phase 4 populates them
- **Every gcloud command example in the skill must show the `--project=nvites-me` flag** — the skill is itself a reference that future sessions will read; it must model the anti-pattern correctly
- Keep the 7-step ceremony: migrations → local CI → staging push → build/push → red team → deploy → verify
- Keep the gotcha discipline (dual-tag verification, exit code 2 = don't deploy, digest-pinned deploy command)

**Required skill content: gcloud scope reminder.** The skill must open with a restatement of the gcloud anti-pattern. This is the fourth reinforcement point (after CLAUDE.md, Architecture.md, DEPLOYMENT.md). Deploy is the most dangerous context, so the rule is stated first.

Verification: skill must grep clean for UWZ refs:

```
grep -E "uwz|urbanwarzone|idropr" .claude/skills/deploy/SKILL.md
```

Must return empty.

---

## Phase 3 — GCP provisioning

One-time setup. Most commands require the user running them interactively. Every command includes an explicit project flag.

### Known state

- **Project**: `nvites-me`, project number `1083207796199`, already created 2026-04-14 18:27 UTC, lifecycle ACTIVE
- **Account**: `josh@idropr.com`, authenticated

### Commands (run as `nvites` user, inside `su - nvites`)

1. **Enable APIs**:
   ```
   gcloud services enable \
     run.googleapis.com \
     cloudbuild.googleapis.com \
     artifactregistry.googleapis.com \
     sqladmin.googleapis.com \
     secretmanager.googleapis.com \
     billingbudgets.googleapis.com \
     --project=nvites-me
   ```

2. **Create Artifact Registry repo**:
   ```
   gcloud artifacts repositories create nvites-containers \
     --repository-format=docker \
     --location=us-east4 \
     --project=nvites-me
   ```

3. **Configure Docker auth** (per-user, runs as the nvites user):
   ```
   gcloud auth configure-docker us-east4-docker.pkg.dev --project=nvites-me
   ```

4. **Create Cloud SQL instance** (`db-f1-micro`, MySQL 8.0, `us-east4`):
   ```
   gcloud sql instances create nvites-db \
     --database-version=MYSQL_8_0 \
     --tier=db-f1-micro \
     --region=us-east4 \
     --storage-size=10GB \
     --storage-type=SSD \
     --backup-start-time=03:00 \
     --project=nvites-me
   ```

5. **Set the root password**:
   ```
   gcloud sql users set-password root \
     --host=% \
     --instance=nvites-db \
     --password=<strong-password> \
     --project=nvites-me
   ```

6. **Create nvites database and scoped user** (via `gcloud sql connect nvites-db --user=root --project=nvites-me`, then at mysql prompt):
   ```sql
   CREATE DATABASE nvites CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
   CREATE USER 'nvites'@'%' IDENTIFIED BY '<strong-password>';
   GRANT ALL ON nvites.* TO 'nvites'@'%';
   FLUSH PRIVILEGES;
   ```

   Note: the `nvites` MySQL user is scoped to the `nvites` schema only (`nvites.*`, not `*.*`). Even though this is a dedicated Cloud SQL instance, scope the grants narrowly.

7. **Populate Secret Manager**:
   ```
   printf "nvites" | gcloud secrets create DB_USER --data-file=- --project=nvites-me
   printf "<password>" | gcloud secrets create DB_PASSWORD --data-file=- --project=nvites-me
   printf "nvites" | gcloud secrets create DB_DATABASE --data-file=- --project=nvites-me
   printf "<master>" | gcloud secrets create MASTER_PASSWORD --data-file=- --project=nvites-me
   printf "<postmark>" | gcloud secrets create POSTMARK_SECRET --data-file=- --project=nvites-me
   openssl rand -base64 32 | gcloud secrets create TRUSTED_PROXY_SECRET --data-file=- --project=nvites-me
   printf "LIVE" | gcloud secrets create PUBLIC_MODE --data-file=- --project=nvites-me
   printf "" | gcloud secrets create PUBLIC_POSTHOG_ANALYTICS --data-file=- --project=nvites-me
   ```

   Generate passwords fresh. Do not reuse passwords from other projects. `MASTER_PASSWORD` must be ≥12 chars.

8. **Grant Cloud Run SA access to each secret**:
   ```
   for SECRET in DB_USER DB_PASSWORD DB_DATABASE MASTER_PASSWORD POSTMARK_SECRET TRUSTED_PROXY_SECRET PUBLIC_MODE PUBLIC_POSTHOG_ANALYTICS; do
     gcloud secrets add-iam-policy-binding $SECRET \
       --member="serviceAccount:1083207796199-compute@developer.gserviceaccount.com" \
       --role="roles/secretmanager.secretAccessor" \
       --project=nvites-me
   done
   ```

9. **Apply migrations against nvites schema** (from inside the nvites user's repo, via `cloud-sql-proxy` on a separate port):
   ```
   cloud-sql-proxy --port 3307 nvites-me:us-east4:nvites-db &
   DATABASE_URL='mysql://nvites:<password>@127.0.0.1:3307/nvites' \
     sqlx migrate run --source server/migrations
   kill %1
   ```

10. **Set up Postmark server** (manual, via Postmark web UI, not gcloud):
    - New server inside existing Postmark account, name: "TrakSent"
    - Sender signature: `<address>@traksent.com`, with DNS records (SPF, DKIM, Return-Path) added to Cloudflare for `traksent.com`
    - Copy the server token, store in Secret Manager as `POSTMARK_SECRET`

11. **DNS at Cloudflare** (manual):
    - `nvites.me` — CNAME or A/AAAA record pointing at `nvites-server` Cloud Run service (records emitted by `gcloud run domain-mappings create`)
    - `traksent.com` — same pattern pointing at `nvites-website` Cloud Run service
    - `_domainkey.traksent.com`, SPF TXT, DMARC TXT — per Postmark sender signature requirements

12. **Optional: billing budget alert** (recommended: $50/mo soft cap for a zero-traffic dev project):
    ```
    gcloud billing budgets create \
      --billing-account=<billing-account-id> \
      --display-name="nvites-me monthly cap" \
      --budget-amount=50USD \
      --threshold-rule=percent=50 \
      --threshold-rule=percent=75 \
      --threshold-rule=percent=100 \
      --project=nvites-me
    ```

---

## Phase 4 — First deploy ceremony

Use the adopted deploy skill. Specific values:

- **Cloud Run services**: `nvites-server`, `nvites-website`
- **Registry**: `us-east4-docker.pkg.dev/nvites-me/nvites-containers/`
- **VPC connector**: NONE (using `--add-cloudsql-instances`)
- **Cloud SQL flag**: `--add-cloudsql-instances=nvites-me:us-east4:nvites-db`
- **DB_HOST**: `/cloudsql/nvites-me:us-east4:nvites-db` (Unix socket path)

### Server env vars

```
IP_ADDRESS=0.0.0.0
SHARDS=2
LIMITER_INITIAL_CAPACITY=100
LIMITER_TOKENS_PER_BUCKET=100
LIMITER_INITIAL_TOKENS_PER_BUCKET=1000
LIMITER_REFILL_RATE=100.0
LIMITER_REFILL_WINDOW=HOUR
SESSIONS_INITIAL_CAPACITY=100
SITE_URL=https://traksent.com
CORS_ALLOWED_ORIGINS=https://traksent.com
DB_HOST=/cloudsql/nvites-me:us-east4:nvites-db
DB_PORT=3306
```

`TIMEZONE_OFFSET` is dropped — server operates in UTC, per-customer IANA tz is stored at the customer level (implementation deferred until customer/campaign schema work).

### Server secrets (bound via `--set-secrets`)

`DB_USER`, `DB_PASSWORD`, `DB_DATABASE`, `MASTER_PASSWORD`, `POSTMARK_SECRET`, `TRUSTED_PROXY_SECRET`

### Website env vars

```
ORIGIN=https://traksent.com
API_BASE_URL=<internal Cloud Run URL of nvites-server>
ADDRESS_HEADER=X-Forwarded-For
```

### Website build-args (hardcoded in `build-website.sh`)

```
PUBLIC_HOSTNAME=https://traksent.com
PUBLIC_TRADE_NAME=TrakSent
PUBLIC_MODE (from Secret Manager)
PUBLIC_POSTHOG_ANALYTICS (from Secret Manager, can be empty for first deploy)
```

### Custom domain mapping

```
gcloud run domain-mappings create \
  --service=nvites-server \
  --domain=nvites.me \
  --region=us-east4 \
  --project=nvites-me

gcloud run domain-mappings create \
  --service=nvites-website \
  --domain=traksent.com \
  --region=us-east4 \
  --project=nvites-me
```

Follow the DNS record instructions emitted by each command.

---

## Pre-deploy contamination checklist

**BLOCKER — production-visible UWZ leaks. MUST address before Phase 4.**

- [ ] **`server/api/src/enums/email_id.rs`**: 6 hardcoded `@urbanwarzonepaintball.com` email "from" addresses returned by `EmailID::from_address()`. Used for outbound email via Postmark. Update the existing template addresses to `@traksent.com` equivalents. Most templates (`BookingConfirmation`, `QueuePendingConfirmation`, `WaiverConfirmation`, `BookingCancellation`) are UWZ-specific and will eventually be deleted when nvites has its own template set — for now, preserve the template infrastructure and change only the domain portion. Minimum for deploy: no `@urbanwarzonepaintball.com` address remains in this file.
- [ ] **`surface-website/static/robots.txt`**: update `Sitemap:` URL to `https://traksent.com/sitemap.xml`.
- [ ] **Cookie name** (5 files): `surface-website/src/hooks.server.ts`, `(auth)/login/+page.server.ts`, `portal/logout/+page.server.ts`, `portal/profile/+page.server.ts`, `lib/api/handleLoadError.ts`. Replace `uwz_token` with `traksent_token`.
- [ ] **`surface-website/src/lib/components/SeoHead.svelte`**: `TITLE_SUFFIX = ' | UWZ Paintball'` → `' | TrakSent'`.
- [ ] **`surface-website/src/routes/(auth)/+layout.svelte`**: `UWZ: BE THE HERO` brand string and `aria-label="UWZ home"`. Rewrite for TrakSent.
- [ ] **Page titles in 4 files**: `(auth)/login/+page.svelte`, `(auth)/register/+page.svelte`, `portal/profile/+page.svelte`, `portal/orders/+page.svelte`. Replace `| UWZ` → `| TrakSent`.
- [ ] **`surface-website/src/routes/(public)/about/+page.svelte`**: ~4 UWZ brand/story references. Rewrite for TrakSent OR remove the page entirely (it's a UWZ template, not TrakSent content).

**NON-BLOCKER but should clean up eventually:**

- [ ] `server/qr-frame/src/types/generator.rs` lines 124, 136, 147, 161, 164, 186, 191: test fixture URLs use `https://urbanwarzonepaintball.com/...`. Replace with `https://traksent.com/test` or `https://example.com/test`.
- [ ] `server/postmark/src/types/postmark.rs` lines 73, 78–80: test fixtures with `contact@urbanwarzonepaintball.com`. Replace with `test@example.com`.

**Completed in Phase 0 (for reference):**

- ✅ `server/Dockerfile`
- ✅ `surface-website/Dockerfile`
- ✅ `server/email-template/.../system_alert/v1/en.text`
- ✅ `server/email-template/.../system_alert/v1/en.mjml`

---

## Next session starting checklist

**If resuming under the `nvites` Linux user:**

1. Run `/orient`
2. Read this dispatch (`docs/dispatches/CLOUD_RUN_DEPLOY_PREP.md`)
3. Verify the pre-requisites checklist at the top of this dispatch is complete
4. Verify state:
   - `git log -5` should show the Phase 0 commits plus the 2026-04-15 pivot commits
   - `cd server && cargo xtask build-all` should pass
   - `cd server && cargo test -p nvites-server` should pass
   - `gcloud config list --project=nvites-me` should show `josh@idropr.com` + `nvites-me`
5. Sweep for leftover contamination:
   ```
   grep -rE "uwz|urbanwarzone|idropr" server/ surface-website/ api-contracts/ sdk-ts/ scripts/
   ```
   Expect matches ONLY in the contamination checklist items above.
6. Ready to start Phase 1 (build scripts port). Phase 1 requires an alignment session — see "Alignment session pattern" above.
7. **Phase 1** (build scripts, alignment session required)
8. **Phase 2** (deploy skill, alignment session required)
9. **Phase 3** (GCP provisioning, most commands run interactively by the human)
10. **Phase 4** (first deploy ceremony — red-team hard, THEN execute; contamination checklist must be clean)

---

## Risk register

| Risk | Severity | Mitigation |
|---|---|---|
| Accidental push to another project's container registry | **Critical** | Separate `nvites-me` project → separate registry. Build scripts hard-code `nvites-containers` path. Every gcloud command carries `--project=nvites-me` flag. Grep-clean verification on every script before first run. |
| Accidental deploy of nvites code to another project's Cloud Run service | **Critical** | Separate Linux user has no credentials for other GCP projects. Deploy skill ceremony emits project + service name and requires confirmation before proceeding. |
| Cross-project Cloud SQL corruption | **Eliminated structurally** | Nvites has its own Cloud SQL instance in `nvites-me` project. No cross-project IAM bindings. No shared database access. |
| Shared Cloud SQL connection starvation | **Eliminated structurally** | Not shared. |
| Outbound emails sent from UWZ domain | **High** | `email_id.rs` fix is a Phase 4 pre-flight blocker. Must be clean of `@urbanwarzonepaintball.com` before deploy. |
| UWZ branding leaked in production HTML | **Medium** | Contamination checklist must be complete before Phase 4. Red-team step in deploy ceremony surfaces any remaining leaks. |
| Shared DB user with over-broad grants | **Low** | `nvites` MySQL user is scoped to `nvites.*`, not `*.*`. |
| Muscle memory from other projects leaking into nvites sessions | **Low (down from Medium)** | Separate Linux user eliminates shared Claude Code state. Nvites Claude sessions cannot read files outside the nvites user's home directory. Anti-pattern gcloud rule fires on command construction, not project awareness. |
| Postmark suppression list pollution | **Low (down from Medium)** | Separate Postmark server for TrakSent isolates bounce/suppression state from any other server in the account. |
