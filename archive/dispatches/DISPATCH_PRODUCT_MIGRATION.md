# Dispatch: First real migration — product catalog seed

**Date:** 2026-03-21
**From:** dev session (migration flatten + seed script fix)
**To:** server worktree (next session)
**Priority:** Medium — blocks `seed_dev_data.sql` from working on a fresh DB, but doesn't block server development

---

## Problem

`seed_dev_data.sql` creates bookings and queue entries that reference `booking_product` IDs 1–7 and `booking_resource` IDs 1–5. Both tables are empty after the migration flatten. Running the seed script on a fresh DB fails with FK violations.

These aren't test fixtures — they're the business's actual products (paintball packages, party rooms, axe lanes) and physical resources (fields, rooms, lanes). They existed in the old dev database from manual Workbench use but were never formalized in a migration.

## Proposed Solution

Create `20260321XXXXXX_seed_product_catalog.sql` as the first real migration after the flattened baseline. This migration seeds:

### `booking_product` (7 rows)

The seed script comments document the expected products:

| ID | Name | Category | Resource Type | Duration |
|----|------|----------|---------------|----------|
| 1 | Std Paintball | Paintball (1) | PaintballMarker (0) | 60m |
| 2 | Open Play | Paintball (1) | PaintballMarker (0) | 180m |
| 3 | Bday 2hr | Parties (2) | PartyRoom (1) | 120m |
| 4 | Bday 3hr | Parties (2) | PartyRoom (1) | 180m |
| 5 | Corporate | Corporate (4) | PaintballMarker (0) | 240m |
| 6 | GellyBall | GellyBall (3) | PaintballMarker (0) | 120m |
| 7 | Axe | Axe Throwing (5) | AxeLane (2) | 60m |

**User input needed:** Real names, descriptions, prices (`price_cents`), `min_guests`, `max_guests`. The table above is derived from seed script comments — the user knows the actual product line.

### `booking_resource` (5 rows)

| ID | Name | Resource Type | Capacity |
|----|------|---------------|----------|
| 1 | Field A | PaintballMarker (0) | ? |
| 2 | Field B | PaintballMarker (0) | ? |
| 3 | Party Room 1 | PartyRoom (1) | ? |
| 4 | Axe Lane 1 | AxeLane (2) | ? |
| 5 | Axe Lane 2 | AxeLane (2) | ? |

**User input needed:** Real names, descriptions, capacities. The names above are from seed script comments.

### After migration

Update `server/scripts/seed_dev_data.sql` to confirm the IDs match (they should — the migration will use explicit IDs). Add a comment at the top noting the dependency: "Requires: 20260321XXXXXX_seed_product_catalog.sql".

## Reasoning

- **These are production seed data, not dev data.** Every environment (dev, staging, prod) needs the product catalog to function. Bookings reference products via FK. The command center displays products. The website will eventually list them.
- **Migration, not application code.** Products could be managed via API later, but the initial catalog must exist before the first booking can be created. A seed migration is the right vehicle — same pattern as `booking_resource_type`, `category`, `booking_status`, etc.
- **Explicit IDs.** The seed script and any future workflow definitions reference products by ID. Using explicit IDs in the INSERT (not AUTO_INCREMENT) ensures consistency across environments.

## Confidence

- **Structure: High.** The tables exist, the FKs are defined, the pattern matches other seed data in the flattened migration.
- **Data: Low.** The product names, prices, guest limits, and resource capacities are business decisions. The user stated they know their product line — this dispatch needs their input to fill in the real values.

## After completion

- Run `seed_dev_data.sql` on a fresh DB to verify it succeeds
- Run `cargo test` (shouldn't be affected but verify)
- Consider whether `booking_product` and `booking_resource` should also appear in the xtask `db-reset --seed` path
