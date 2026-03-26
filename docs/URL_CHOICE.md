# URL Choice: Consolidated Booking Page Slug

**Decision date:** 2026-03-22
**Status:** Superseded by `docs/DISPATCH_BOOK_PAGE.md` — architecture evolved to `/prices` + `/book` (two route trees) during session. This document remains the canonical source for the underlying Search Console and GA4 data. For the final architecture, redirect map, and implementation plan, read the dispatch.
**Data window:** Oct 2025 – Mar 2026 (Search Console: 16 months; GA4: 5 months)

## Decision

Use `/book` as the booking page slug and `/prices/[tier]` as the pricing pages. Redirect all legacy URLs via 301. See `docs/DISPATCH_BOOK_PAGE.md` for the full route architecture and redirect map.

## Context

The current site has two pages feeding into the booking funnel:

- `/paintball-reservations/` — reservation entry point
- `/rental-prices/` — pricing page

The new site consolidates these into a single page. The question: should that page be `/book` (clean, intent-forward) or `/paintball-reservations/` (preserves existing keyword-bearing slug)?

## Recommendation: `/book`

**Overall confidence: High.** The keyword-in-URL argument for preserving `/paintball-reservations/` is empirically weak. The data shows the URL slug is not what drives rankings for either page.

### Why the slug doesn't matter as much as expected

**Confidence: High.** Based on 16 months of Search Console data — large enough sample to be definitive.

**Zero of the top 10 queries driving clicks to `/paintball-reservations/` contain "reservations":**

| Query | Clicks | Position |
|---|---|---|
| paintball houston | 115 | 3.3 |
| paintball near me | 55 | 6.1 |
| paintball | 38 | 5.0 |
| houston paintball | 17 | 3.0 |
| paint ball in houston | 12 | 3.2 |
| paintball houston tx | 9 | 4.2 |
| paintball in houston | 8 | 4.5 |
| paintball houston texas | 8 | 4.6 |
| paintballing houston | 5 | 3.3 |
| paintball in houston texas | 5 | 4.6 |

Google ranks this page for "paintball houston" because of domain signals, content, and local relevance — not because "reservations" is in the URL.

Same pattern on `/rental-prices/`: top non-branded queries are "how much is paintballing," "paintball prices," "how much does paintball cost." The word "rental" drives none of them.

### Why the volume at risk is small

**Confidence: Medium.** GA4 data covers 5 months and lacks conversion event tracking, so we're inferring booking intent from engagement time and funnel page patterns rather than measuring completions directly. Engagement time comparisons between page types are unreliable (see caveat below).

Organic search is not the primary booking channel. The homepage dominates:

| Landing page | Total sessions | Organic sessions | Organic engagement |
|---|---|---|---|
| `/` | 8,826 | 4,922 (56%) | 90s |
| `/rental-prices/*` (full funnel) | 1,945 | 1,073 (55%) | varies |
| `/rental-prices` (parent only) | 724 | 450 (62%) | 43s |
| `/paintball-reservations/*` (full funnel) | 527 | 321 (61%) | varies |
| `/paintball-reservations` (parent only) | 347 | 193 (56%) | 112s |
| `/paintball-birthday-party` | 183 | 87 (48%) | 98s |

The rental-prices funnel is **3.3x larger** than the reservations funnel when measured across all sub-pages (1,073 vs 321 organic sessions). Google ranks the sub-pages independently — `/rental-prices/individual-rental-prices` alone has 433 organic sessions, nearly as many as the parent page.

The booking funnel is driven by internal navigation from the homepage, not by organic landing on either page. Evidence: `/Thank-You` had 65 organic-attributed sessions with **0 new users** — every completed booking came from returning visitors who started their session elsewhere.

**Caveat on engagement time comparisons:** The 112s engagement on `/paintball-reservations/` vs 43s on `/rental-prices/` does NOT indicate higher booking intent. These are different page types: `/paintball-reservations/` is a wall of text that takes time to read; `/rental-prices/` is a selection page where users pick a group size and move to a sub-page. The GA4 metric is session-level (includes all pages visited after landing), so 43s already accounts for any sub-page navigation — but short session time on a selection page is expected behavior, not a quality signal. We cannot reliably compare booking intent between these pages using engagement time alone.

### Why `/book` is the better long-term choice

- **Intent clarity.** `/book` is a verb — Google, AI assistants, and humans all recognize transactional intent immediately.
- **SERP display.** `urbanwarzonepaintball.com/book` is cleaner than `/paintball-reservations/`. The domain already contains "paintball."
- **Site language match.** All internal CTAs say "Book Now," "Book a Party," "Book Your Event." The URL matches anchor text site-wide.
- **Future-proof.** Doesn't need to change as offerings evolve.

## Conditions

1. **301 all legacy URLs on day one — including sub-pages.** Both current slugs, all `.shtml` variants, and critically the `/rental-prices/*` sub-pages which collectively drive 1,073 organic sessions (more than the parent pages combined). Known gaps: `/online-paintball-reservations` without trailing slash returns a connection error (with trailing slash, 301 works). Ensure both resolve. Sub-pages like `/rental-prices/individual-rental-prices` (433 organic sessions) and `/rental-prices/medium-group-discount` (131 organic sessions) need explicit redirect coverage — Google ranks them independently.

2. **The `/book` page must contain substantial crawlable pricing content.** Package names, prices, what's included, group size tiers. The rental-prices funnel (1,073 organic sessions across all sub-pages) is 3.3x larger than the reservations funnel. This is the higher-value organic asset being consolidated. If pricing content disappears behind a JS widget that Google can't parse, you lose not just the "how much does paintball cost" cluster but the entire pricing sub-page organic reach.

3. **Title tag bridges both intent clusters.** Something like: "Book Paintball in Houston | Prices from $24.95 | UWZ Paintball" — covers discovery ("paintball houston") and price intent ("prices from $24.95") in one tag.

4. **On-page signals must compensate for the slug change.** H1, meta description, and body content should include "paintball reservations" language naturally. Google needs textual signals to connect `/book` to the same intent as `/paintball-reservations/`.

## Planned redirects

```
# Current pages
/paintball-reservations/                → /book  (301)
/paintball-reservations/gateway         → /book  (301)
/rental-prices/                         → /book  (301)
/rental-prices/individual-rental-prices → /book  (301)  ← 433 organic sessions
/rental-prices/medium-group-discount    → /book  (301)  ← 131 organic sessions
/rental-prices/large-group-discount     → /book  (301)
/rental-prices/extra-paintballs         → /book  (301)
/rental-prices/food-pricing             → /book  (301)
/rental-prices/monthly-vip-membership   → /book  (301)
/rental-prices/gear-requirements        → /book  (301)
/rental-prices/get-faster-paintball-marker → /book  (301)
/rental-prices/introduction-to-paintball  → /book  (301)

# Legacy URLs
/reservations.shtml            → /book  (301)
/prices.shtml                  → /book  (301)
/online-paintball-reservations → /book  (301)
15+ additional legacy URLs     → /book  (301)
```

## Supporting data

### Two pages serve distinct search intent clusters

**Confidence: High.** Only 11 queries overlap with clicks > 0 out of 75+ and 54+ unique clicked queries respectively. The cluster separation is clear.

| | `/rental-prices/` | `/paintball-reservations/` |
|---|---|---|
| **Total clicks (16mo)** | 472 | 337 |
| **Total impressions** | 126,053 | 59,485 |
| **Dominant cluster** | Branded (49%) + Price intent (44%) | Location (58%) + Near me (20%) + Generic (20%) |
| **Branded % of clicks** | 48.5% | 0.9% |
| **Non-branded clicks** | 243 | 334 |

`/rental-prices/` is effectively half a branded landing page. Strip branded queries and it generates ~15 non-branded organic clicks/month.

`/paintball-reservations/` does the actual organic acquisition — 99% non-branded — but at only ~21 clicks/month from Search Console.

### Keyword cluster breakdown

**`/rental-prices/` clicks by cluster:**
| Cluster | Clicks | Impressions |
|---|---|---|
| Branded | 229 | 16,274 |
| Price/cost | 208 | 11,822 |
| Generic paintball | 20 | 38,004 |
| Location (Houston) | 13 | 28,127 |
| Near me | 2 | 26,760 |

**`/paintball-reservations/` clicks by cluster:**
| Cluster | Clicks | Impressions |
|---|---|---|
| Location (Houston) | 197 | 26,349 |
| Near me | 67 | 9,827 |
| Generic paintball | 66 | 16,050 |
| Branded | 3 | 5,372 |
| Booking/reservation | 3 | 48 |

Only 11 queries overlap between the two pages (with clicks > 0). They serve almost entirely different search intents, and the consolidated page must serve both.

### Keyword overlap detail

| Query | Rental-prices clicks | Reservations clicks |
|---|---|---|
| paintball houston | 6 | 115 |
| paintball | 4 | 38 |
| paint ball in houston | 2 | 12 |
| paintball houston tx | 1 | 9 |
| paintball in houston | 1 | 8 |
| paint ball houston | 1 | 4 |
| urban war zone paintball | 101 | 3 |
| paintballing | 1 | 3 |
| paint ball | 1 | 3 |
| best paintball in houston | 1 | 2 |
| paintball group packages | 2 | 1 |

### Engagement quality (GA4, organic only)

| Page | Organic sessions | Avg engagement | New users |
|---|---|---|---|
| `/` | 4,922 | 90s | 3,585 |
| `/rental-prices` (parent) | 450 | 43s | 151 |
| `/rental-prices/individual-rental-prices` | 433 | 11s | 41 |
| `/rental-prices/medium-group-discount` | 131 | 31s | 10 |
| `/paintball-reservations` | 193 | 112s | 151 |
| `/paintball-reservations/gateway` | 128 | 39s | 1 |
| `/paintball-birthday-party` | 87 | 98s | 48 |

**Engagement time is not a reliable booking-intent signal here.** These are structurally different pages: `/paintball-reservations/` is text-heavy (long read time expected), `/rental-prices/` is a selection page (short time expected — user picks group size and moves on), and the sub-pages are detail views. The GA4 metric is session-level (total time across all pages visited), so `/rental-prices/` at 43s already includes sub-page navigation time. Short session time on a selection page is normal behavior, not an indication of low quality or bouncing.

The rental-prices funnel collectively (1,073 organic sessions) is 3.3x larger than the reservations funnel (321 organic sessions). Google ranks `/rental-prices/individual-rental-prices` independently — it has nearly as many organic sessions as the parent page.

### Impression trend (both pages declining)

**Confidence: Medium.** Both pages saw a ~70% impression drop starting Jan 2026. Clicks held steady, which is consistent with Google pruning low-quality impressions (queries at position 30+ that never converted to clicks). No site changes occurred during this period. The interpretation that this is data cleanup rather than ranking loss fits the pattern, but we cannot rule out an algorithm change that coincidentally maintained click volume while reducing visibility for future queries.

### AI referral traffic

**Confidence: Low (on trend extrapolation).** 75 sessions over 5 months, mostly ChatGPT to homepage and blog content. Small but real. The claim that `/book` is more likely to be cited correctly by AI assistants is directionally reasonable but speculative — we have no data on how AI assistants handle URL slugs in recommendations. Not decision-driving.

### Technical SEO baseline (confirmed 2026-03-22)

- Canonical tags: present on all key pages
- Meta descriptions: present on all key pages
- Legacy `.shtml` redirects: working (301)
- Sitemap: both pages included at priority 0.8
- SSR: all pages render server-side (SvelteKit)
- No noindex/nofollow tags on key pages

## Risk assessment

| Risk | Severity | Likelihood | Mitigation |
|---|---|---|---|
| Ranking dip during 301 transition | Low | High (nearly certain, but shallow) | On-page signals, content parity, proper redirects |
| Loss of pricing sub-page organic reach | **High** | Medium (if sub-pages aren't redirected or content is thin) | Explicit 301s for each sub-page; crawlable pricing content on `/book` |
| Loss of "how much" price cluster | Medium | Medium (if crawlable content is thin) | Ensure pricing content is crawlable text, not JS-only |
| Slow crawl/reindex for local business | Low | Medium | Submit updated sitemap, request indexing in Search Console |
| Google fails to connect `/book` to old intent | Low | Low (if on-page signals are strong) | Title, H1, meta desc, body text all reference reservations and pricing |

## What we chose not to optimize for

- **Preserving `/paintball-reservations/` for keyword value.** The keywords in the URL aren't the keywords driving traffic.
- ~~**Keeping two separate pages.** They serve distinct intents, but the volume doesn't justify maintaining two pages when a single well-structured page can serve both.~~ **Reversed.** Further analysis of sub-page organic reach (1,073 sessions across `/rental-prices/*`) led to a two-route-tree architecture: `/prices/[tier]` + `/book`. See `docs/DISPATCH_BOOK_PAGE.md`.
- **Waiting for the impression trend to recover.** The impression drop is Google pruning irrelevant SERP appearances. Clicks are stable. There's nothing to wait for.
