# Dispatch: API_BASE_URL startup guard with automatic maintenance mode

**Date:** 2026-03-20
**From:** dev session (server-oriented)
**To:** surface-website worktree
**Priority:** High — prevents cryptic deploy failures

---

## Problem

`API_BASE_URL` is a runtime env var (`$env/dynamic/private`, DEC-146) read in two places:

1. `hooks.server.ts:123` — `new URL(env.API_BASE_URL!).origin` for CSP
2. `lib/api/index.ts:5` — `sdkCreateClient(env.API_BASE_URL!, ...)` for BFF requests

Both use non-null assertions (`!`). If the var is missing on Railway, the website crashes on the first request with a cryptic error. If it points to localhost in production, every API call silently fails (connection refused) and pages render empty or 500.

## Proposed Solution

**Confidence: High** — maintenance mode infrastructure already exists and works (`PUBLIC_MODE === 'MAINTENANCE'` gate in hooks.server.ts:125-127).

Add a validation function at module level in `hooks.server.ts` that runs once on server startup (before the first request). The function should:

1. **Check for missing/empty `API_BASE_URL`** → override to maintenance mode
2. **Check for localhost values when `PUBLIC_MODE` is `LIVE`, `STAGING`, or `PRODUCTION`** → override to maintenance mode
3. **Log a clear `console.error`** explaining why maintenance mode was activated, so the operator knows what to fix

### Localhost patterns to match

Match the hostname portion of the URL against all well-known localhost values. These are the addresses that resolve to the loopback interface and would never be correct for a deployed API server:

- `localhost`
- `127.0.0.1`
- `0.0.0.0`
- `[::1]` (IPv6 loopback)
- `::1` (IPv6 loopback without brackets)
- `host.docker.internal` (Docker host — valid in Docker dev, never in Railway)

### Implementation sketch

```typescript
/**
 * Validates API_BASE_URL at server startup. Returns the validated URL string,
 * or null if the value is missing or points to a loopback address in a
 * production-like mode.
 *
 * When null is returned, the caller should force maintenance mode — the BFF
 * cannot reach the API server, so every page load would fail.
 *
 * Localhost patterns matched: localhost, 127.0.0.1, 0.0.0.0, [::1], ::1,
 * host.docker.internal. These are loopback or Docker-host addresses that
 * never resolve to a real API server in deployed environments.
 *
 * In DEV mode, localhost values are allowed (that's the normal local setup).
 * In LIVE/STAGING/PRODUCTION/CONSTRUCTION, they trigger maintenance mode.
 */
const LOOPBACK_HOSTNAMES = new Set([
  'localhost',
  '127.0.0.1',
  '0.0.0.0',
  '[::1]',
  '::1',
  'host.docker.internal',
]);

function validateApiBaseUrl(raw: string | undefined, mode: SiteMode): string | null {
  if (!raw || raw.trim() === '') {
    console.error('[startup] API_BASE_URL is not set — entering maintenance mode');
    return null;
  }

  let parsed: URL;
  try {
    parsed = new URL(raw);
  } catch {
    console.error(`[startup] API_BASE_URL is not a valid URL: "${raw}" — entering maintenance mode`);
    return null;
  }

  const isDevMode = mode === 'DEV';
  if (!isDevMode && LOOPBACK_HOSTNAMES.has(parsed.hostname)) {
    console.error(
      `[startup] API_BASE_URL points to loopback (${parsed.hostname}) in ${mode} mode — entering maintenance mode`
    );
    return null;
  }

  return raw;
}
```

Then at module level:

```typescript
const validatedApiUrl = validateApiBaseUrl(env.API_BASE_URL, siteMode);
const forceMaintenance = validatedApiUrl === null;
```

And in the handle function, expand the maintenance gate:

```typescript
if (siteMode === 'MAINTENANCE' || forceMaintenance) {
  return maintenanceResponse();
}
```

Also update `lib/api/index.ts` to use the validated URL instead of `env.API_BASE_URL!`.

### What NOT to do

- Don't crash the process. The whole point is graceful degradation.
- Don't check localhost in DEV mode — `http://localhost:3000` is the correct dev value.
- Don't add a new maintenance page — the existing `maintenanceResponse()` is correct as-is.

## Alternative considered

**Crash on boot with `process.exit(1)`** — Rejected. Maintenance mode is better UX (users see a real page, not a browser connection error) and better ops (Railway shows the service as running, logs explain why).

## References

- DEC-146: `API_BASE_URL` uses `$env/dynamic/private`
- `hooks.server.ts` lines 122-155: existing handle function
- `lib/api/index.ts` line 5: SDK client creation
- `docs/PRE_LAUNCH.md`: "API_BASE_URL startup guard" open item
- `docs/STARTUP_GATES.md`: website env vars table documents `API_BASE_URL`

## Additional: CSP connect-src hostname leak

**While you're in hooks.server.ts**, fix the CSP `connect-src` leak (lines 139-146).

Currently the code appends `apiOrigin` (e.g. `http://server.railway.internal:3000`) to the browser's CSP `connect-src` directive. The browser can't reach this address (internal DNS only), but it exposes the internal Railway hostname to anyone inspecting response headers.

**Fix:** Remove the CSP append block entirely. The BFF makes all API calls server-side — the browser never calls the API directly, so `connect-src` doesn't need the API origin. If there's a legitimate reason to keep it (e.g., client-side fetch to the API in some future flow), gate it behind an env var for a public-facing API URL instead.

**Confidence: High** — the handoff from 2026-03-19 identified this as information leakage. No browser makes direct requests to the API server. The BFF pattern means all API traffic is server-to-server.

**Reference:** `docs/PRE_LAUNCH.md` — "CSP connect-src leaks internal hostname" open item. Mark resolved after fix.

## After completion

- Mark `API_BASE_URL` startup guard as resolved in `docs/PRE_LAUNCH.md`
- Mark CSP `connect-src` hostname leak as resolved in `docs/PRE_LAUNCH.md`
- Run `/review-ts` on modified files
