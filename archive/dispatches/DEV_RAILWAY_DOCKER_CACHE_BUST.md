# DEV_RAILWAY_DOCKER_CACHE_BUST

**Date:** 2026-03-30
**Severity:** High
**Scope:** Any Railway-deployed Dockerfile that COPYs source files

## Problem

Railway's Docker builder aggressively caches COPY layers and may not detect source file changes between deploys. This results in deploying stale builds — the build log shows every layer as `cached` and the output image digest is identical to the previous deploy, even when the source code has changed.

Observed behavior:
- `COPY surface-website/ surface-website/` cached despite file changes in that directory
- `RUN pnpm build` cached because the COPY it depends on didn't invalidate
- Redeploying (even with "clear cache" intent) produced the identical image digest
- The deployed site served old code while Railway reported the correct commit SHA

## Fix

Add an `ARG CACHE_BUST` immediately before the first `COPY` of source files. This invalidates all downstream layers when the value changes.

```dockerfile
# Before source file copies
ARG CACHE_BUST
COPY src/ src/
```

On Railway, set `CACHE_BUST` as a build-time variable. Change its value (timestamp, commit SHA, anything) to force a full rebuild when Railway's cache is stale.

## Why This Matters

- Silently deploys old code — no error, no warning
- Build logs show the correct commit SHA, so it looks like it deployed correctly
- Only detectable by observing runtime behavior doesn't match expected changes
- Payment-critical and UX-critical changes can be silently dropped

## Action

Apply this pattern to any other Railway-hosted Dockerfile. The fix is a 2-line addition with zero runtime impact.
