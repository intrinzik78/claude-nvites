# Dispatch: Bounded negative cache for gateway cold path

**Date:** 2026-03-30
**Workstream:** dev

## Problem

Cache misses for nonexistent codes hit the DB every time (40-50ms cross-region round trip) until the per-IP rate limiter kicks in. The rate limiter bounds per-IP abuse, but distributed bot scans — many IPs hitting different nonexistent codes — bypass per-IP limits while each consuming a DB connection pool slot. At sufficient volume, this exhausts the connection pool and blocks legitimate cold-path lookups.

## Suggested Solution

Add a separate bounded negative cache — checked after the warm cache and before the DB fallback. On a DB miss (code not found), insert the code into the negative cache. Subsequent requests for the same code return 404 from memory without touching the DB.

**Structure:** Separate from the warm `LinkCache`. Different semantics — TTL-based expiry (10s + 50% jitter), not activity-based eviction. A sharded `HashMap<String, Instant>` with its own sweeper, or a simpler bounded structure. The aggressive TTL keeps memory growth small — at most 10 seconds of unique invalid codes accumulate before being purged.

**Lookup order:** warm cache → negative cache → DB fallback.

**Sweep interval:** 10 seconds. Entries older than their TTL are evicted.

**Bounded size:** Consider capping at 10,000 entries as a hard ceiling. If the cache is full, either evict the oldest entry or skip caching (fail open). A circular buffer was considered but adds complexity — a simple HashMap with aggressive sweeping likely suffices given the 10s TTL.

**New code visibility:** A newly created code would be unreachable if it was recently looked up and negatively cached. The 10-15s TTL makes this acceptable — the code becomes reachable within seconds.

## Reasoning

Two complementary protections:
- **Rate limiter:** bounds per-IP request volume (protects CPU/bandwidth)
- **Negative cache:** bounds per-code DB queries (protects connection pool)

The warm cache self-curates via write-through and sweeping. The negative cache protects against the gap the warm cache doesn't cover — codes that don't exist and never will.

## Confidence

**High** on the problem and approach. **Medium** on the exact structure — keep it simple, a `HashMap<String, Instant>` with a sweeper is likely sufficient. Don't over-engineer the data structure.
