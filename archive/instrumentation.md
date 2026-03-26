# Spawn Instrumentation Plan

Background tasks spawned via `actix_web::rt::spawn` and `actix_rt::task::spawn_blocking` run outside the request span hierarchy. Their log output appears as top-level events with no service name — making it hard to filter or correlate in structured log output.

The fix: wrap each spawned future with `.instrument(tracing::info_span!("service_name"))` so all log events inside carry the span context.

## Background Services (long-lived, spawned at startup)

These run for the lifetime of the process. Each should get a named span.

| File | Line | Span Name | Notes |
|------|------|-----------|-------|
| `types/rate_limit_sweeper.rs` | 17 | `rate_limit_sweeper` | General limiter |
| `types/rate_limit_sweeper.rs` | 24 | `addon_rate_limit_sweeper` | Addon limiter |
| `types/rate_limit_sweeper.rs` | 31 | `queue_rate_limit_sweeper` | Queue limiter |
| `types/bookings/sweeper.rs` | 49 | `booking_sweeper` | Pending expiry monitor |
| `types/scans/scan_sweeper.rs` | 15 | `scan_sweeper` | Document scan controller |
| `types/sessions/session_sweeper.rs` | 14 | `session_sweeper` | Stale session cleanup |
| `types/sessions/user_epoch_sweeper.rs` | 18 | `user_epoch_sweeper` | Epoch sync |
| `types/workflow/sweeper.rs` | 19 | `workflow_sweeper` | Workflow monitor |

### Pattern

```rust
// before
let _monitor = actix_web::rt::spawn(async move {
    WorkflowMonitor::watch(connection, shared).await
});

// after
use tracing::Instrument;

let _monitor = actix_web::rt::spawn(
    async move {
        WorkflowMonitor::watch(connection, shared).await
    }
    .instrument(tracing::info_span!("workflow_sweeper"))
);
```

## Fire-and-Forget Handler Spawns

Short-lived tasks spawned from request handlers. These should carry enough context to correlate with the originating request.

| File | Line | Span Name | Notes |
|------|------|-----------|-------|
| `api/bookings/bookings_post.rs` | 125 | `booking_confirmation_email` | Fire-and-forget email |
| `api/queue_entries/call_ahead_post.rs` | 113 | `call_ahead_confirmation_email` | Fire-and-forget email |

### Pattern

```rust
// before
actix_web::rt::spawn(async move {
    if let Err(e) = BookingsPost::send_confirmation(&b, &p, &s).await { ... }
});

// after
use tracing::Instrument;

actix_web::rt::spawn(
    async move {
        if let Err(e) = BookingsPost::send_confirmation(&b, &p, &s).await { ... }
    }
    .instrument(tracing::info_span!("booking_confirmation_email"))
);
```

## spawn_blocking (CPU-bound)

These are short-lived blocking tasks. Instrumentation is lower priority since they're synchronous and the parent span context is already lost by design. Including for completeness.

| File | Line | Context | Notes |
|------|------|---------|-------|
| `traits/verify_password.rs` | 21 | bcrypt verify | Auth path — timing-sensitive |
| `api/users/users_post.rs` | 65 | bcrypt hash | User creation |
| `api/sessions/sessions_post.rs` | 50 | bcrypt verify (dummy) | Timing normalization |
| `api/sessions/sessions_post.rs` | 56 | bcrypt verify (dummy) | Timing normalization |

These can optionally use `tracing::info_span!("bcrypt")` but the value is marginal — they don't emit log events internally.

## Execution Notes

- `tracing::Instrument` trait must be in scope (`use tracing::Instrument;`)
- Background services are the high-value targets — they emit logs continuously
- Fire-and-forget spawns are medium-value — they emit logs on failure
- spawn_blocking is low-value — no internal logging
- All files already import `tracing` for log macros; only the `Instrument` trait is new
