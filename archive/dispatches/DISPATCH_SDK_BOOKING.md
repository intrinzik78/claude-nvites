# DISPATCH: SDK Booking Preview Wrapper

**Date:** 2026-03-23
**From:** surface-website
**To:** server (SDK work)
**Confidence:** 0.95

## Problem

The server shipped `POST /v1/bookings/preview` in `f263c72`, which computes a line-item receipt (product × guests + addons + tax) server-side. The website needs this for the booking review step — it's the single source of truth for pricing math, preventing client/server divergence on tax rounding.

The SDK has no types or wrapper for this endpoint. `dist/openapi.json` is being regenerated now (`cargo xtask build-all`), which will produce the generated types. But the SDK still needs:

1. Type re-exports in `sdk-ts/src/types/index.ts`
2. A hand-written API wrapper in `sdk-ts/src/api/bookings.ts`
3. Barrel export from `sdk-ts/src/index.ts` (if types aren't already re-exported through existing barrel)

## Contract Types (from `api-contracts/src/bookings.rs`)

**Request body:**
```
BookingPreviewBody {
    product_id: i32,
    guest_count: u16,
    addons: Vec<AddonSelection>,  // default empty
}

AddonSelection {
    product_id: i32,
    quantity: u16,
}
```

**Response:**
```
BookingPreviewDto {
    product_name: String,
    price_per_person_cents: u32,
    guest_count: u16,
    line_items: Vec<LineItemDto>,
    subtotal_cents: u32,
    tax_cents: u32,
    tax_rate_display: String,
    total_cents: u32,
}

LineItemDto {
    name: String,
    quantity: u16,
    unit_price_cents: u32,
    line_total_cents: u32,
}
```

## Proposed Solution

### 1. Type re-exports (`sdk-ts/src/types/index.ts`)

After `openapi.json` regeneration, add to the domain DTOs section:

```typescript
export type BookingPreviewDto = components["schemas"]["BookingPreviewDto"];
export type LineItemDto = components["schemas"]["LineItemDto"];
```

And to the request bodies section:

```typescript
export type BookingPreviewBody = components["schemas"]["BookingPreviewBody"];
export type AddonSelection = components["schemas"]["AddonSelection"];
```

### 2. API wrapper (`sdk-ts/src/api/bookings.ts`)

Add to the existing `makeBookingsApi` return object:

```typescript
/** POST /v1/bookings/preview */
previewBooking(body: BookingPreviewBody): Promise<BookingPreviewDto> {
  return client.request<BookingPreviewDto>("POST", "/v1/bookings/preview", body);
},
```

Import the new types at the top of the file:

```typescript
import type {
  // ... existing imports ...
  BookingPreviewBody,
  BookingPreviewDto,
} from "../types/index.js";
```

### 3. Verification

```bash
cd sdk-ts && npm run build && npm test
```

## Why This Matters

The website's `/book` review step currently shows `price_cents` from the product — that's the per-person rate. It doesn't compute a total, show tax, or handle addons. The preview endpoint gives us the exact amount the customer will be charged, computed server-side. This is a prerequisite for the payment integration (DISPATCH_PAYMENTS.md).

## What Surface-Website Will Do With It

Once the SDK wrapper exists:
1. Add a BFF endpoint (`/book/preview/+server.ts`) that proxies to `sdk.previewBooking()`
2. Call it from the booking ViewModel when advancing to the review step
3. Display the receipt (line items, subtotal, tax, total) on BookingReview
4. Pass the total through to the payment step (future)
