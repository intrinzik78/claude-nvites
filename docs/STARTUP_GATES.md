# Startup Gates

Critical configuration that must be set correctly before the server goes live. Failures here are **silent at runtime** unless noted — the server starts but features are broken.

## Required

| Gate | Env var | Failure mode |
|------|---------|-------------|
| Database | `DATABASE_URL` | Panic on startup |
| Master password | `MASTER_PASSWORD` | Panic on startup (min 12 chars) |
| Server port | `PORT` | Panic on startup |
| IP address | `IP_ADDRESS` | Panic on startup |
| Server mode | `SERVER_MODE` | Panic on startup |
| Timezone | `TIMEZONE_OFFSET` | Panic on startup |
| Site URL | `SITE_URL` | Panic on startup |
| CORS origins | `CORS_ALLOWED_ORIGINS` | Panic on startup |

## Optional (silent degradation)

| Gate | Env var | Failure mode |
|------|---------|-------------|
| Postmark | DB `postmark_email_service` flag | Emails silently not sent |
| Authorize.Net | DB `payment_service` flag | Payments disabled |
| Rate limiter | DB `load_rate_limiter_service` flag | No rate limiting |
| System alerts | `SYSTEM_ALERT_EMAIL` | No alert emails |
| QR generator | Frame asset load | QR generation disabled (logged at warn) |
