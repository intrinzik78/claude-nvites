# Dispatch: Build `/book` + `/prices` Pages

**Date:** 2026-03-22
**Branch:** `surface-website`
**Status:** Phase 1 + Phase 2 complete — presentation/copy polish remaining
**Confidence:** 0.92 — architecture shipped, funnel tested, SEO verified

## What We Built

Two route trees replacing the old site's booking funnel:

- **`/prices`** — pricing pages (absorbs old `/rental-prices/*`)
- **`/book`** — high-intent booking page with guided tier funnel (absorbs old `/paintball-reservations/`)

These are **separate concerns**. `/prices` answers "how much does it cost?" `/book` answers "I'm ready to reserve." The old site already had this separation — we preserved it under cleaner URLs.

## Why This Architecture

Full reasoning is in `docs/URL_CHOICE.md`. Key findings from 16 months of Search Console data and 5 months of GA4:

1. **The two old page families serve distinct search intent clusters** with only 11 overlapping queries out of 120+ unique clicked queries. Forcing them into one page fights the data.

2. **The rental-prices funnel is 3.3x larger** than the reservations funnel (1,073 vs 321 organic sessions). Google ranks sub-pages independently — `/rental-prices/individual-rental-prices` alone has 433 organic sessions.

3. **URL slug keywords don't drive rankings.** Zero of the top 10 queries to `/paintball-reservations/` contain "reservations." Google ranks these pages on domain signals, content, and local relevance.

4. **Organic search is not the primary booking channel.** The homepage drives 4,922 organic sessions. The booking funnel is driven by internal navigation, not organic landing on sub-pages. `/Thank-You` had 65 organic-attributed sessions with 0 new users — every completed booking started elsewhere.

5. **Preserving sub-page structure as `/prices/[tier]`** gives the tightest possible redirect mapping (pricing detail → pricing detail), preserving Google's independent rankings for each page.

## Route Architecture

```
/prices                    ← overview/selection page (absorbs /rental-prices/)
/prices/individual         ← 1-9 guests, all 3 packages (absorbs /rental-prices/individual-rental-prices)
/prices/groups             ← 10-29 guests, all 3 packages (absorbs /rental-prices/medium-group-discount)
/prices/large-groups       ← 30+ guests, all 3 packages (absorbs /rental-prices/large-group-discount)
/prices/food               ← food pricing — Phase 3 (redirects to /prices until built)
/prices/gear               ← gear requirements — Phase 3 (redirects to /prices until built)
/prices/membership         ← VIP membership — Phase 3 (redirects to /prices until built)
/book                      ← booking wizard with guided tier funnel
/book?tier=individual      ← pre-selected tier (linked from /prices/[tier] CTAs)
/book?tier=groups          ← pre-selected tier
/book?tier=large-groups    ← pre-selected tier
```

### Product Catalog Mapping

The database has 9 products: 3 packages (Basic, Deluxe, Elite) × 3 guest tiers (1-9, 10-29, 30+). These map identically to the old site's tier structure.

| Old tier | New tier slug | Guest range | Package prices (per person) |
|---|---|---|---|
| Individual | `/prices/individual` | 1-9 | Basic $34.95, Deluxe $39.95, Elite $49.95 |
| Medium group | `/prices/groups` | 10-29 | Basic $29.95, Deluxe $39.95, Elite $49.95 |
| Large group | `/prices/large-groups` | 30+ | Basic $24.95, Deluxe $34.95, Elite $44.95 |

Product data: `server/migrations/20260321120000_seed_product_catalog.sql`
Tier definitions: `surface-website/src/lib/data/tiers.ts`

### How the Pages Relate

```
/prices (overview) ──→ /prices/individual ──→ CTA: /book?tier=individual
                   ──→ /prices/groups     ──→ CTA: /book?tier=groups
                   ──→ /prices/large-groups ──→ CTA: /book?tier=large-groups

Homepage ──→ "Book Now" ──→ /book (guided funnel: pick group size → see 3 packages → book)
```

`/book` has a two-beat guided funnel replicating the old `/rental-prices/` flow:
1. **Beat 1:** "How many players?" — three group-size buttons (1-9, 10-29, 30+)
2. **Beat 2:** Shows 3 packages for that tier — user picks one → booking wizard continues

Tier selection is URL-driven (`?tier=` param) so browser back/forward navigates between tier states. The ViewModel resets to Step 1 if the URL tier changes while past the package selection step.

## Phase Status

### Phase 1: `/prices` route tree — COMPLETE

**Files created:**
- `surface-website/src/lib/data/tiers.ts` — tier definitions, product filtering, package features
- `surface-website/src/routes/(public)/prices/+layout.svelte` — atmospheric layout
- `surface-website/src/routes/(public)/prices/+page.server.ts` — SSR load, no prerender
- `surface-website/src/routes/(public)/prices/+page.svelte` — overview with tier cards, JSON-LD AggregateOffer
- `surface-website/src/routes/(public)/prices/_components/TierCard.svelte` — tier card for overview
- `surface-website/src/routes/(public)/prices/[tier]/+page.server.ts` — SSR load, tier validation, 404 on invalid slug
- `surface-website/src/routes/(public)/prices/[tier]/+page.svelte` — tier detail with package comparison, canonical Product @id
- `surface-website/src/routes/(public)/prices/[tier]/_components/PackageDetailCard.svelte` — package card with features, CTA to /book?tier=

**Files modified:**
- `redirects.ts` — 12 redirect targets updated per map
- `redirects.test.ts` — test expectations updated
- `GlobalNav.svelte` — Packages → Prices
- `SiteFooter.svelte` — Packages → Prices
- `sitemap.xml/+server.ts` — added /prices + 3 tier sub-pages
- `seo.json` — replaced /packages with /prices + 3 tier route entries, updated /book entry

### Phase 2: `/book` page rebuild — COMPLETE (presentation polish remaining)

**Files created:**
- `surface-website/src/routes/(public)/book/_components/TierSelect.svelte` — "How many players?" group-size picker

**Files modified:**
- `book/+page.server.ts` — reads `?tier=` param, validates against known slugs, passes `preselectedTier`
- `book/+page.svelte` — added crawlable intro section with "reservations" language, price signal, /prices link; passes preselectedTier to BookingFlow; updated title/description and JSON-LD @id references
- `BookingFlow.svelte` — accepts/forwards `preselectedTier`; `$effect` syncs ViewModel with URL tier state (resets wizard if tier changes via browser nav)
- `PackageSelect.svelte` — two-beat flow: tier picker → filtered 3-package grid; tier derived from URL `$derived(preselectedTier)`, selection via `goto()` for browser history support; "Change group size" link
- `bookingFlow.svelte.ts` — added `resetToPackageSelect()` method
- `PackageDetailCard.svelte` — CTAs link to `/book?tier={slug}` for tier handoff

### Phase 3: Non-tier sub-pages — NOT STARTED

`/prices/food`, `/prices/gear`, `/prices/membership` — lower priority, smaller organic footprint. Redirects currently point to `/prices` parent. Per RT-9, each sub-page must ship with its redirect update.

## Remaining Work

- ~~**Presentation/copy polish**~~ — completed 2026-03-23. Package features verified, cinematic tuning done, mobile pass done.
- **Loading indicator on step 3→4 transition** — `advanceToReview()` now makes a network call (booking preview) but the Continue button has no spinner/loading state while the preview fetches. On slow connections the form appears frozen. Add loading treatment matching the Confirm button pattern.
- **Open question 1:** Home page "See Prices" link — decision pending
- **Open question 2:** `/hours` label — "Hours & Pricing" vs "Hours" — decision pending

## Phase 4: Payment Integration

**Dependency:** Server Slices 1-3 from `docs/DISPATCH_PAYMENTS.md` must ship first. This phase cannot start until `CreateBookingBody` has the `payment` field and the charge flow is live. The server agent will update `sdk-ts/src/types/generated.d.ts` via `cargo xtask build-all` — the website agent consumes the updated types.

### Accept.js — Client-Side Card Tokenization

Authorize.Net's Accept.js tokenizes card data in the browser. Card numbers never reach our server (PCI SAQ-A compliance).

**Script inclusion** (in `app.html` or a payment-specific component):
```
Sandbox: https://jstest.authorize.net/v1/Accept.js
Production: https://js.authorize.net/v1/Accept.js
```

Gate on an env var (e.g. `PUBLIC_AUTHORIZENET_SANDBOX`) to switch URLs. When `payment_service` is disabled on the server, the script doesn't need to load.

**Tokenization flow:**
```typescript
// Accept.js exposes window.Accept
Accept.dispatchData({
  authData: {
    clientKey: PUBLIC_AUTHORIZENET_CLIENT_KEY,  // public key, safe in browser
    apiLoginID: PUBLIC_AUTHORIZENET_LOGIN_ID    // public login ID
  },
  cardData: {
    cardNumber: '4111111111111111',
    month: '12',
    year: '2030',
    cardCode: '123'
  }
}, (response) => {
  if (response.messages.resultCode === 'Error') {
    // Show validation errors to customer
    return;
  }
  // response.opaqueData.dataDescriptor = "COMMON.ACCEPT.INAPP.PAYMENT"
  // response.opaqueData.dataValue = opaque nonce (one-time use, ~15 min expiry)
});
```

**Env vars needed on the website surface:**
- `PUBLIC_AUTHORIZENET_CLIENT_KEY` — public client key from Authorize.Net dashboard
- `PUBLIC_AUTHORIZENET_LOGIN_ID` — API login ID (this is the public-facing ID, not the transaction key)
- `PUBLIC_AUTHORIZENET_SANDBOX` — "true"/"false" for script URL selection

### Wizard Changes

The booking wizard gains a **payment step** between Guest Info and Review. The step sequence becomes:

```
Package → Date & Time → Guest Info → Payment → Review → Confirmed
```

Update `bookingConstants.ts` to add `PAYMENT` between `GUEST_INFO` and `REVIEW`. Update `STEP_LABELS` accordingly.

**Payment step responsibilities:**
1. Render a card form (card number, expiry month/year, CVV)
2. On "Continue": call `Accept.dispatchData()` to tokenize
3. On success: store the nonce (`dataDescriptor` + `dataValue`) on the ViewModel
4. Advance to Review step
5. On error: display Accept.js validation messages inline (card declined at tokenization is rare — most errors are format validation)

**The nonce is single-use and expires in ~15 minutes.** If the customer sits on Review for too long and then submits, the server will return `PaymentNonceInvalid` (422). The website should handle this by returning the customer to the Payment step with a message like "Your payment session expired. Please re-enter your card details."

### Modified Booking Submission

The `handleConfirm()` function in `BookingReview.svelte` currently calls `sdk.createBooking(body)`. The body gains two new fields:

```typescript
{
  // ... existing fields (product_id, guest_count, start_at, guest_name, etc.) ...
  payment: {
    data_descriptor: nonce.dataDescriptor,  // "COMMON.ACCEPT.INAPP.PAYMENT"
    data_value: nonce.dataValue             // opaque token from Accept.js
  },
  addons: vm.selectedAddons  // if addon selection exists — optional
}
```

When `payment_service` is disabled on the server, the `payment` field should be omitted (server won't require it). The website can detect this from the booking preview response or a dedicated settings endpoint — coordinate with the server agent on the mechanism.

### Response Handling

The booking endpoint returns three distinct outcomes when payment is enabled:

| HTTP Status | Meaning | Website Behavior |
|---|---|---|
| **201** | Payment approved, booking confirmed | Show confirmation page (existing flow) |
| **202** | Payment held for fraud review | Show "under review" message — booking exists but isn't confirmed yet. Customer gets email when resolved. |
| **422** with `PaymentDeclined` | Card declined | Show decline message, return to Payment step to retry with different card |
| **422** with `PaymentNonceInvalid` | Nonce expired/invalid | Return to Payment step, ask customer to re-enter card |
| **422** with `PaymentNonceRequired` | Payment enabled but no nonce sent | Bug — should not happen if frontend is correct |
| **502** with `PaymentError` | Gateway error | Show generic "payment could not be processed, try again" message |

The ViewModel needs a new state for the 202 case — something like `HELD_FOR_REVIEW` alongside `CONFIRMED`. The BookingConfirm component (or a new component) should render differently for held-for-review bookings.

### Loading States

Two loading moments need treatment:
1. **Payment step → Review:** Tokenization via Accept.js (client-side, fast but async). Show spinner on Continue button.
2. **Review → Confirmed:** The `handleConfirm()` call now charges a credit card. This takes 2-5 seconds. The existing `submitting` state spinner is correct but the copy should change from "Submitting..." to "Processing payment..." to set expectations.

The step 3→4 loading indicator (flagged in Remaining Work above) should also be addressed — `advanceToReview()` fetches the booking preview but has no spinner.

### Sandbox Testing

Authorize.Net sandbox test card numbers:
- `4111111111111111` — Visa, approves
- `5424000000000015` — Mastercard, approves
- `4222222222222` — Visa, declines (triggers declined response)

Use sandbox env vars during development. The server's `AUTHORIZENET_SANDBOX=true` points to the sandbox API.

## Decisions Made During Build

### Tier selection is URL-driven on `/book`
The `?tier=` query param owns the tier state on the booking page. Selecting a tier pushes a history entry via `goto('/book?tier=groups')`. Browser back/forward navigates between tier states. The ViewModel resets to package selection if the URL tier changes while past step 1. This replicates the old `/rental-prices/` funnel pattern where group-size → packages → reserve was a navigable flow.

### Product @id canonical lives on `/prices/[tier]`
Each product gets a canonical `@id` like `https://urbanwarzonepaintball.com/prices/individual#product-1`. The `/book` page references these same `@id`s in its JSON-LD. Google deduplicates by `@id` — the richer definition on the pricing page takes precedence.

### Non-tier redirects temporarily point to `/prices` parent
`/rental-prices/food-pricing`, `/rental-prices/gear-requirements`, `/rental-prices/monthly-vip-membership`, `/rental-prices/membership-terms-conditions`, and `/rental-prices/feed` all redirect to `/prices` until Phase 3 builds dedicated sub-pages.

### Package features are drafted, not confirmed
`tiers.ts` contains `PACKAGE_FEATURES` with drafted inclusions per package (Basic/Deluxe/Elite). These are flagged with a TODO for owner verification before launch.

## Red Team Findings — Resolution Status

| RT | Finding | Status | Resolution |
|---|---|---|---|
| RT-1 | /book must not duplicate /prices | **Mitigated** | /book has functional tier picker + package selector. /prices has persuasive comparison content, feature lists, FAQ. Different content, different moments. |
| RT-2 | /prices parent must not be thin | **Mitigated** | Overview has tier cards, "Every Package Includes" list, "Not Sure Which Tier?" guidance, CTA. |
| RT-3 | Nav placement | **Resolved** | Packages → Prices in Party Packages dropdown. Book Now stays as direct link. |
| RT-4 | Non-tier pages need content | **Deferred to Phase 3** | Redirects point to /prices parent until sub-pages built. |
| RT-5 | Scope creep | **Managed** | Phased delivery: Phase 1 (prices) + Phase 2 (book) complete. Phase 3 deferred. |
| RT-6 | Product @id duplication | **Resolved** | Canonical @id on /prices/[tier], referenced on /book. |
| RT-7 | No prerender on pricing pages | **Resolved** | Comment in every +page.server.ts explaining why. |
| RT-8 | Tier pages need substance | **Mitigated** | Each has comparison cards, feature lists, audience blurb, FAQ, CTA. Copy needs owner review. |
| RT-9 | Non-tier redirects bundled with launches | **Documented** | Phase 3 requirement: each sub-page ships with its redirect update. |

## Open Questions

1. **Home page `/prices` link (needs owner input).** With `/prices` as a first-class section, should the home page body include a "See Prices" link alongside "Book Now"? Nav will link to `/prices`, but body links carry more internal linking weight. This could strengthen `/prices`' SEO position or dilute the primary CTA. Conscious decision — not automatic, not default.

2. **Hours & Pricing page overlap.** The nav currently has `{ href: '/hours', label: 'Hours & Pricing' }` under "Plan Your Visit." With `/prices` as its own section, does `/hours` still say "& Pricing" or just "Hours"? Minor, decide during build.

## Reference Files

| File | Purpose |
|---|---|
| `docs/URL_CHOICE.md` | Full SEO analysis with Search Console + GA4 data |
| `docs/SVELTE_STYLE_GUIDE.md` | Code conventions |
| `docs/WEB_UX.md` | Component layering, MVVM, 8-stage workflow |
| `.claude/skills/seo/seo.json` | Route classifications, structured data types, crawl config |
| `.claude/skills/seo/schema-reference.md` | JSON-LD property requirements |
| `.claude/skills/frontend-website/SKILL.md` | Design direction, creative constraints |
| `server/migrations/20260321120000_seed_product_catalog.sql` | Product data (source of truth for prices) |
| `surface-website/src/lib/data/tiers.ts` | Tier definitions, product filtering, package features |
| `surface-website/src/lib/data/redirects.ts` | Current redirect map |
| `surface-website/src/lib/components/GlobalNav.svelte` | Navigation structure |
| `surface-website/src/routes/(public)/book/` | Booking page + wizard + tier funnel |
| `surface-website/src/routes/(public)/prices/` | Pricing pages + tier detail |
| `docs/DISPATCH_PAYMENTS.md` | Server payment integration plan (6 slices) |
| `surface-website/src/routes/(public)/book/_components/bookingConstants.ts` | Step definitions — will gain PAYMENT step |
| `surface-website/src/routes/(public)/book/_components/bookingFlow.svelte.ts` | ViewModel — will gain nonce + held-for-review state |
| `surface-website/src/routes/(public)/book/_components/BookingReview.svelte` | Confirm button — will send payment nonce |
