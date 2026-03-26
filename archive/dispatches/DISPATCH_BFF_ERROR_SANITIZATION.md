# DISPATCH: BFF Error Message Sanitization

**Date:** 2026-03-15
**Target:** surface-website

---

## Problem

All four waiver BFF endpoints (`/waiver/api/begin`, `consent`, `confirm`, `sign`) forward `err.message` from the backend SDK verbatim to the client:

```ts
return json(
    { success: false, error: err.message, code: err.reason?.code },
    { status: err.code },
);
```

If the Rust backend ever returns an error message containing internal details (table names, constraint violations, SQL context), these get forwarded to the browser. The ViewModel maps known error codes (4013, 4016, 4017, 4018, 4019, 4020) to user-friendly messages, but unknown codes fall through to `error = message || 'Something went wrong.'` — displaying the raw backend message.

## Fix

For unknown/unexpected error codes in the BFF layer, return a generic message instead of forwarding the backend's message. Only forward `err.message` for known 4xx status codes where the message is user-facing by design. For 500+ codes, always return `'Something went wrong.'`.

## Files

- `surface-website/src/routes/(public)/waiver/api/begin/+server.ts`
- `surface-website/src/routes/(public)/waiver/api/[uuid]/consent/+server.ts`
- `surface-website/src/routes/(public)/waiver/api/[uuid]/confirm/+server.ts`
- `surface-website/src/routes/(public)/waiver/api/[uuid]/sign/+server.ts`

## Origin

Security audit finding M-1 (medium priority, defense-in-depth).
