# DISPATCH: Replace `realip_remote_addr()` with Cloudflare-aware IP extraction

**Date:** 2026-03-17
**From:** dev audit session (form & BFF security audit)
**Target:** server worktree
**Priority:** High — pre-launch blocker
**Audit reference:** `docs/DEV_AUDIT_RESULTS.md`, FINDING: Client IP Identification Is Broken

---

## Why

Render routes all public traffic through Cloudflare → Render LB → application. `X-Forwarded-For` is **spoofable** on Render — Render only appends to it, never strips client-supplied values. Any client can set `X-Forwarded-For: <fake-ip>` and get a fresh rate-limit bucket.

The server currently uses `connection.realip_remote_addr()` everywhere, which reads `X-Forwarded-For` first. This affects:

- **Rate limiting** — bypassable via header spoofing on direct API traffic; all website users share one bucket on BFF traffic
- **ESIGN audit trail** — waiver endpoints log the wrong IP for website-originated signatures

**Sources:**
- Render does not strip X-Forwarded-For: [Render feature request](https://feedback.render.com/features/p/send-the-correct-xforwardedfor), [Paul Kuruvilla analysis](https://rohitpaulk.com/articles/render-rails-remote-ip)
- Cloudflare `True-Client-IP` is unspoofable: [Cloudflare docs — HTTP request headers](https://developers.cloudflare.com/fundamentals/reference/http-request-headers/)

---

## What to build

### 1. Create `extract_client_ip` utility function

**Location:** `server/api/src/api/validation.rs` (or a new `server/api/src/api/ip.rs` if preferred — it's a cross-cutting utility like `is_valid_email`)

Two traffic paths reach the server:

| Path | Arrives via | Trusted header | Why trustworthy |
|------|-------------|----------------|-----------------|
| BFF (surface-website) | Render private network | `X-Real-Client-IP` | Only private-network services can reach the server on this path; header can't be set by external clients |
| Direct (Tauri, CLI, public) | Cloudflare → Render LB | `True-Client-IP` | Set by Cloudflare edge; Cloudflare overwrites any client-supplied value |

```rust
use actix_web::HttpRequest;

/// Extract the real client IP from trusted headers.
///
/// Priority:
/// 1. `X-Real-Client-IP` — set by the BFF over Render's private network.
///    Trustworthy because the private network is not reachable from the public internet.
/// 2. `True-Client-IP` — set by Cloudflare at the edge for public traffic.
///    Cloudflare overwrites any client-supplied value; cannot be spoofed.
/// 3. Falls back to "unknown" if neither header is present (local dev).
pub fn extract_client_ip(req: &HttpRequest) -> String {
    req.headers()
        .get("X-Real-Client-IP")
        .or_else(|| req.headers().get("True-Client-IP"))
        .and_then(|v| v.to_str().ok())
        .unwrap_or("unknown")
        .to_string()
}
```

**Why this priority order:**
- BFF traffic arrives over the private network where `True-Client-IP` is NOT present (no Cloudflare in the path). `X-Real-Client-IP` is the only source.
- Public traffic has `True-Client-IP` from Cloudflare. It will NOT have `X-Real-Client-IP` (only the BFF sets it, and only over the private network).
- If an attacker sends `X-Real-Client-IP` on a public request, `True-Client-IP` would also be present (Cloudflare always sets it). But since `X-Real-Client-IP` is checked first, could the attacker spoof it? **No** — public traffic cannot reach the private network port. If the server is also exposed publicly and an attacker hits the public URL with `X-Real-Client-IP: <fake>`, they'd bypass Cloudflare's header... but only if the server is reachable on the same port for both public and private traffic. **If the server is exposed publicly**, reverse the priority order (check `True-Client-IP` first) or only read `X-Real-Client-IP` when `True-Client-IP` is absent. The implementation above handles this correctly — on public requests, both headers may be present, but `X-Real-Client-IP` won't be set by the BFF on public-path requests, so only `True-Client-IP` will be present.

### 2. Replace all `realip_remote_addr()` call sites

**13 call sites total.** Two patterns:

#### Pattern A: Rate limiting (5 sites)

These use `ConnectionInfo` and chain into the rate limiter. They need `HttpRequest` added to the extractor list (where not already present) and the IP extraction replaced.

**Before:**
```rust
let denied = conn
    .realip_remote_addr()
    .or(conn.peer_addr())
    .and_then(|ip| limiter.try_connect(ip).ok())
    .is_none_or(|d| d == Decision::Denied);
```

**After:**
```rust
let ip = extract_client_ip(&req);
let denied = limiter.try_connect(&ip)
    .map_or(true, |d| d == Decision::Denied);
```

**Files:**

| File | Line | Extractor change needed? |
|------|------|-------------------------|
| `services/rate_limit_service.rs` | 56 | No — middleware has `ServiceRequest`, use `req.headers()` directly (see below) |
| `api/users/users_register.rs` | 48 | Check if `HttpRequest` is already in fn signature |
| `api/bookings/addons_post.rs` | 35 | Check if `HttpRequest` is already in fn signature |
| `api/queue_entries/call_ahead_post.rs` | 51 | **Yes — add `req: HttpRequest`**, currently only has `conn: ConnectionInfo` |
| `api/queue_entries/call_ahead_confirm.rs` | 29 | Check if `HttpRequest` is already in fn signature |

#### Pattern B: Audit trail (8 sites)

These extract IP as a string for logging. Same replacement, simpler:

**Before:**
```rust
let ip_address = conn
    .realip_remote_addr()
    .or(conn.peer_addr())
    .unwrap_or("unknown")
    .to_string();
```

**After:**
```rust
let ip_address = extract_client_ip(&req);
```

**Files:**

| File | Line | Notes |
|------|------|-------|
| `api/portal/portal_waivers_begin_post.rs` | 67 | Already has `req: HttpRequest` |
| `api/portal/portal_waivers_consent_post.rs` | 40 | Check for `HttpRequest` |
| `api/portal/portal_waivers_confirm_post.rs` | 40 | Check for `HttpRequest` |
| `api/portal/portal_waivers_sign_post.rs` | 52 | Check for `HttpRequest` |
| `api/portal/portal_waivers_begin_child_post.rs` | 77 | Check for `HttpRequest` |
| `api/portal/portal_waiver_record_get.rs` | 85 | Check for `HttpRequest` |
| `api/waivers/booking_waivers_accept_post.rs` | 53 | Check for `HttpRequest` |
| `api/waivers/booking_waivers_paper_post.rs` | 77 | Check for `HttpRequest` |

### 3. Rate limit middleware — special case

`rate_limit_service.rs` is middleware, not a handler. It doesn't use Actix extractors — it has a `ServiceRequest` directly. The `logic()` function currently takes `&ConnectionInfo`. Change it to take `&ServiceRequest` (or just the headers) so it can read the custom headers:

**Current signature:**
```rust
fn logic(shared: &Data<AppState>, connection: &ConnectionInfo) -> Decision
```

**New signature:**
```rust
fn logic(shared: &Data<AppState>, req: &ServiceRequest) -> Decision
```

Then inside:
```rust
fn logic(shared: &Data<AppState>, req: &ServiceRequest) -> Decision {
    let rate_limit_handle = match shared.rate_limiter() {
        RateLimiterStatus::Enabled(limiter) => limiter,
        RateLimiterStatus::Disabled => return Decision::Approved,
    };

    let ip = req.headers()
        .get("X-Real-Client-IP")
        .or_else(|| req.headers().get("True-Client-IP"))
        .and_then(|v| v.to_str().ok())
        .unwrap_or_default();

    if ip.is_empty() {
        return Decision::Denied;
    }

    rate_limit_handle.try_connect(ip).unwrap_or(Decision::Denied)
}
```

Update the call site in `call()` (line 88-91):
```rust
// Before:
let connection = req.connection_info().clone();
RateLimitService::<S>::logic(shared, &connection)

// After:
RateLimitService::<S>::logic(shared, &req)
```

### 4. Remove `ConnectionInfo` imports where no longer needed

After replacing all `realip_remote_addr()` calls, some handlers may no longer need `ConnectionInfo` in their extractor list. Remove unused imports and extractor parameters to keep handlers clean. Don't remove `ConnectionInfo` from handlers that use it for other purposes (check each file).

---

## What NOT to do

- **Do not read `X-Forwarded-For`** — it's spoofable on Render. The whole point of this change is to stop trusting it.
- **Do not add a new crate or dependency** — this is header reads with `req.headers().get()`, standard Actix-web.
- **Do not change api-contracts** — no contract change. This is internal plumbing.
- **Do not change the rate limiter crate** (`server/rate-limit/`) — the `try_connect(&str)` interface is fine. Only the IP extraction changes.

---

## Local dev

In local dev, neither `True-Client-IP` nor `X-Real-Client-IP` will be present (no Cloudflare, no BFF). The function returns `"unknown"`. The rate limiter will call `try_connect("unknown")` — all local requests share one bucket. This is fine for dev.

If per-IP testing is needed locally, set `True-Client-IP` manually in test requests (curl/Postman).

---

## Verification

- [ ] `cargo check -p uwz-server` passes
- [ ] `cargo test -p uwz-server` passes
- [ ] `/review-rs` passes
- [ ] Rate limiter uses `True-Client-IP` for direct requests, `X-Real-Client-IP` for BFF requests
- [ ] Waiver audit trail uses the same extraction
- [ ] Spoofed `X-Forwarded-For` headers are ignored
- [ ] Local dev still works (falls back to `"unknown"`)
- [ ] Grep for `realip_remote_addr` returns zero results after migration
