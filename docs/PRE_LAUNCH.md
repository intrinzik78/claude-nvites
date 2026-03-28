# Pre-Launch Checklist

Launch readiness tracker for nvites.me. See also: [STARTUP_GATES.md](STARTUP_GATES.md) for runtime configuration, [DEPLOYMENT.md](DEPLOYMENT.md) for deployment procedures.

## Infrastructure

- [ ] Railway project created
- [ ] Cloud SQL instance provisioned, `nvites` schema created
- [ ] Migrations applied to production DB
- [ ] `.env` configured with production values
- [ ] CORS origins set for production domain
- [ ] DNS configured for nvites.me

## Services

- [ ] Postmark account + sender domain verified
- [ ] Authorize.Net sandbox → production credentials
- [ ] Webhook endpoints registered in Authorize.Net dashboard

## Security

- [ ] Master password set (strong, 12+ chars)
- [ ] API secrets created via bootstrap command
- [ ] Rate limiters enabled
- [ ] HTTPS enforced (Railway auto TLS)

## Product

- [ ] QR redirect endpoint functional (`/{short_code}` → destination)
- [ ] Analytics capture on pass-through
- [ ] Daily/weekly digest email template built
- [ ] Client registration flow working
- [ ] At least one test campaign end-to-end
