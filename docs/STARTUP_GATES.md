# Startup Gates

Critical configuration that must be set correctly before the server goes live.
Failures here are **silent at runtime** unless noted — the server starts but features are broken.

The `prod` startup command warns on disabled items (see `PrimaryCommand::prod_state()` in `primary_command.rs`).

For the complete env var inventory per service, see [DEPLOYMENT.md](DEPLOYMENT.md).

---

## system_settings table (DB-persisted flags)

| Column | Must be | Effect if wrong |
|---|---|---|
| `postmark_email_service` | `1` (Enabled) | Booking confirmation emails silently skipped |
| `load_rate_limiter_service` | `1` (Enabled) | All API endpoints unprotected against abuse |

The `system_settings` row is inserted automatically by the environment seed migration (`20260319120000`). Verify the values are correct for the target environment after running migrations.

---

## Server env vars (silent failures)

These vars cause broken behavior — not a boot failure — if misconfigured.

| Variable | Requirement | Effect if wrong |
|---|---|---|
| `TIMEZONE_OFFSET` | Signed minutes matching venue local time (e.g. `-300` = UTC-5) | Booking operating-hours check and confirmation email times wrong |
| `MASTER_PASSWORD` | Must match the key used to encrypt secrets in DB | Secrets unreadable; server fails to start |
| `PORT` | Must match what Railway expects (default `3000`) | 502 from Railway public URL; internal networking timeouts |
| `IP_ADDRESS` | `0.0.0.0` | Server binds to localhost only; Railway can't route to it |
| `SHARDS` | Positive integer | Rate limiter and session controller sharding fails |
| `DB_CERT` | Raw PEM content of Cloud SQL server CA cert | SSL connection to Cloud SQL fails; server won't start |
| `SITE_URL` | Full public URL with scheme | Email links and ESIGN audit trail URLs point to wrong host |
| `POSTMARK_SECRET` | Valid Postmark API key (stored in `api_secrets`, encrypted) | Email sending silently fails at runtime |

---

## Website env vars (silent failures)

| Variable | Requirement | Effect if wrong |
|---|---|---|
| `API_BASE_URL` | Internal server URL with port (`http://<service>.railway.internal:3000`) | All BFF requests fail; pages render without data or 500 |
| `ORIGIN` | Public URL matching the domain users visit | SvelteKit CSRF checks reject all form submissions |
| `ADDRESS_HEADER` | `X-Real-IP` | SvelteKit reads wrong header for client IP; `locals.clientIp` is wrong |
| `PUBLIC_MODE` | `LIVE` for production | Site shows maintenance or dev mode UI |

---

## Database seed data

| Table | Required row | Used by |
|---|---|---|
| `system_settings` | Single row (inserted by migration `20260319120000`) | Server boot — `prod_state()` reads this at startup |
| `email` | `id = 2` (`EmailID::BookingConfirmation`) | `send_confirmation` — server starts but emails fail at runtime if row missing |
| 15 lookup tables | Seeded via migration matching Rust enum discriminants | Enum `from_u8` conversions fail if rows are missing |
| `api_secrets` | Environment-specific, encrypted with `MASTER_PASSWORD` | Postmark and other integrations fail at runtime |
| Admin user | Manual insert (see [DEPLOYMENT.md](DEPLOYMENT.md)) | No staff login possible; system is unusable |

---

## Railway / TLS

The server speaks **HTTP only**. Railway's edge proxy terminates TLS on public traffic. Internal traffic (website BFF → server) is plain HTTP encrypted by Railway's WireGuard tunnel.

| Requirement | Effect if wrong |
|---|---|
| Railway edge proxy active on public URLs | All traffic in plaintext; tokens exposed on the wire |
| Railway sets `X-Real-IP` on public requests | Rate limiting uses wrong IP; ESIGN audit trail IPs are inaccurate |
| Internal requests use `X-Real-Client-IP` header (set by BFF) | BFF-originated requests all share one rate limit bucket |
| `X-Forwarded-For` is **not trusted** (spoofable) | `extract_client_ip()` ignores it by design (DEC-141) |

**Key detail:** `X-Real-IP` is only present on requests that pass through Railway's public edge proxy. Internal (BFF → server) requests don't have it — the BFF reads `X-Real-IP` from the incoming public request and forwards it as `X-Real-Client-IP`.

---

## Notes

- `load_rate_limiter_service` and session controller are linked: enabling the rate limiter in the DB also requires `SESSIONS_INITIAL_CAPACITY` and related env vars to be set correctly.
- New gates should be added here when introduced. If a gate can be checked at startup, add a warning to `prod_state` in `primary_command.rs`.
- `CORS_ALLOWED_ORIGINS` is set but the CORS middleware is vestigial — no browser makes direct cross-origin requests to the API. See [PRE_LAUNCH.md](PRE_LAUNCH.md).
