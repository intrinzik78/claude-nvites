# DISPATCH: Document Timestamp Column Bug

**Date:** 2026-03-15
**Target:** server branch
**Severity:** Runtime failure — affected endpoints will error on execution

---

## Problem

Three methods in `server/api/src/types/waivers/waiver.rs` query the `document` table using `` d.`timestamp` AS created_at `` but the `document` table column is `created_at`, not `timestamp`. The column `timestamp` does not exist on the `document` table.

**Affected methods:**
- `fetch_document()` (~line 1006)
- `fetch_document_by_uuid()` (~line 1029)
- `verify_signed_document()` (~line 1083)

**Introduced:** commit `d80a2b4` (waiver document retrieval + integrity verification)

**Impact:** Any call to these methods will produce a MySQL column-not-found error at runtime. This affects:
- `GET /v1/portal/waivers/{uuid}` (signed record retrieval — calls `fetch_document` + `verify_signed_document`)
- `GET /v1/waivers/document/{uuid}` (public document retrieval — calls `fetch_document_by_uuid`)

These endpoints were built but may not have been exercised against a live database.

## Fix

In all three methods, change:

```sql
d.`timestamp` AS created_at
```

to:

```sql
d.created_at
```

The `DocumentContentRow` struct already maps the field as `created_at: DateTime<Utc>`, so the Rust side needs no changes — only the SQL strings.

## Verification

After fixing, hit both endpoints against the local DB:
1. `GET /v1/waivers/document/{uuid}` with a valid document UUID
2. `GET /v1/portal/waivers/{uuid}` with a signed waiver UUID (requires auth)
