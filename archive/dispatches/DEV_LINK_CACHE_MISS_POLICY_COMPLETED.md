# Dispatch: Link cache miss → DB fallback policy

**Date:** 2026-03-27
**Workstream:** dev

## Problem

The redirect gateway currently returns 404 on cache miss with no DB fallback. Valid links created after server boot (or missed during startup load for any reason) will 404 until the cache is manually populated via `LinkCache::insert()`.

## Scenarios

1. **Cache hit** → 302 (current, correct)
2. **Cache miss → DB hit (active)** → 302 + populate cache (not implemented)
3. **Cache miss → DB hit (inactive)** → 410 Gone? 404? (not implemented)
4. **Cache miss → DB miss** → 404 (current, but only because all misses are 404)

## Needs

- DB fallback query on cache miss in the redirect handler
- Write-through: populate cache after successful DB fallback
- Policy decision on inactive campaign response code (410 vs 404)
- A cache sweeper or refresh mechanism for bulk updates (e.g., campaign status change affects all its links)

## Related

- The campaign CRUD handlers (not yet built) will need to call `LinkCache::insert()` / `LinkCache::remove()` as part of their write path
- `CachedLink::load_active()` already exists for the startup load — a single-link variant is needed for the fallback path

## Confidence

**High** on the need, **medium** on the policy (410 vs 404 for inactive campaigns is a UX/SEO decision)
