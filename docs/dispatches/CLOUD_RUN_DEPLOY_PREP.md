# Cloud Run Deploy Prep

**Branch:** dev
**Date:** 2026-04-14
**Deploy target:** 2026-05-30
**Status:** Phase 0 complete (server_mode removal, IP extraction refactor, UWZ purge from Dockerfiles + alert templates). Phases 1–4 pending.

---

## Setup — re-link `uwz-ref` first

This dispatch references files in `uwz-ref/` throughout (scripts, Dockerfile, deploy skill, env.rs, migrations). The symlink was removed at end-of-session cleanup. **Re-create it before Phase 1:**

```bash
# from nvites-me monorepo root:
ln -s <path-to-uwz-monorepo> uwz-ref
```

Verify with `ls uwz-ref/scripts/` — should list `build-server.sh`, `build-website.sh`, and `check-image-refs.sh`. If the target path has moved since the Phase 0 session, ask for the current location.

---

## Why

The nvites repo was template-copied from UWZ and has never been deployed. The deploy infrastructure was partially present (Dockerfiles exist) but triple-broken from the copy. This dispatch directs the work needed to reach a working first deploy to Google Cloud Run.

**Primary safety invariant for all work in this dispatch:** no change may leave UWZ-specific identifiers (`uwz-server`, `uwz-website`, `uwz-containers`, `idropr-dev`, `urbanwarzone*`) anywhere that would cause nvites code or artifacts to push against UWZ infrastructure. Verify with grep after every slice.

---

## What was done in Phase 0 (already committed)

- **`0214961` Remove SERVER_MODE env var and ServerMode enum** — mirrored uwz migration `20260410130000_drop_server_mode`. The granular service flags in `system_settings` are the DB-polled runtime gating path; server_mode was redundant.
- **`7193b85` Extract client IP via multi-provider priority chain** — replaced the Railway-era 2-header function with the uwz multi-provider chain (CF-Connecting-IP → X-Real-IP → Fly-Client-IP → trusted-proxy path → X-Forwarded-For rightmost → untrusted X-Real-Client-IP → peer_addr). Added `TRUSTED_PROXY_SECRET` env var + `subtle::ConstantTimeEq` for timing-safe BFF trust. 143 tests passing.
- **THIS COMMIT — Purge UWZ from Dockerfiles and alert templates**:
  - `server/Dockerfile` rewritten as 5-stage cargo-chef build with correct `nvites-server` package name and nvites crate list (api, authorizenet, database, email-template, postmark, qr-frame, rate-limit, schema-emitter, xtask). Removed uwz-only crates (anthropic, doc-extractor) and the Railway `CACHE_BUST` arg.
  - `surface-website/Dockerfile` stripped of UWZ defaults (`PUBLIC_HOSTNAME=https://urbanwarzonepaintball.com`, `PUBLIC_TRADE_NAME="Urban Warzone Paintball"`), reduced to the 5 PUBLIC_* ARGs nvites actually uses, CACHE_BUST removed.
  - `system_alert/v1/en.text` and `en.mjml` footer: "UWZ Server" → "nvites server".

### Decisions made (apply across all phases)

| Decision | Value | Why |
|---|---|---|
| GCP project | **Separate nvites project** (TBD: project ID) | IAM blast radius, billing clarity, scaling isolation, easier spin-off |
| Cloud SQL | **Share `idropr-dev:us-east4:uwz-sandbox`** via cross-project IAM + `--add-cloudsql-instances` | Save ~$30/mo, reuse existing flags, schema-level isolation is sufficient for nvites's experimental stage |
| Cloud SQL connection path | **`--add-cloudsql-instances` (built-in proxy)** — no VPC connector | Simplest cross-project pattern, no peering/shared-VPC setup. Slight latency vs private IP is negligible for nvites scale |
| Region | **us-east4** | Co-located with shared Cloud SQL |
| Artifact Registry | **Separate `nvites-containers` repo in nvites project** | Separate project → separate registry naturally; cleaner lineage |
| GCS | **Separate nvites buckets in nvites project** (when needed) | Clean separation; nvites may not need media hosting early on |
| server_mode concept | **Eliminated** (Reading A) | Env-set mode required restart; granular service flags in `system_settings` already cover runtime gating |
| IP extraction | **Multi-provider chain with TRUSTED_PROXY_SECRET** | Required for Cloud Run (`X-Forwarded-For` rightmost), CF migration readiness, BFF trust |
| Website PUBLIC_* vars | **5 confirmed**: PUBLIC_MODE, PUBLIC_HOSTNAME, PUBLIC_TRADE_NAME, PUBLIC_PHONE_NUMBER, PUBLIC_POSTHOG_ANALYTICS | Strict subset of uwz's 15; 3 Authorize.Net vars and 8 locale/address vars dropped |

### Open questions (need user input before Phases 1–3)

1. **Nvites GCP project ID** (suggestion: `nvites-prod` or `nvites-dev`)?
2. **Nvites production domain** (e.g., `nvites.me`, `staging.nvites.me`, `app.nvites.me`)?
3. **Nvites email domain** + per-template addresses for `email_id.rs` (see contamination checklist below)?
4. **`PUBLIC_TRADE_NAME` value** (what does the website say as its brand)?
5. **`PUBLIC_PHONE_NUMBER` value** or is this field not needed and should be dropped from the client bundle?
6. **`TIMEZONE_OFFSET`** (signed minutes, e.g., -300 = UTC-5)?
7. **Cookie name replacement for `uwz_token`** (suggestion: `nvites_token`)?
8. **Postmark account** — share UWZ's or new nvites account?
9. **PostHog project** for `PUBLIC_POSTHOG_ANALYTICS` — share or new?

---

## Reference files in `uwz-ref/` (read first when resuming)

- `uwz-ref/scripts/build-server.sh` — server build script template (dual-tag verification, registry check, digest-pinned deploy command emission, 3 exit codes)
- `uwz-ref/scripts/build-website.sh` — website build script template (secret fetch from Secret Manager before docker build, hardcoded business info as build-args)
- `uwz-ref/scripts/check-image-refs.sh` — website pre-deploy image reference verifier (only relevant if nvites adopts GCS media delivery)
- `uwz-ref/server/Dockerfile` — 5-stage cargo-chef reference (already ported in Phase 0)
- `uwz-ref/surface-website/Dockerfile` — website Dockerfile reference (already ported in Phase 0)
- `uwz-ref/cloudbuild-server.yaml` / `cloudbuild-website.yaml` — secondary CI path via Cloud Build (lower priority)
- `uwz-ref/.claude/skills/deploy/SKILL.md` — the 7-step deploy ceremony skill to adopt
- `uwz-ref/docs/DEPLOYMENT.md` — full Cloud Run infrastructure documentation (project IDs, secret names, VPC connector setup, custom domain pattern)
- `uwz-ref/server/api/src/types/env.rs` — reference env.rs with trusted_proxy_secret, gcs_bucket, cdn_base_url fields (nvites has the trusted_proxy_secret; gcs_bucket/cdn_base_url are deferred)

## Gotchas from uwz build scripts (preserve in nvites versions)

These are field-tested — do not drop them when porting:

1. **Dual-tag verification** — both `:latest` and `:SHA` tagged; verify local tags point at the same image ID AFTER build AND in the registry AFTER push. Catches `:latest` drift, which otherwise deploys whatever stale image happens to be serving as latest.
2. **`gcloud --filter=tag=` is broken** — a comment in the uwz script notes gcloud warns that the filter expression "does not currently match but will in the future." Script parses unfiltered output with awk instead. Anyone who tries the "obvious" filter syntax will silently get empty results and think the push failed.
3. **Three exit codes**: `0` = success or user-declined-push, `1` = build or local-tag-mismatch failure, **`2` = push succeeded but registry `:latest` did not update — DO NOT DEPLOY**. Exit 2 specifically means tag drift at the registry level, and deploying would be dangerous.
4. **Digest-pinned deploy command emission** — script prints `gcloud run deploy ... --image=...@sha256:<digest>` at the end, not `:latest` or `:SHA`. Immune to subsequent tag drift. Never construct the deploy command by hand with `$(git rev-parse --short HEAD)` — re-introduces the footgun the script was built to eliminate.
5. **Non-interactive graceful exit** — if stdin isn't a TTY and `--push` flag is absent, skip push cleanly (good for pipelines and dry runs).
6. **Website script: secret fetch before docker build** — SvelteKit `$env/static/public` vars are baked into the client bundle at build time, so secrets must exist when `docker build` runs. Fetch from Secret Manager via gcloud, pass as `--build-arg`.
7. **Hardcoded business info in website script** — phone, address, etc. are hardcoded in `build-website.sh`, not stored as secrets. Secrets rotate; addresses don't. Intentional split.

---

## Phase 1 — Build scripts

### `scripts/build-server.sh`

Adapt from `uwz-ref/scripts/build-server.sh`. Substitutions:

- `uwz-server` → `nvites-server`
- `uwz-containers` → `nvites-containers`
- `idropr-dev` → `<NVITES_GCP_PROJECT_ID>`
- Keep `us-east4` (same region)
- Keep the entire verification and tagging structure verbatim

Verification: after writing, `./scripts/build-server.sh` (without `--push`) must build the image locally and exit 0 without pushing. `grep -i "uwz\|urbanwarzone\|idropr" scripts/build-server.sh` must return empty.

### `scripts/build-website.sh`

Adapt from `uwz-ref/scripts/build-website.sh`. Substitutions:

- `uwz-website` → `nvites-website`
- `uwz-containers` → `nvites-containers`
- `idropr-dev` → `<NVITES_GCP_PROJECT_ID>`
- **Secret fetches: reduce from 5 to 2** — keep `PUBLIC_MODE`, `PUBLIC_POSTHOG_ANALYTICS`; drop the 3 Authorize.Net Accept.js secrets
- **Hardcoded build-args: reduce from 12 to 3** — `PUBLIC_HOSTNAME` (nvites domain), `PUBLIC_TRADE_NAME` (nvites brand), `PUBLIC_PHONE_NUMBER` (if applicable)
- **Drop the 8 address/locale build-args** (STREET_ADDRESS, CITY, STATE_LONG, STATE_SHORT, ZIPCODE, COUNTRY, PHONE_E164 — not used by nvites client bundle)
- Keep the entire verification and tagging structure verbatim

Verification: same pattern. `grep -i "uwz\|urbanwarzone\|idropr" scripts/build-website.sh` must return empty after writing.

### `scripts/check-image-refs.sh`

**SKIP for now.** The script expects `surface-website/src/lib/data/preload-manifest.ts` and an `imageSet()` utility. Nvites has neither. Port only if/when nvites adopts GCS media delivery with a manifest-driven approach. If porting, substitute `gs://uwz-media-staging` → `gs://nvites-media-staging`.

---

## Phase 2 — Adopt the `deploy` skill

Port `uwz-ref/.claude/skills/deploy/SKILL.md` to `.claude/skills/deploy/SKILL.md` with substitutions:

- `uwz-server` → `nvites-server`
- `uwz-website` → `nvites-website`
- **Remove the DEC-121 reference** — uwz enforces `deny_unknown_fields` project-wide, so server-before-website deploy ordering is an invariant there. Nvites has only 1 usage in `api-contracts/src/users.rs`, so it's a convention hint, not a load-bearing invariant. Replace the blocker framing with a soft recommendation.
- **Stub specific URLs** as `<TBD>` markers — Cloud Run service URLs (`https://nvites-server-<PROJECT_NUMBER>.us-east4.run.app`), gcloud auth account, custom domain
- Keep the 7-step ceremony: migrations → local CI → staging push → build/push → red team → deploy → verify
- Keep the gotcha discipline (dual-tag verification, exit code 2 = don't deploy, digest-pinned deploy command)

Verification: skill must grep clean for UWZ refs (`grep -i "uwz\|urbanwarzone\|idropr" .claude/skills/deploy/SKILL.md`).

---

## Phase 3 — GCP provisioning (user in the loop)

One-time setup, requires user running most of the `gcloud` commands. The reference is `uwz-ref/docs/DEPLOYMENT.md`.

1. **Create nvites GCP project** (name TBD). Set billing account.
2. **Enable APIs**:
   ```
   gcloud services enable run.googleapis.com cloudbuild.googleapis.com \
     artifactregistry.googleapis.com sqladmin.googleapis.com \
     secretmanager.googleapis.com billingbudgets.googleapis.com
   ```
3. **Create Artifact Registry repo**:
   ```
   gcloud artifacts repositories create nvites-containers \
     --repository-format=docker --location=us-east4
   ```
4. **Configure Docker auth**:
   ```
   gcloud auth configure-docker us-east4-docker.pkg.dev
   ```
5. **Cross-project Cloud SQL IAM** — grant nvites compute SA access to uwz-sandbox:
   ```
   gcloud projects add-iam-policy-binding idropr-dev \
     --member="serviceAccount:<NVITES_PROJECT_NUMBER>-compute@developer.gserviceaccount.com" \
     --role="roles/cloudsql.client"
   ```
6. **Create nvites schema on uwz-sandbox** (run via cloud-sql-proxy from local machine with admin access):
   ```sql
   CREATE DATABASE nvites CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
   CREATE USER 'nvites'@'%' IDENTIFIED BY '<strong-password>';
   GRANT ALL ON nvites.* TO 'nvites'@'%';  -- scoped to nvites schema only
   FLUSH PRIVILEGES;
   ```
7. **Populate nvites Secret Manager**:
   - `DB_USER=nvites`, `DB_PASSWORD=<strong-password>`, `DB_DATABASE=nvites`
   - `MASTER_PASSWORD` (new key, ≥12 chars — generate fresh, do not reuse UWZ's)
   - `POSTMARK_SECRET` (decision pending: share UWZ's or new nvites account)
   - `TRUSTED_PROXY_SECRET` — generate with `openssl rand -base64 32`
   - `PUBLIC_MODE=LIVE`
   - `PUBLIC_POSTHOG_ANALYTICS` (decision pending)
8. **Grant Cloud Run SA access to each secret**:
   ```
   gcloud secrets add-iam-policy-binding SECRET_NAME \
     --member="serviceAccount:<NVITES_PROJECT_NUMBER>-compute@developer.gserviceaccount.com" \
     --role="roles/secretmanager.secretAccessor"
   ```
9. **Apply migrations against nvites schema**:
   ```
   # via cloud-sql-proxy on a separate port
   DATABASE_URL='mysql://nvites:<pass>@127.0.0.1:3307/nvites' \
     sqlx migrate run --source server/migrations
   ```
10. **Optional**: set budget alert (reference: uwz's $75/mo at 50/75/100% thresholds).

---

## Phase 4 — First deploy ceremony

Use the adopted deploy skill. Specific values to plug in:

- **Cloud Run services**: `nvites-server`, `nvites-website`
- **Registry**: `us-east4-docker.pkg.dev/<NVITES_PROJECT>/nvites-containers/`
- **VPC connector**: NONE (using `--add-cloudsql-instances` for cross-project DB)
- **Cloud SQL flag**: `--add-cloudsql-instances=idropr-dev:us-east4:uwz-sandbox`
- **DB_HOST**: `/cloudsql/idropr-dev:us-east4:uwz-sandbox` (Unix socket path)
- **Server env vars**:
  - `IP_ADDRESS=0.0.0.0`
  - `SHARDS=2`
  - `LIMITER_INITIAL_CAPACITY=100`
  - `LIMITER_TOKENS_PER_BUCKET=100`
  - `LIMITER_INITIAL_TOKENS_PER_BUCKET=1000`
  - `LIMITER_REFILL_RATE=100.0`
  - `LIMITER_REFILL_WINDOW=HOUR`
  - `SESSIONS_INITIAL_CAPACITY=100`
  - `TIMEZONE_OFFSET=<TBD>`
  - `SITE_URL=https://<nvites-domain>`
  - `CORS_ALLOWED_ORIGINS=https://<nvites-domain>`
  - `DB_HOST=/cloudsql/idropr-dev:us-east4:uwz-sandbox`
  - `DB_PORT=3306`
- **Server secrets** (bound via `--set-secrets`):
  - `DB_USER`, `DB_PASSWORD`, `DB_DATABASE`, `MASTER_PASSWORD`, `POSTMARK_SECRET`, `TRUSTED_PROXY_SECRET`
- **Website env vars**:
  - `ORIGIN=https://<nvites-domain>`
  - `API_BASE_URL=https://nvites-server-<PROJECT_NUMBER>.us-east4.run.app`
  - `ADDRESS_HEADER=X-Forwarded-For` (Cloud Run default)
- **Custom domain mapping**: TBD (nvites domain decision needed)

**Red-team before first deploy**: before pushing images, pause and ask:
- Does `email_id.rs` still have UWZ addresses? (YES — see contamination checklist; MUST fix first)
- Does `robots.txt` still have the UWZ sitemap URL? (YES — MUST fix)
- Is the cookie name still `uwz_token`? (YES — MUST fix OR accept that users have a poorly-named cookie)
- Are there any UWZ brand strings visible in rendered HTML that would confuse real users? (check SeoHead, layouts, about page)

---

## Pre-deploy UWZ contamination checklist

**BLOCKER — production-visible leaks; MUST address before deploy:**

- [ ] **`server/api/src/enums/email_id.rs` lines 36–41**: 6 hardcoded `@urbanwarzonepaintball.com` email "from" addresses returned by `EmailID::from_address()`. Used for outbound email via Postmark. If deployed as-is, nvites sends emails as UWZ → potential spam flagging, brand confusion, reply-to-wrong-inbox. Decision needed: nvites email domain + per-template addresses (`EmailVerification`, `BookingConfirmation`, `QueuePendingConfirmation`, `WaiverConfirmation`, `SystemAlert`, `BookingCancellation`).
- [ ] **`surface-website/static/robots.txt` line 6**: `Sitemap: https://urbanwarzonepaintball.com/sitemap.xml`. Update to nvites domain.
- [ ] **Cookie name `uwz_token`** (5 files): `surface-website/src/hooks.server.ts`, `(auth)/login/+page.server.ts`, `portal/logout/+page.server.ts`, `portal/profile/+page.server.ts`, `lib/api/handleLoadError.ts`. Decision needed on replacement (suggest `nvites_token`).
- [ ] **`surface-website/src/lib/components/SeoHead.svelte` line 14**: `TITLE_SUFFIX = ' | UWZ Paintball'`. Update to nvites brand suffix.
- [ ] **`surface-website/src/routes/(auth)/+layout.svelte` line 20**: hardcoded `UWZ: BE THE HERO` brand string and `aria-label="UWZ home"`. Rewrite.
- [ ] **Page titles in 4 files**: `(auth)/login/+page.svelte`, `(auth)/register/+page.svelte`, `portal/profile/+page.svelte`, `portal/orders/+page.svelte` — `Login | UWZ`, `Register | UWZ`, `Profile | Portal | UWZ`, `Orders | Portal | UWZ`. Update.
- [ ] **`surface-website/src/routes/(public)/about/+page.svelte`**: ~4 UWZ brand/story references. Rewrite for nvites OR remove the about page entirely (it's a UWZ template, not nvites content).

**NON-BLOCKER but should clean up eventually (test fixtures, not production-visible):**

- [ ] `server/qr-frame/src/types/generator.rs` lines 124, 136, 147, 161, 164, 186, 191: test fixture URLs use `https://urbanwarzonepaintball.com/waiver?code=...`. Replace with `https://nvites.me/<generic-path>` or `https://example.com/test`.
- [ ] `server/postmark/src/types/postmark.rs` lines 73, 78–80: test fixtures with `contact@urbanwarzonepaintball.com`. Replace with `test@example.com`.

**Completed in Phase 0 (for reference):**

- ✅ `server/Dockerfile` — rewritten 5-stage cargo-chef with nvites crates + `nvites-server` package name
- ✅ `surface-website/Dockerfile` — stripped UWZ defaults, reduced to 5 PUBLIC_* ARGs, CACHE_BUST removed
- ✅ `server/email-template/.../system_alert/v1/en.text` — footer updated
- ✅ `server/email-template/.../system_alert/v1/en.mjml` — footer updated

---

## Next session starting checklist

1. Run `/orient`
2. Read this dispatch (`docs/dispatches/CLOUD_RUN_DEPLOY_PREP.md`)
3. Verify state:
   - `git log -5` should show the three Phase 0 commits
   - `cd server && cargo xtask build-all` should pass
   - `cd server && cargo test -p nvites-server` should pass (143 tests)
4. Confirm `uwz-ref/` symlink still exists. If not, ask user to re-link before Phase 1/2.
5. Sweep for leftover contamination:
   ```
   grep -ri "uwz\|urbanwarzone\|idropr" server/ surface-website/ api-contracts/ sdk-ts/ scripts/
   ```
   Expect matches ONLY in the contamination checklist items above. No matches in Dockerfiles, alert templates, or any file touched in Phase 0.
6. Answer the 9 open questions at the top of this dispatch (needs user in the loop).
7. **Phase 1** (build scripts) — mechanical port with substitutions, once open questions are answered.
8. **Phase 2** (deploy skill) — mechanical port with substitutions.
9. **Phase 3** (GCP provisioning) — user runs gcloud commands, Claude walks through.
10. **Phase 4** (first deploy ceremony) — red-team hard, THEN execute. Contamination checklist items MUST be addressed before this phase.

---

## Risk register

| Risk | Severity | Mitigation |
|---|---|---|
| Accidental push to uwz-containers registry | **Critical** | Separate nvites project → separate registry. Build scripts must have grep-clean substitutions before first run. |
| Accidental deploy of nvites code to `uwz-server` Cloud Run service | **Critical** | Separate nvites project → no access to uwz-server service. Deploy skill service name must be `nvites-server` exclusively. |
| Cross-project Cloud SQL IAM misconfigured | High | Verify `roles/cloudsql.client` grant before first deploy attempt. Test with a read query via `cloud-sql-proxy` first. |
| Shared Cloud SQL connection starvation | Medium | Set explicit `DB_MAX_CONNECTIONS` on both uwz and nvites services with headroom to the instance max_connections cap. |
| Leaked UWZ branding in production HTML | Medium | Contamination checklist must be completed before Phase 4. Red-team step in deploy ceremony surfaces any remaining leaks. |
| Outbound emails sent from UWZ domain | High | `email_id.rs` fix is a Phase 4 pre-flight blocker. Do NOT skip. |
| Shared DB user with over-broad grants | Medium | Create `nvites` user with `GRANT ALL ON nvites.*` only, NOT `*.*`. |
