# Pre-Launch Checklist

Project launch readiness tracker. Items are categorized and checked off as they're resolved. See also: [STARTUP_GATES.md](STARTUP_GATES.md) for runtime configuration requirements, [DEPLOYMENT.md](DEPLOYMENT.md) for env vars and deployment procedures.

## Security

### Open

- [ ] **Per-user rate limiting not implemented**: Rate limiting is IP-based only. A compromised account behind a shared IP cannot be individually throttled. Acceptable for launch; revisit if abuse patterns emerge.
- [ ] **Rate limiter whitelist escalation for authenticated users**: `RateLimiter` has whitelist infrastructure (`add_to_whitelist`, `is_whitelisted`) but no automatic escalation on login or de-escalation on logout. Parked — global bucket (250 tokens) is generous enough that authenticated users won't hit it. Build when tightening global supply post-launch. Needs: `remove_from_whitelist` method, upsert semantics on `add_to_whitelist`, reference counting for shared-IP venues, timer expiry checks in `is_whitelisted`.
- [ ] **Decrypted secrets held in plaintext memory**: Standard for secret managers; key material is zeroized on drop (SEC-004) but decrypted values live in the `SecretController` map. Mitigate via process hardening (seccomp, memory-locked pages) post-launch.
- [ ] **CORS middleware is vestigial**: No browser makes cross-origin requests — all website traffic goes through the BFF, Tauri uses native HTTP. `CORS_ALLOWED_ORIGINS` env var is set but unused. Remove middleware and env var pre-launch or accept as harmless dead code.

### Resolved

- [x] **Client IP extraction secured**: `extract_client_ip()` reads Railway `X-Real-IP` (public) → BFF `X-Real-Client-IP` (internal) → `"unknown"`. Rate limiting and ESIGN audit trails use real client IPs. `X-Forwarded-For` banned as spoofable. **Resolved 2026-03-19** (DEC-141).

- [x] **Rate limiting on queue public endpoints**: Queue endpoints share the addon rate limiter (DEC-100). **Resolved 2026-03-08.**

- [x] **Postmark test needs real credentials**: `send_postmark_test_email` is `#[ignore]`'d — it hits the live Postmark API. Before launch, verify email sending works with production credentials. Run: `cargo test -p postmark -- --ignored`. **Verified 2026-02-24** — migration applied, `postmark_email_service` enabled, live send confirmed.

- [x] **Rate limiting on public addon POST**: IP rate limiter implemented — `PrimaryCommand::build_addon_rate_limiter()` in `primary_command.rs` (10 tokens/min/IP, sharded), enforced in `AddonsPost::logic()` in `addons_post.rs` (429 on denial), GC via `rate_limit_sweeper.rs`. **Verified 2026-02-24.**

- [x] **DEC-024 — Entity-level auth**: Closed by DEC-049. Audit confirmed role-based auth sufficient for launch — portal filters by person_id, staff unrestricted by design, public endpoints use UUID capability tokens.

- [x] **VULN-001 — TOCTOU race on addon cap**: Count and insert were separate non-transactional queries in `addons_post.rs`. Fixed: wrapped in transaction with `SELECT COUNT(*) ... FOR UPDATE`.

- [x] **DEC-051 — Addon POST auth**: Stays public. UUID capability token is the auth gate (consistent with DEC-049).

## Correctness

### Open

- [x] **CSP `connect-src` leaks internal hostname**: Removed CSP `connect-src` append entirely — BFF pattern means browser never calls API directly (DEC-050 supersedes DEC-063). **Resolved 2026-03-20.**
- [x] **`API_BASE_URL` startup guard**: `validateApiBaseUrl()` runs at module level, forces maintenance mode on missing/invalid/loopback values with clear console.error. **Resolved 2026-03-20.**

### Resolved

- [x] **Venue-local date in call-ahead POST**: `call_ahead_post.rs` now applies `utc_offset_minutes` from AppState, matching the `queue_entries_list_get.rs` pattern. **Verified 2026-03-09.**

## Build Pipeline

### Resolved

- [x] **End-to-end `cargo xtask build-all` validation**: Full pipeline verified: api-contracts → schema-emitter → dist/openapi.json → uwz-server → sdk-ts type generation. All steps pass. CI regression gate is an infrastructure item. **Verified 2026-03-09.**

## Infrastructure

### Open

- [ ] **CI/CD pipeline**: Railway auto-deploys on branch push, but no GitHub Actions workflow for running tests, `cargo xtask check`, or lint on PRs.
- [ ] **Railway watch paths verification**: Server should watch `server/`, `api-contracts/`. Website should watch `surface-website/`, `sdk-ts/`. Discussed but need verification in Railway UI.
- [x] **Admin bootstrap**: `uwz-server bootstrap` command reads `BOOTSTRAP_*` env vars, creates System user with SysAdmin permissions. Idempotent, local-only (DEC-147). **Resolved 2026-03-20.**
- [ ] **Domain and DNS**: Custom domain configuration, DNS pointing, Railway custom domain setup.

### Resolved

- [x] **Deployment platform**: Railway selected (DEC-143). Per-service Dockerfiles (`server/Dockerfile`, `surface-website/Dockerfile`). Staging deployment proven end-to-end. See [DEPLOYMENT.md](DEPLOYMENT.md). **Resolved 2026-03-19.**

- [x] **SSL/TLS**: Railway edge proxy terminates TLS automatically for public traffic. Internal traffic encrypted via WireGuard tunnel. Database SSL via `DB_CERT` env var (DEC-145). **Resolved 2026-03-19.**

- [x] **Environment variable management**: All env vars documented in [DEPLOYMENT.md](DEPLOYMENT.md) with per-service tables. `PORT`/`SHARDS` renames (DEC-144), `DB_CERT` for hosted SSL (DEC-145), `API_BASE_URL` dynamic private (DEC-146). **Resolved 2026-03-19.**

## Observability

### Open

- [ ] Error tracking (Sentry or equivalent)
- [ ] Log aggregation (Railway provides basic log viewing; evaluate if sufficient)
- [ ] Alerting (email failures, rate limiter activations, DB errors)
- [ ] PostHog analytics verification — client-side navigation tracking, CSP configuration

## Data & Backups

### Open

- [ ] **Backup schedule with point-in-time recovery**: Cloud SQL supports automated backups — configure retention and verify PITR.
- [ ] **Restore procedure tested end-to-end**: Test restoring a Cloud SQL backup to a new instance and verify data integrity.
- [ ] **STARTUP_GATES.md items verified in production**: Run through all gates against the production environment before go-live.

### Resolved

- [x] **Production database migration plan**: Cloud SQL 8.4 is live. All migrations run clean. Environment seed migration (`20260319120000`) inserts `system_settings` row. CI runs MySQL 8.4 to catch FK constraint issues early. **Resolved 2026-03-19.**
