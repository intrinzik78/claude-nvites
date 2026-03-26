# Dispatch: System error notification emails for silent operational failures

**Date:** 2026-03-21
**From:** server session (AUDIT-014, AUDIT-019)
**To:** dev (crosscutting)
**Priority:** High — silent revenue loss and silent operational failures with no alerting path

---

## Problem

Two classes of silent failure exist with no notification to anyone who can act:

1. **Booking confirmation email rejected by Postmark** (AUDIT-014) — customer books successfully but never receives confirmation. Postmark rejection is logged to `email_postmark_log` table and a `warn`-level log line. Nobody monitors either during operations. Causes: inactive recipient, sender verification drift, quota.

2. **Invalid availability time slots** (AUDIT-019) — operating hours configuration produces out-of-range time values during slot generation. Customers silently don't see bookable slots for affected times/days. Revenue is lost with no indication to anyone. Currently these `.unwrap()` calls panic the handler (500 error), but even after fixing to skip-and-log, the log goes unmonitored.

Both share the same root cause: **the system has no dev/operator alerting channel for errors that require human intervention**. Logs exist but nobody watches them. The ops team can't diagnose these — only dev can act.

## Proposed Solution

**Confidence: High**

Build a system error notification capability — a new email type that sends to a configured dev/operator address when specific failure conditions occur.

### Design considerations

1. **Recipient** — dev/operator email address, not customer. Likely configured as an env var or `system_settings` row. Could be a single address or a small list.

2. **Deduplication / throttling** — critical. A misconfigured operating hours schedule could fire on every slot generation attempt in a loop. A Postmark outage could reject every email. The system must deduplicate by error class and throttle (e.g., one notification per error type per hour, or per day). Without this, the alerting system becomes a spam cannon during outages.

3. **Error classes to cover initially:**
   - Postmark send-time rejection for transactional emails (booking confirmation, waiver confirmation, queue confirmation, email verification)
   - Availability slot generation producing invalid times
   - Any future "silent data/config error" that causes customer-facing degradation

4. **Delivery mechanism** — email is appropriate because:
   - The Postmark integration already exists
   - Dev checks email regularly
   - No additional infrastructure (Slack webhooks, PagerDuty) needed
   - Use a separate Postmark message stream or sender address to distinguish from customer emails

5. **Not a general-purpose alerting system** — this is specifically for human-caused configuration errors and third-party service rejections that silently degrade the customer experience. Application crashes, DB connection failures, etc. are infrastructure concerns handled by Railway's monitoring.

### Implementation sketch

- New `EmailID` variant (e.g., `SystemAlert`) with a dev-facing sender address
- New type (e.g., `SystemAlert`) that accepts an error class enum and detail string, checks a throttle table/cache before sending
- Call sites: `bookings_post.rs` send_confirmation error path, `availability_get.rs` invalid slot path, and future sites as identified
- Throttle state: either an in-memory cache (simple, resets on restart) or a DB table (persistent, survives restarts). In-memory is probably fine for v1

## Relationship to existing audit items

- **AUDIT-014** (BookingConfirmationEmailRejected) — currently deferred. This dispatch provides the alerting mechanism that makes the fix complete. After implementation: promote log level from `warn` to `error`, send system alert email on rejection.
- **AUDIT-019** (invariant `.unwrap()` calls) — the immediate code fix (replace `.unwrap()` with `let Some` + `tracing::error!` + continue) should ship independently on the server branch. This dispatch adds the notification layer on top.

## Before implementation

- Decide on recipient configuration: env var vs `system_settings` row vs both
- Decide on throttle strategy: per-error-class interval, daily digest, or both
- Decide whether `SystemAlert` is a new `EmailID` variant or a separate pathway (Postmark message stream consideration)
- Check Postmark rate limits and pricing for the expected volume of system alerts
- Coordinate with server branch: AUDIT-019 code fix (skip-and-log) should land first so the call site exists for the notification hook
