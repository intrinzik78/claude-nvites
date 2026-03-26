# SEO Migration Plan: surface-website

> Generated: 2026-03-07
> Supersedes: original technical-only audit (same date)
> Config: `.claude/skills/seo/seo.json`

---

## Reasoning

This plan was produced after auditing the new codebase AND the live production site at urbanwarzonepaintball.com. The original audit examined only the new code and found valid technical gaps (font-display, missing structured data, noindex). But it missed the critical context: **the live site is a SvelteKit build serving the old WordPress-era content at 56 indexed URLs, all of which will 404 when the new site deploys.**

The old site has years of SEO investment — keyword-rich titles, internal linking, blog content, backlinks, and a 54-entry sitemap that Google crawls. The new site currently has 7 public routes (homepage, packages, book, shop, gallery, queue, queue/confirm) with no content pages (about, contact, hours, FAQ, birthday parties, team building, etc.).

**The goal is not to "fix SEO on the new site." It's to build the new site so that it preserves and improves on the old site's rankings.** Every content page, title, heading, and redirect must be planned with the old site as the baseline.

Key principles:
1. **No URL goes dark without a 301.** Every old URL either becomes a new page or redirects to one.
2. **Match keyword coverage before adding new signals.** The old site targets "paintball birthday party Houston," "paintball prices Houston," "team building paintball Houston" etc. as distinct pages. Collapsing them all into `/packages` loses those keyword-specific rankings.
3. **Carry forward all existing redirects.** The old site already has 64 redirect entries from even older URLs (.shtml era, WordPress paths). The new site must carry the full chain.
4. **Technical SEO is foundation, not the goal.** Font performance, structured data, and meta tags matter — but only on pages that exist with real content.

---

## Decisions

All open questions have been resolved:

1. **Title suffix:** `| UWZ Paintball` — preserve current ranking pattern. Do not change.
2. **Blog:** Drop entirely. Redirect category pages to closest content page. Accept long-tail traffic loss.
3. **VIP memberships:** Not active now, coming back. Redirect to `/packages` temporarily. Build `/membership` when VIP relaunches. Slug reserved.
4. **Gift certificates:** Deferred — unclear if new site will sell them. Redirect `/select-gift-certificate-amount/` to `/shop` for now.
5. **Game types:** Keep as dedicated `/game-types` page — separate from `/what-to-expect`.
6. **Hiring:** Not active. All job page redirects go to `/`. If hiring resumes, build `/careers`.

---

## Live Production Inventory

### What currently ranks (56 URLs in sitemap)

The live site at urbanwarzonepaintball.com serves these pages. They are SvelteKit-rendered content pages using old WordPress-era URL slugs.

#### Tier 1 — Core revenue pages (priority 0.8-1.0)

| Live URL | Live title | New URL | Status |
|---|---|---|---|
| `/` | Paintball in Houston, Tx \| Paintballing for Kids & Adults \| UWZ Paintball | `/` | Exists (redesigned) |
| `/paintball-reservations/` | Paintball Reservations in Houston \| UWZ Paintball | `/book` | Exists — needs redirect |
| `/rental-prices/` | Paintball Prices in Houston \| UWZ Paintball | `/packages` | Exists — needs redirect |
| `/paintball-birthday-party/` | Paintball Birthday Party \| UWZ Paintball | `/birthday` | **Build dedicated page** |
| `/corporate-team-building-games/` | Houston Team Building with Paintball Games \| UWZ Paintball | `/team-building` | **Build dedicated page** |
| `/pictures/` | (gallery) | `/gallery` | Exists — needs redirect |
| `/unlimited-private-play/` | (private play info) | `/packages` | Redirect |
| `/paintball-game-types/` | (game descriptions) | `/game-types` | **Build dedicated page** |

**Why `/birthday` and `/team-building` need dedicated pages:** The old site ranks for "paintball birthday party Houston" and "team building paintball Houston" as distinct keyword targets with dedicated content. Collapsing them into `/packages` loses those rankings — Google sees `/packages` as a pricing page, not a birthday party page.

#### Tier 2 — High-value informational pages (priority 0.6)

| Live URL | New URL | Status |
|---|---|---|
| `/about-us/` | `/about` | **Build** |
| `/contact/` | `/contact` | **Build** |
| `/hours-operation/` | `/hours` | **Build** (or embed in contact) |
| `/frequently-asked-questions/` | `/faq` | **Build** |
| `/waiver/` | `/waiver` | **Build** (public page, not just portal) |
| `/map-to-the-field/` | `/directions` | **Build** (or embed in contact) |
| `/what-to-expect-playing-paintball/` | `/what-to-expect` | **Build** |
| `/low-impact-paintball-for-kids/` | `/kids` | **Build** |
| `/paintball-birthday-invitations/` | `/birthday` | Redirect |

#### Tier 3 — Pricing sub-pages (priority 0.6)

These are sub-pages under `/rental-prices/` on the old site. All redirect to `/packages` or `/shop`.

| Live URL | New URL | Notes |
|---|---|---|
| `/rental-prices/individual-rental-prices/` | `/packages` | Redirect |
| `/rental-prices/medium-group-discount/` | `/packages` | Redirect |
| `/rental-prices/large-group-discount/` | `/packages` | Redirect |
| `/rental-prices/extra-paintballs/` | `/shop` | Redirect |
| `/rental-prices/food-pricing/` | `/packages` | Redirect |
| `/rental-prices/gear-requirements/` | `/packages` | Redirect |
| `/rental-prices/get-faster-paintball-marker/` | `/shop` | Redirect |
| `/rental-prices/introduction-to-paintball/` | `/what-to-expect` | Redirect |
| `/rental-prices/membership-terms-conditions/` | `/packages` | Temporary — redirect to `/membership` when VIP relaunches |
| `/rental-prices/monthly-vip-membership/` | `/packages` | Temporary — redirect to `/membership` when VIP relaunches |

#### Tier 4 — Promotional / transactional (priority 0.6)

| Live URL | New URL | Notes |
|---|---|---|
| `/select-gift-certificate-amount/` | `/shop` | Redirect — gift certificate decision deferred |
| `/get-a-free-paintball-grenade/` | `/` | Redirect — promo is dead |
| `/paintball-reservations/gateway/` | `/book` | Redirect |
| `/co2-refill-price/` | `/shop` | Redirect |
| `/compressed-air-refill-price/` | `/shop` | Redirect |

#### Tier 5 — Blog (dropped — redirect all)

Blog is not being carried forward. Redirect all blog URLs to the closest content page:

| Live URL | New URL |
|---|---|
| `/blog/` | `/` |
| `/blog/party/` | `/birthday` |
| `/blog/party/unforgettable-bachelor-party-ideas-houston/` | `/birthday` |
| `/blog/party/adult-paintball/` | `/birthday` |
| `/blog/party/do-paintballs-stain-clothes/` | `/faq` |
| `/blog/party/bruises-from-paintball/` | `/faq` |
| `/blog/news/` | `/` |
| `/blog/news/pump-league-may-2023/` | `/` |
| `/blog/news/pump-league-june-2023/` | `/` |
| `/blog/news/2023-july-4-introduction/` | `/` |
| `/blog/news/2023-july-4-1917/` | `/` |
| `/blog/news/2024-spring-break-vibes/` | `/` |
| `/blog/news/2024-beryl-status/` | `/` |
| `/blog/news/2025-new-years-day/` | `/` |
| `/blog/business/` | `/team-building` |
| `/blog/business/team-bonding-cost/` | `/team-building` |
| `/blog/business/team-building-for-football/` | `/team-building` |
| `/blog/gear/` | `/shop` |
| `/blog/gear/paintball-repair-houston/` | `/shop` |
| `/blog/gear/compressed-air-tank-for-paintball/` | `/shop` |
| `/blog/gear/paintball-co2-tank/` | `/shop` |

#### Tier 6 — Jobs (redirect to /)

Not hiring. All job page redirects go to `/`. Carry forward from old site:

- `/hiring-for-paintball-jobs-work/*` → `/`
- `/gellyball-party-for-kids` → `/`

#### Tier 7 — Legacy redirect chain (from old-site/src/lib/data/redirects.js)

These 64 redirects map ancient URLs (.shtml, WordPress paths, typos) to the old site's current URLs. The new site must carry the **full chain** — e.g., `/prices.shtml` → `/packages` (not → `/rental-prices/` → 404).

Flattened legacy redirects for the new site (deduped, trailing-slash variants collapsed):

| Source | Destination |
|---|---|
| `/prices.shtml` | `/packages` |
| `/reservations.shtml` | `/book` |
| `/birthday.shtml` | `/birthday` |
| `/corporate.shtml` | `/team-building` |
| `/hours.shtml` | `/hours` |
| `/contact.shtml` | `/contact` |
| `/faq.shtml` | `/faq` |
| `/map.shtml` | `/directions` |
| `/about` | `/about` |
| `/index.shtml` | `/` |
| `/pictures11.shtml` | `/gallery` |
| `/pictures02.shtml` | `/gallery` |
| `/pictures09.shtml` | `/gallery` |
| `/online-paintball-reservations/` | `/book` |
| `/introduction-to-paintball` | `/what-to-expect` |
| `/request-corporate-event-quote` | `/team-building` |
| `/uncategorized/host-great-paintball-party` | `/birthday` |
| `/uncategorized/protect-president` | `/` |
| `/uncategorized/tournament-paintball/` | `/` |
| `/sniper-package-unlimited-paintballs` | `/` |
| `/nonprofit.shtml` | `/` |
| `/specials.shtml` | `/` |
| `/wp-login.php` | `/` |
| `/wp-content/plugins/about.php` | `/about` |
| `/wp-content/uploads/2013/09/waiver.pdf` | `/waiver.pdf` |
| `/sitemap-generator/xml-sitemap` | `/sitemap.xml` |
| `/error/404/` | `/` |
| `/rental-prices/feed/` | `/packages` |
| `/waiver/feed/` | `/waiver` |
| `/paintball-birthday-invitations/feed.php/` | `/birthday` |
| `/blog/business/team-building-football` | `/team-building` |
| `/blog/news/pump-league-may-2023//` | `/` |
| `/hiring-for-paintball-jobs-work/expierienced/referee/` | `/` |
| `/hiring-for-paintball-jobs-work/experienced-referee` | `/` |
| `/hiring-for-paintball-jobs-work/beginner-referee` | `/` |
| `/hiring-for-paintball-jobs-work/cashier` | `/` |
| `/gellyball-party-for-kids` | `/` |

Note: each source also needs a trailing-slash variant (or use a prefix match). The old site handled both `/path` and `/path/` separately.

---

## Homepage JSON-LD Parity

The old site's homepage structured data uses `LocalBusiness` with rich signals that drive search features (star ratings, hours, map pins). The new site uses `SportsActivityLocation`. Verify the new site's JSON-LD includes ALL of these:

| Signal | Old site | New site | Status |
|---|---|---|---|
| `@type` | `LocalBusiness` | `SportsActivityLocation` | OK — subtype of LocalBusiness |
| `aggregateRating` | 4.7 / 864 reviews | Present | **Verify count is current** |
| `openingHours` | ISO format array | Present | Verify matches |
| `telephone` | (281) 892-1148 | Present | Verify |
| `address` | Full postal address | Present | Verify |
| `geo` | lat/long | Present | Verify |
| `sameAs` | 5 social profiles | Present | Verify |
| `image` | WordPress-era photo URL | ? | **Needs new image URL** |
| `logo` | `/images/logo/uwz-logo-white.png` | ? | **Needs new logo URL** |
| `priceRange` | `$$` | ? | **Verify present** |

---

## Title Suffix — DECIDED

**`| UWZ Paintball`** — preserve the established ranking pattern. This is what Google already associates with the domain.

Update required:
- `SeoHead.svelte` → change `TITLE_SUFFIX` to `` | UWZ Paintball``
- `seo.json` → change `defaults.titleTemplate` to `"%s | UWZ Paintball"`

---

## Technical SEO Findings

These are valid regardless of content status. Apply to existing pages.

### Blockers

| # | Location | Issue | Fix |
|---|---|---|---|
| B1 | `app.css` | No `font-display` on any `@font-face` — FOIT causes CLS | Add `font-display: swap` to all 3 blocks |
| B2 | `app.html` | No `<link rel="preload">` for BlackOpsOne — hero H1 font delays LCP | Add preload for woff2 |
| B3 | `SeoHead.svelte` | `DEFAULT_OG_IMAGE = ''` — og:image never emitted | Needs design asset (deferred) |
| B4 | `queue/+page.svelte` | Raw `<svelte:head>` — missing description, canonical, OG, breadcrumbs. Title typo: "Urban Warzone" | Replace with SeoHead |
| B5 | `queue/confirm/+page.svelte` | No noindex on transactional OTP step. Uses deprecated `$app/stores` | Add SeoHead with noindex, fix import |

### Warnings

| # | Location | Issue | Fix |
|---|---|---|---|
| W1 | `gallery/+page.svelte` | Missing `ImageGallery` structured data | Add to JSON-LD @graph |
| W2 | `gallery/[id]/+page.svelte` | Missing `ImageGallery` with photo objects | Add to JSON-LD @graph |
| W3 | `packages/+page.svelte` | Missing `Product` structured data | Add to JSON-LD @graph |
| W4 | `shop/+page.svelte` | Missing `Product` structured data | Add to JSON-LD @graph |

### Nits (deferred)

| # | Location | Issue |
|---|---|---|
| N1 | `login/+page.svelte` | Title "Login \| UWZ" — noindexed page, browser tab only |
| N2 | `gallery/[id]/[photoId]` | Breadcrumb uses raw filename instead of human label |
| N3 | `HomProof.svelte` | `<section>` without heading (has no ARIA either) |
| N4 | `HomTestimonial.svelte` | `<section>` without heading (has `aria-label` — marginal value to add heading) |

### Good Patterns (preserve)

- `SeoHead` centralizes all meta — consistent canonical, OG, Twitter
- Canonical uses hardcoded `BASE_URL` (not `$page.url.origin`)
- `(auth)` and `portal/` layouts set noindex at layout level
- `app.html` has charset, viewport, theme-color, favicon
- Home page JSON-LD: `SportsActivityLocation` with address, geo, hours, aggregateRating, sameAs
- BreadcrumbList correctly omits `item` on final element
- Gallery photo page sets `og:image` to actual photo URL
- Dynamic gallery pages derive title/description from server data (SSR-visible)

### Red Team Notes (from original audit, still valid)

**RT-1: Title length.** With `| UWZ Paintball` (15 chars including pipe+spaces), page titles have ~45 chars for the page-specific portion before hitting the 60-char Google truncation point. Measure each page title.

**RT-2: $app/stores → $app/state is a two-part fix.** In `queue/confirm/+page.svelte`, changing the import requires also replacing `$page` → `page` (no auto-subscription prefix in Svelte 5 state).

**RT-3: Sitemap — keep the +server.ts.** The existing dynamic route handler at `src/routes/sitemap.xml/+server.ts` generates fresh `lastmod` on each request and can be extended to query the API for gallery albums. A static build script is a regression. Just add missing routes to the existing handler.

---

## Implementation Slices

Ordered by value and dependency. Each slice is self-contained and committable.

### Slice 1 — Redirect infrastructure

**Why first:** This is the safety net. Even if no content pages exist yet, redirects prevent 404s for any old-site URLs that leak into the new site during development or accidental early deployment.

- Port all redirects into new site's `hooks.server.ts`
- Sources: Tier 1-6 old-URL → new-URL mappings (above) + Tier 7 legacy chain
- Flatten redirect chains (e.g., `/prices.shtml` goes directly to `/packages`, not through `/rental-prices/`)
- For pages that don't exist yet (`/birthday`, `/team-building`, `/about`, etc.), redirect to `/` as temporary fallback
- Handle both `/path` and `/path/` variants
- Blog catch-all: `/blog/party/*` → `/birthday`, `/blog/business/*` → `/team-building`, `/blog/gear/*` → `/shop`, `/blog/news/*` → `/`
- Test: each legacy URL returns 301 with correct Location header

### Slice 2 — Title suffix + technical SEO foundation

- `SeoHead.svelte`: change TITLE_SUFFIX to `` | UWZ Paintball``
- `app.css`: add `font-display: swap` to all 3 `@font-face` blocks
- `app.html`: add `<link rel="preload">` for BlackOpsOne woff2
- `queue/+page.svelte`: replace raw `<svelte:head>` with SeoHead (fixes typo, adds meta)
- `queue/confirm/+page.svelte`: add SeoHead with noindex, fix `$app/stores` → `$app/state`
- Test: view-source checks for meta tags, font preload in Network tab

### Slice 3 — Structured data enrichment

- `gallery/+page.svelte`: convert jsonLd to @graph with ImageGallery
- `gallery/[id]/+page.svelte`: convert jsonLd to @graph with ImageGallery + photo ImageObjects
- `packages/+page.svelte`: add Product entries to @graph (no `sku` field)
- `shop/+page.svelte`: add Product entries to @graph
- Verify homepage JSON-LD parity with old site (see parity table above)
- Test: Rich Results Test on each page

### Slice 4 — Sitemap update

- Add `/queue` to existing `sitemap.xml/+server.ts`
- Add new content page URLs as they're built (ongoing)
- Do NOT delete the +server.ts or replace with static file
- Test: `curl /sitemap.xml` returns valid XML with all public routes

### Slice 5 — Content: Birthday + Team Building pages

**Why these first:** Highest-value keyword targets that currently collapse into `/packages`. The old site has dedicated pages with rich content for "paintball birthday party Houston" and "team building paintball Houston."

- Build `/birthday` — SeoHead, structured data, content matching old site's keyword targets
- Build `/team-building` — same pattern
- Update redirects: change temporary `/` fallbacks to real page URLs
- Update sitemap with new routes
- Content source: old site pages at `/home/zik/programming/uwz/old-site/src/routes/(web)/`

### Slice 6 — Content: Informational cluster

- Build `/about` (old: `/about-us/`)
- Build `/contact` (old: `/contact/`)
- Build `/hours` (old: `/hours-operation/`)
- Build `/faq` (old: `/frequently-asked-questions/`)
- Build `/waiver` (old: `/waiver/` — public download page, distinct from portal waivers)
- Update redirects and sitemap
- Content source: old site pages

### Slice 7 — Content: Experience pages

- Build `/what-to-expect` (old: `/what-to-expect-playing-paintball/`)
- Build `/kids` (old: `/low-impact-paintball-for-kids/`)
- Build `/directions` (old: `/map-to-the-field/`)
- Build `/game-types` (old: `/paintball-game-types/`)
- Update redirects and sitemap

### Slice 8 — seo.json update + final verification

- Add all new routes to seo.json
- Update `defaults.titleTemplate` to `"%s | UWZ Paintball"`
- Update `audit.lastRun`
- Run full verification checklist (below)

---

## Verification Checklist

| Check | Method |
|---|---|
| Title suffix | All indexed pages end with `\| UWZ Paintball` |
| Font preload | DevTools Network → BlackOpsOne shows `preload` initiator |
| No FOIT on headings | Hard reload — headings render without flash |
| All legacy URLs redirect | Script: curl each old URL, verify 301 + Location header |
| No redirect chains | Each old URL resolves in one hop (not old → intermediate → new) |
| Queue page meta | View source `/queue` → description, canonical, og:title present |
| Queue confirm noindex | View source → `<meta name="robots" content="noindex, nofollow">` |
| Product schema | Rich Results Test on `/packages` and `/shop` |
| ImageGallery schema | JSON-LD in page source on `/gallery` and `/gallery/[id]` |
| Homepage JSON-LD parity | Compare old and new site structured data field by field |
| Title lengths | All indexed page titles ≤ 60 chars |
| Sitemap valid | `curl /sitemap.xml` → valid XML with all public routes |
| Sitemap in robots.txt | `curl /robots.txt` → references `/sitemap.xml` |
| Content pages indexed | Each new content page has SeoHead, no noindex, in sitemap |

---

## Deferred Items

| Item | Reason | Notes |
|---|---|---|
| OG image (1200x630) | Requires design asset | `SeoHead.svelte DEFAULT_OG_IMAGE` ready — fill URL when asset exists |
| Gallery album IDs in sitemap | Requires API query at request time | Extend `+server.ts` to fetch from API |
| Photo breadcrumb label | Uses filename, needs description field | Low priority — N2 |
| `/book`, `/gallery` title length | Short but not wrong | Include primary keyword on content pass |
| Gift certificates | Decision deferred | Redirect `/select-gift-certificate-amount/` → `/shop` for now |
| VIP membership page | Feature not active yet | Redirect to `/packages` now. Build `/membership` when VIP relaunches. Slug reserved. |
| Careers page | Not hiring | All job URLs redirect to `/`. Build `/careers` when hiring resumes. |
