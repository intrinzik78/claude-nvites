# Website Payment Integration

**Date:** 2026-03-24
**Workstream:** surface-website
**Depends on:** Server Slice 3 (charge-at-booking) — shipped on `server` branch
**Status:** Payment integration shipped. Remaining items are `/book` + `/prices` follow-ups merged from `DISPATCH_BOOK_PAGE.md`.

## Implementation Status

All payment work is **shipped**. Uses raw Accept.js `dispatchData()` with our own form inputs (not hosted iframe fields). Card data is tokenized client-side — never reaches the UWZ server. PCI SAQ A-EP.

| Item | Status | Notes |
|------|--------|-------|
| Accept.js script loading | Done | Dynamic loader (`loadAcceptJs.ts`), not static `app.html` tag — better for conditional loading |
| PaymentForm component | Done | Card number, expiration, CVV; `Accept.dispatchData()` tokenization |
| Nonce generation flow | Done | Full flow: button → spinner → tokenize → submit → result handling |
| BFF endpoint (`/book/+server.ts`) | Done | Passes `payment` + `addons`, returns full `BookingDto`, maps error codes |
| BookingReview (step 4) | Done | Receipt + PaymentForm conditional on `vm.paymentEnabled`; "Pay & Book" / "Confirm Booking" toggle |
| BookingConfirm (step 5) | Done | 201 Approved, 202 HeldForReview, non-payment paths — all three states render |
| ViewModel payment state | Done | `paymentEnabled`, `paymentConfig`, `submitBooking(nonce?)`, `bookingResult` with payment |
| Environment variables | Done | `PUBLIC_AUTHORIZENET_SANDBOX`, `PUBLIC_AUTHORIZENET_LOGIN_ID`, `PUBLIC_AUTHORIZENET_CLIENT_KEY` — declared in `env.d.ts`, wired in `+page.server.ts` |
| Step 3→4 loading indicator | Done | `previewLoading` state with "Calculating total…" message |

### `/review-ts` pass: COMPLETE (2026-03-24)

Full review of PaymentForm.svelte, BookingReview.svelte, BookingConfirm.svelte, bookingFlow.svelte.ts, bookingApi.ts, loadAcceptJs.ts, +server.ts, +page.server.ts, accept.d.ts, bookingConstants.ts. Two warnings fixed: `loadAcceptJs` cached rejection reset, duplicate `formatCents` replaced with shared `formatPrice`. 202 HeldForReview path verified end-to-end (SDK treats 202 as success, BFF passes through, UI renders correctly).

## What the Server Expects

### POST /v1/bookings — updated contract

`CreateBookingBody` now accepts two new fields:

```typescript
{
  product_id: number;
  guest_name: string;
  guest_email: string;
  guest_phone?: string;
  guest_count: number;
  start_at: string;       // ISO 8601
  notes?: string;
  payment?: {             // required when payment_service Enabled
    data_descriptor: string;  // always "COMMON.ACCEPT.INAPP.PAYMENT"
    data_value: string;       // opaque nonce from Accept.js
  };
  addons?: Array<{        // optional inline addons
    product_id: number;
    quantity: number;
  }>;
}
```

### Response codes

| Code | Meaning | Client action |
|------|---------|--------------|
| 201  | Approved — booking confirmed, `payment` field populated on `BookingDto` | Show confirmation (step 5) |
| 202  | HeldForReview — booking exists but pending fraud review | Show "under review" message, NOT confirmation |
| 422 (7000) | Declined — card was rejected | Show decline message, let user retry with different card |
| 422 (7004) | Nonce required — payment_service is Enabled but no nonce sent | Bug — should not happen if UI is correct |
| 422 (7003) | Nonce invalid — malformed or expired nonce | Show "payment token expired, please try again" |
| 502 (7001) | Gateway error — Authorize.Net was unreachable | Show "payment system temporarily unavailable" |

Error responses use the standard `ApiResult` error envelope with `error.data.code` for the error number.

### BookingDto response — payment field

When payment succeeds (201), `BookingDto.payment` is populated:

```typescript
{
  transaction_id: string;
  status: "Approved" | "Declined" | "Error" | "HeldForReview";
  subtotal_cents: number;
  tax_cents: number;
  total_cents: number;
  card_type?: string;   // "Visa", "Mastercard", etc.
  last_four?: string;   // "1234"
}
```

When payment_service is Disabled or on non-payment paths, `payment` is `undefined` (omitted from JSON).

## SDK State

All types are generated and barrel-exported from `@uwz/sdk-ts`:
- `PaymentNonce`, `PaymentSummaryDto`, `TransactionStatus`, `TransactionType`
- `CreateBookingBody` already includes `payment` and `addons` fields
- `BookingDto` already includes optional `payment` field
- `sdk.createBooking(body)` — no wrapper change needed, types flow through

The `sdk.getBookingPreview(body)` endpoint is already live and supports addons.

## What NOT to Build

- **Void/refund UI** — that's Slice 4 (server) + future command center work
- **Webhook handling** — server Slice 5
- **Staff payment visibility** — server Slice 6 + command center
- **Addon selection UI** — the `addons` field is supported in the contract but the `/book` page doesn't have addon selection yet. Pass an empty array for now.

## Verification

1. Load `/book`, go through steps 1-3
2. Step 4: payment form renders, preview shows correct total
3. Submit with sandbox test card `4111111111111111` → 201, step 5 shows confirmation with card details
4. Submit with amount that triggers decline ($5.01 total) → 422, decline message, form re-enabled
5. Submit with expired/invalid nonce → 422 (7003), "try again" message
6. With `payment_service` Disabled: no payment form, existing flow works unchanged

## Sandbox Testing

Authorize.Net sandbox test card numbers:
- `4111111111111111` — Visa, approves
- `5424000000000015` — Mastercard, approves
- `4222222222222` — Visa, declines (triggers declined response)

Use sandbox env vars during development. The server's `AUTHORIZENET_SANDBOX=true` points to the sandbox API.

---

## Remaining Work (merged from DISPATCH_BOOK_PAGE.md)

Items below are from the original `/book` + `/prices` dispatch. The pricing pages (Phase 1) and booking page rebuild (Phase 2) are complete. Payment integration (Phase 4) is complete (above). These are the surviving items.

### Phase 3: Non-tier sub-pages — NOT STARTED

`/prices/food`, `/prices/gear`, `/prices/membership` — lower priority, smaller organic footprint. Redirects currently point to `/prices` parent. Per RT-9, each sub-page must ship with its redirect update.

Product data: `server/migrations/20260321120000_seed_product_catalog.sql`
Tier definitions: `surface-website/src/lib/data/tiers.ts`

### Owner decisions pending

1. **Home page "See Prices" link.** With `/prices` as a first-class section, should the home page body include a "See Prices" link alongside "Book Now"? Nav already links to `/prices`, but body links carry more internal linking weight. Could strengthen `/prices`' SEO position or dilute the primary CTA.

2. **`/hours` label.** The nav currently has `{ href: '/hours', label: 'Hours & Pricing' }` under "Plan Your Visit." With `/prices` as its own section, does `/hours` still say "& Pricing" or just "Hours"?

3. ~~**202 "HeldForReview" UX copy.**~~ Approved (2026-03-24): "Your payment is being reviewed. We'll email you once it's confirmed."

### Red Team findings (open)

| RT | Finding | Status |
|----|---------|--------|
| RT-4 | Non-tier pages need content | Deferred to Phase 3 |
| RT-9 | Non-tier redirects bundled with launches | Documented — each sub-page ships with its redirect update |

### Package features verification

`tiers.ts` contains `PACKAGE_FEATURES` with drafted inclusions per package (Basic/Deluxe/Elite). Flagged with a TODO for owner verification before launch.

## Decisions Made During `/book` + `/prices` Build

### Tier selection is URL-driven on `/book`
The `?tier=` query param owns the tier state. Selecting a tier pushes a history entry via `goto('/book?tier=groups')`. Browser back/forward navigates between tier states. The ViewModel resets to package selection if the URL tier changes while past step 1.

### Product @id canonical lives on `/prices/[tier]`
Each product gets a canonical `@id` like `https://urbanwarzonepaintball.com/prices/individual#product-1`. The `/book` page references these same `@id`s in its JSON-LD. Google deduplicates by `@id`.

### Non-tier redirects temporarily point to `/prices` parent
`/rental-prices/food-pricing`, `/rental-prices/gear-requirements`, `/rental-prices/monthly-vip-membership`, `/rental-prices/membership-terms-conditions`, and `/rental-prices/feed` all redirect to `/prices` until Phase 3 builds dedicated sub-pages.

## Reference Files

| File | Purpose |
|------|---------|
| `docs/URL_CHOICE.md` | Full SEO analysis with Search Console + GA4 data |
| `docs/SVELTE_STYLE_GUIDE.md` | Code conventions |
| `docs/WEB_UX.md` | Component layering, MVVM, 8-stage workflow |
| `.claude/skills/seo/seo.json` | Route classifications, structured data types, crawl config |
| `surface-website/src/lib/data/tiers.ts` | Tier definitions, product filtering, package features |
| `surface-website/src/lib/data/redirects.ts` | Current redirect map |
| `surface-website/src/routes/(public)/book/` | Booking page + wizard + payment |
| `surface-website/src/routes/(public)/prices/` | Pricing pages + tier detail |
| `docs/DISPATCH_PAYMENTS.md` | Server payment integration plan (6 slices) |
| `archive/dispatches/DISPATCH_BOOK_PAGE.md` | Archived — original `/book` + `/prices` dispatch |
