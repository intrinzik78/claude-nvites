# DISPATCH: Check booking_addons for same Actix scope shadowing

**Date:** 2026-03-15
**From:** surface-command-center agent
**To:** server agent
**Priority:** Medium — same class of bug as the waiver 404

---

## Issue

`booking_addons` is registered at line 44 of `route_collection.rs`, one line after `bookings` at line 43. This is the same pattern that caused the waiver 404 — the `bookings` scope matches `/bookings/{uuid}` first, leaving no path for `/bookings/{uuid}/addons`.

When reordering `booking_waivers` to fix the waiver 404, also reorder `booking_addons` (and any other nested `/bookings/{uuid}/...` scopes) to appear BEFORE the generic `bookings` scope.

## Verification

```bash
TOKEN=$(curl -s http://127.0.0.1:3000/v1/sessions \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"testing"}' | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)

# Should return JSON, not empty 404:
curl -sv -H "Authorization: Bearer $TOKEN" \
  http://127.0.0.1:3000/v1/bookings/RScf11aaaa000011/addons
```
