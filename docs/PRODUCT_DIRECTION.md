# Product Direction

**Date:** 2026-04-02
**Status:** Working draft — captures a strategic pivot from QR analytics SaaS to marketing accountability service.

---

## The Problem

Small and medium local businesses (HVAC, roofing, plumbing, landscaping) spend $1,000–3,000/month on offline advertising — door hangers, direct mail, truck wraps, yard signs, Val-Pak coupons. They have no way to measure which channels bring paying customers. Decisions about where to spend are based on gut feel.

QR code platforms offer scan counts (device, location, time). This is the equivalent of pageview tracking — it measures **interest**, not **intent**. Knowing 500 people scanned a code says nothing about whether those people called, booked, or bought. The question every business owner actually asks — "is my advertising working?" — goes unanswered.

The industry stops at scan analytics because solving the next step (conversion tracking) requires integration into the customer's systems — their booking software, CRM, or POS. That integration is operationally complex, raises onboarding friction, and kills self-serve economics. Well-funded competitors (Flowcode, Beaconstac, QR Tiger) have chosen not to solve it.

## The Insight

**Scans measure interest. Conversions measure intent. The gap between them is the product.**

A scan tells you someone is curious. A tap-to-call, a form submission, or an SMS tap tells you someone is ready to act. That conversion event — the moment a person moves from browsing to taking action — is what local businesses will pay for.

The key architectural decision: **own the landing page.** By hosting a branded offer page between the QR scan and the customer's website, we control the cookie, the session, and the conversion event. No DNS setup, no code integration, no CRM webhooks required. The entire funnel lives on our infrastructure.

## The Service

**Marketing accountability for local businesses with offline advertising.**

The pitch: "You're spending money on mailers. We tell you which ones bring customers."

### How It Works

1. Business has an offer or promotion (e.g., "Spring AC Tune-Up — $49")
2. We create a branded landing page with their logo, colors, and offer copy
3. We generate QR codes — one per advertising channel (door hangers, truck wrap, yard signs, etc.)
4. Business prints the codes on their existing collateral (we don't need to be the printer)
5. Scans route through our gateway to the landing page
6. Landing page presents the offer with CTAs: tap-to-call, email, form submit, SMS
7. Each CTA tap is a tracked **engagement event** (not "conversion" — we don't own the conversion, we own the engagement)
8. Monthly report breaks down the funnel per channel: scans → unique visitors → engagements → engagement rate

### What the Customer Sees

A monthly report:

| Channel | Scans | Unique Visitors | Engagements | Engagement Rate | Signal |
|---------|-------|-----------------|-------------|-----------------|--------|
| Door hangers (Zone A) | 312 | 74 | 27 | 36.5% | Strong |
| Truck wrap | 89 | 41 | 20 | 48.8% | Strong |
| Yard signs | 204 | 12 | 3 | 25.0% | Weak (low volume) |
| Val-Pak coupon | 847 | 38 | 2 | 5.3% | Strong |

**Engagement rate** (engagements / unique visitors) is the primary decision metric. It normalizes across channels — a channel with fewer but higher-quality visitors outranks one with raw volume. The truck wrap has the best engagement rate despite fewer total scans.

**Signal confidence** is based on volume thresholds. Channels with insufficient engagement volume are flagged as weak signal to prevent over-optimization on noise. 23 engagements vs 20 engagements is a real difference; 3 vs 2 is not.

**Unique visitors vs total scans.** 50 scans from 50 people is different from 50 scans from 3 people revisiting. Reports show both but unique visitors feed the engagement rate calculation. First-time engagements are tracked separately from repeat interactions.

The report presents data and highlights; it does not make explicit recommendations ("stop spending on X"). The data is directional, not absolute — telling a business owner to cut a channel based on QR-tracked engagement alone crosses into advisory territory the data can't support. The business owner applies their own judgment and close rates.

### What the System Actually Measures

**This measures offer performance within a channel, not pure channel performance.** The result is channel × offer × placement × timing. If "Free Diagnostic" runs on door hangers and "$10 Off" runs on the truck wrap, and door hangers win, the customer doesn't know if the channel won or the offer won.

To isolate variables: same offer across different channels tests the channel. Same channel with different offers (A/B at $198) tests the offer. Reports should note when offer variation makes cross-channel comparison unreliable.

### What We Don't Track (Yet)

We don't track whether the call resulted in a booking or the form led to a sale. That's the server-to-server integration problem — it requires access to their booking/POS system. But the CTA engagement is the step right before, and for most local businesses it's enough. They know their own close rate. If 23 people called from door hangers and they close 1 in 3, that's ~8 jobs. They can do that math on a napkin.

Full-funnel conversion tracking (CTA → booking → revenue) is a future capability for customers who grow into it, not a launch requirement.

## Pricing

**$99/month per campaign (landing page + unlimited QR codes).**

A campaign is one offer with one landing page. The business gets as many QR codes as they want against that page — one per channel, one per zip code, one per print run. Doesn't matter. Each code is a separate tracking channel feeding into the same offer funnel.

| Scenario | Monthly Cost |
|----------|-------------|
| 1 offer, 4 channels | $99 |
| A/B test (2 versions of same offer) | $198 |
| 2 different offers | $198 |
| Regional franchise, 6 locations × 1 offer each | $594 |

### Why $99

- **Tangible deliverable.** The landing page is the thing they're paying for. They can see it, visit it, share it. It's a creation, not an abstraction.
- **Low relative to ad spend.** $99 is < 10% of a typical $1,000–3,000/month offline ad budget. Easy to justify.
- **Easy to say yes.** Low enough for a "try it for a quarter" commitment. The first month's report either proves value or it doesn't.
- **Natural upsell.** More offers = more pages. Multi-location = per-location. Growth is organic.

### Landing Page Ownership Model

**The landing page is our infrastructure, not their canvas.** Customers configure it; they don't design it.

**At creation:** We build the page from customer-provided inputs: logo, brand colors, offer headline, offer description, CTA preferences (call, form, email, SMS), and any legal/disclaimer text. Assembled into a template. One review cycle to confirm accuracy (typos, wrong phone number). Included in $99/mo.

**After launch — self-serve content fields (free, anytime):** Customers can update offer text, headline, phone number, and CTA copy through a constrained editor. These are the fields that change legitimately: "spring special went from $49 to $59," "new phone number." No cost, no support ticket, no waiting.

**Structural changes — paid rewrite window ($49, 7 days):** Template changes, logo swap, CTA type changes (drop form, add SMS), or offer structure overhauls require a rewrite. $49 opens a 7-day window. Customer submits their new inputs during the window. We rebuild. Window closes, page goes live. If they miss the window, the $49 is spent — open another. No review cycle on rewrites; if they submitted the wrong logo, that's another window. The window creates urgency and prevents open-ended work.

**What they can never do:** Upload arbitrary HTML. Change the page layout. Add scripts. Modify tracking elements. The page structure is ours — it's what makes the tracking work.

| Action | Cost | Mechanism |
|--------|------|-----------|
| Initial page creation + 1 review | Included in $99/mo | Concierge at launch, templated later |
| Update offer text, headline, phone, CTA copy | Free, anytime | Self-serve constrained editor |
| Structural rewrite (template, logo, CTA types, layout) | $49, 7-day window | Submit inputs, we rebuild |

**Why $49?** For a business paying $99/mo, $49 is half their monthly cost — enough friction to stop casual "let's try a different look" requests, but low enough that a legitimate rebrand or seasonal overhaul isn't blocked. If customers reopen every month, raise to $99 (matching the subscription makes the signal unmistakable).

### On Cancellation

QR codes redirect to the customer's primary website for 1 year after cancellation. This removes the objection "what about the 5,000 door hangers I already printed?" and signals we're not holding codes hostage. Reduces churn paradoxically — customers don't feel trapped, so they stay longer.

**Known risk: free-rider exploit.** A customer signs up, gets their landing page built (human labor), prints QR codes on thousands of mailers, cancels after month 1. They paid $99 for onboarding + 12 months of free redirects to their website. The redirect-on-cancel policy is generous by design, but without a minimum commitment the onboarding labor is unrecoverable. Options to address: (a) 3-month minimum commitment, (b) redirect-on-cancel only available after N months of active subscription, (c) accept the risk as a cost of reducing friction during early growth and revisit when it becomes a real pattern. No decision yet — monitor during first 10 customers.

### First-Month Economics

The first month of any new customer is likely negative margin. Concierge onboarding (collect assets, build page, review cycle) is 1-3 hours of labor. At $99 with no setup fee, that's $33-99/hr before infrastructure costs. This is deliberate — the setup fee was dropped to reduce friction for early adoption. The doc should be explicit: month 1 is a loss-leader. Margin improves from month 2 onward. A setup fee ($49-99) should be introduced once the onboarding process is understood well enough to price it fairly, likely after 10-15 customers.

## What Exists Today (Technical)

| Component | Status | Maps To |
|-----------|--------|---------|
| Gateway (redirect engine) | Built | Routes QR scan to landing page |
| Campaign model | Built | Groups codes under one offer |
| Short link + QR generation | Built | Per-channel tracking codes |
| Redirect events | Built | Scan tracking (top of funnel) |
| Negative cache | Built | Bot scan protection |
| Link cache + sweeper | Built | Hot path performance |
| Email infrastructure (Postmark) | Built | Monthly report delivery |
| Auth + session management | Built | Customer portal access |
| Payment integration (Authorize.Net) | Built | Subscription billing |

## What Needs to Be Built

| Component | Purpose | Complexity |
|-----------|---------|------------|
| Hosted landing pages | Branded offer pages with templated layouts | Medium — not a page builder. 3–4 templates, customer provides logo/colors/copy/offer |
| CTA engagement tracking | Track tap-to-call, email click, form submit, SMS tap as engagement events | Low — events on our own domain, no third-party integration |
| Engagement event model | New event type linked to campaign + channel, distinct from redirect_event | Low — extends existing event pattern |
| Unique visitor tracking | Deduplicate visitors per channel (cookie or fingerprint on our domain) | Low-Medium — we own the landing page domain, so first-party cookies work |
| Engagement rate computation | Engagements / unique visitors per channel, with confidence thresholds | Low — aggregation logic, not new infrastructure |
| Channel funnel report | Per-campaign breakdown: scans → unique visitors → engagements → engagement rate + signal confidence | Medium — aggregation queries + email template |
| Landing page management UI | Constrained editor for content fields; admin tools for structural builds | Medium — depends on who does onboarding (us vs self-serve) |
| Report delivery | Scheduled monthly digest email | Low — email infra exists, needs report template + scheduler |

### Landing Page Hosting Architecture (Decided)

**Decision: Routes on `surface-website`, extract to `surface-offers` when scale demands it.**

Customer landing pages live as a route group on the existing SvelteKit website (e.g., `(offers)/[code]/+page.svelte`). The gateway 302 redirects to this route. SvelteKit SSR fetches campaign data via `sdk-ts` and renders the landing page.

**Why this approach:**
- Svelte component library enables unlimited template variety. Each campaign carries a `template_id` that selects which Svelte component renders. New templates are new component files — no schema changes, no API changes, no server redeploy.
- Familiar tooling. Svelte + TailwindCSS is the established stack. Design iteration is fast.
- No new deployable for MVP. Reuses existing Railway service.
- Route group isolation (`(offers)`) keeps landing pages separate from marketing pages and the customer portal.
- The two-hop latency (gateway 302 → SvelteKit SSR → API call) is sub-100ms intra-Railway. Imperceptible to a consumer scanning a QR code.

**Template model:**
- Each landing page template is a Svelte component in a templates directory
- Campaign record carries `template_id` selecting the component
- Templates receive campaign data as props: logo URL, brand colors, headline, offer text, CTA configuration
- Adding a new template = adding a Svelte component. No backend changes.
- Template variety is a product feature, not an engineering constraint

**SEO isolation:** All offer routes get `noindex, nofollow` meta tags. Optionally excluded from `sitemap.xml`.

**Cookie scoping:** First-party cookies on the website domain for unique visitor tracking. Same domain as the marketing site, which is acceptable — offer pages don't need isolated cookie space.

**Domain strategy:** Industry-targeted subdomains (e.g., `acwork.nvites.me/code`) remain an option. SvelteKit can parse the `Host` header in `hooks.server.ts` to resolve subdomain context. Requires Railway wildcard DNS + subdomain routing config. Not needed for MVP — can be added when consumer-facing URL trust becomes a measurable concern.

**Maintenance mode risk:** The existing website enters maintenance mode via `PUBLIC_MODE` env var, which would take down active landing pages. Acceptable for the first 10-20 customers (website deploys are infrequent). When landing page uptime becomes critical, extract to `surface-offers` — the Svelte components, route logic, and SDK calls move wholesale (SvelteKit to SvelteKit, not a rewrite).

**Gateway changes needed:** The `short_link.url` field currently holds the customer's destination URL. For campaigns with hosted landing pages, this becomes the offer route URL on the website (e.g., `https://website.nvites.me/o/{code}`). The gateway's 302 redirect behavior is unchanged — it doesn't need to know whether the destination is our landing page or an external URL.

## The Wrapper

QR codes are not the product. QR codes are the mechanism — the same way paintball is the mechanism for a park that's really a software company.

The product is **marketing accountability.** The customer pays for a landing page that tracks their advertising. The QR codes, the gateway, the analytics engine — that's the edge that makes the service work. The customer never needs to understand or care about it.

This framing matters for positioning:
- We are **not** "another QR code platform" competing with QR Tiger at $7/month
- We are **not** "an analytics dashboard" competing with Google Analytics
- We are "the company that tells you which of your ads bring customers"

## Go-to-Market

### The Sales Reality

We are not selling against competitors. We are selling against *nothing.* QR codes on local business mailers are recent behavior. Anecdotal evidence suggests very few businesses are deliberately tracking scan-to-engagement funnels. The status quo isn't "I measure fine without you" — it's "I've never had a way to measure this." This is an easier sale than overcoming active resistance: the pitch isn't "switch from your current solution," it's "now you can know."

### GTM Model

**Direct consulting for launch. Print partnership at scale. Guided self-serve as a product maturity milestone, not a sales channel.**

1. **Direct consulting (launch).** Approach HVAC/plumbing/landscaping companies directly. "You spend on mailers — I'll tell you which ones work." High-touch, relationship-driven. Works for first 10–30 customers. Doesn't scale without delegation.

2. **Print partnership (scale).** Partner with or acquire a local print shop. The print shop already has the customer relationships. QR tracking becomes a value-add on every print job. "We now offer tracked mailers." Lower customer acquisition cost, but adds operational dependency.

3. **Guided self-serve (maturity).** Customer signs up, provides logo/colors/offer, we generate pages and codes. Light onboarding call. Build toward it as templates, editor, and onboarding flow mature — not a launch model.

### Who to Sell To First

- Hyper-local service businesses already spending on offline media
- HVAC, roofing, plumbing, landscaping, pest control, home services
- Ideally multi-location or franchise — one sale = multiple campaigns
- The founder is the first customer (personal offline attribution project), providing real-world validation and friction discovery
- Next 2-3 customers from personal network, free or discounted, for case study material

### Leverage Point

The first 3 independent case studies with real numbers are worth more than any feature. "ABC Heating discovered 40% of their ad spend was going to channels that generated zero engagements" — that's the sales pitch for customer #11. The founder's own project validates the tech; external businesses validate the market.

## Known Limitations and Failure Modes

This system measures **inbound engagement**, not revenue. It produces directional truth — consistent relative differences between channels — not absolute attribution. This is the same constraint that applies to every marketing measurement tool, including Google Analytics and enterprise multi-touch platforms. The difference is that our customers are comparing against *nothing*, not against a better tool.

### Terminology

Use **"engagement events"** for CTA interactions (tap-to-call, form submit, email click, SMS tap). Do not call them "conversions." We don't own the conversion — we own the engagement. Using "conversion" sets an expectation the system can't meet and creates the data-perception conflict described below.

### Failure Modes to Design Around

**Offer dominance (severity: high).** The system measures channel × offer × placement × timing, not pure channel performance. A strong offer on a weak channel beats a weak offer on a strong channel. If "Free Diagnostic" runs on door hangers and "$10 Off" runs on the truck wrap, the customer can't tell if the channel won or the offer won. **Mitigation:** Reports must state: "This measures how your offer performs within each channel." To isolate variables: same offer across different channels tests the channel; same channel with different offers (A/B at $198) tests the offer. Flag when offer variation makes cross-channel comparison unreliable.

**Intent ≠ revenue (severity: high).** Channel A generates 20 engagements → 2 jobs. Channel B generates 10 engagements → 8 jobs. Engagement rate favors A, but B is more valuable. **Mitigation:** Reports frame output as opportunity generation. Include language: "A channel with fewer but higher-quality leads may outperform one with higher volume. Apply your close rates to these numbers." Future: optional customer-reported outcome field.

**False confidence (severity: high).** The system presents structured numeric output that appears precise but is inherently approximate. 23 engagements vs 20 engagements may be noise, not signal. **Mitigation:** Confidence indicators on every channel row (Strong / Weak / Insufficient Data) based on volume thresholds. Reports emphasize large deltas only. Small differences are explicitly flagged as inconclusive.

**Channel contamination (severity: medium).** Repeated scans, shared links, internal testing, and non-customer interactions inflate or distort channel performance. **Mitigation:** Report unique visitors, not just total scans. Track first-time engagements separately from repeat interactions. Flag suspicious patterns (e.g., same device scanning across multiple channels).

**Data-perception conflict (severity: high).** Customer says "we got 20 jobs this month" but the report shows 12 engagements. The gap erodes trust. **Mitigation:** Set expectations during onboarding — the system tracks the QR-driven funnel, not all inbound. Include a standing explanation in every report about what is and isn't captured.

**Attribution undercounting (severity: medium, likelihood: high).** Someone sees the truck wrap, remembers the brand, Googles later, calls directly. Untracked. **Mitigation:** Frame as directional. Focus reports on relative channel comparison via engagement rate, not absolute counts. The customer went from zero measurement to "door hangers generated 23 engagements." That's a massive upgrade even if the true number is 35.

**QR behavior bias (severity: medium).** Channels that naturally encourage scanning outperform channels that don't, regardless of true effectiveness. A door hanger with a strong CTA gets scans; a yard sign doesn't. **Mitigation:** Onboarding guidance on QR placement, not product features. Don't compare fundamentally different mediums without context in reports.

**User bypass (severity: medium).** Phone number on the ad gets used instead of QR. Brand is remembered and searched later. **Mitigation:** Prioritize channels where scanning is natural. Future: optional call tracking numbers and branded short links as fallback paths.

**Low signal volume (severity: medium).** Small campaigns produce inconclusive data. 3 engagements total across 4 channels means nothing. **Mitigation:** Customer qualification problem, not product problem. Set minimum campaign size during sales. Confidence indicators flag low-volume channels automatically.

**Time lag distortion (severity: medium).** Offline engagements aren't immediate — a user scans today, calls 3 days later directly. The system skews toward immediate-response channels. **Mitigation:** Position clearly: this captures immediate response. Accept as system constraint.

**Churn from success (structural).** If the report works perfectly and the customer cuts 2 losing channels, they go from 4 campaigns ($396) to 2 ($198). The better the product works, the less they need. **Counter:** Good results create trust → new offers, seasonal campaigns, referrals. The natural lifecycle of a successful customer is: optimize existing → launch new. But be aware that the first motion is consolidation.

### System Constraints (Accepted)

- **No cross-channel identity.** Cannot track users who move from offline impression to non-QR digital paths. Industry-wide limitation.
- **No revenue visibility.** Cannot observe downstream booking or revenue without integration. Engagement is the proxy. Future: optional CRM hooks for customers who grow into it.
- **No delayed attribution.** System captures immediate response, not users who return days later through other channels.
- **Behavior dependency.** Accuracy depends on users scanning and engaging through the controlled funnel. The system measures the QR-driven funnel, not all inbound.

The system undercounts total performance but preserves relative signal between channels. This is the correct tradeoff.

### Competitive Positioning vs Call Tracking

Unique phone numbers per channel is a valid alternative for call-only measurement. Our defense: we track 4 CTA types (call, form, email, SMS) not just one, provide full funnel visibility (scan → visit → engagement), require zero telecom infrastructure, and deploy faster. Call tracking is a future enhancement we can add, not a competitive replacement for the full funnel.

### Future Signal Enhancement (Phased)

| Phase | Capabilities |
|-------|-------------|
| Launch | Engagement event tracking (call, form, email, SMS), unique visitors, engagement rate, confidence indicators |
| Enhanced signal | Call tracking numbers, SMS attribution, customer-reported outcome feedback |
| Partial revenue linkage | CRM integrations, booking system hooks, manual revenue tagging |
| Advanced | Multi-touch modeling, cross-channel blending (only if market demands it) |

## Open Questions

### Resolved or Partially Resolved

1. **Who builds the landing page — us or the customer?** For the first 10 customers, us (concierge). Eventually self-serve via the constrained editor. The Landing Page Ownership Model section defines what's editable vs what requires a paid rewrite.

2. **How branded do pages need to be?** Logo + brand colors + correct copy is sufficient. Confirmed assumption — customers are unlikely to care about pixel-perfect brand identity on a promotional landing page.

3. **What CTA types matter most?** Tap-to-call is the primary engagement event for home services. Form submit and SMS are secondary. Build tap-to-call first.

4. **Monthly vs weekly reporting cadence?** Monthly report is the decision document. Offline marketing has inherent lag — you can't stop a mailer mid-cycle or change pricing mid-campaign. A weekly summary and customer portal for real-time curiosity are nice-to-haves, not launch requirements. The report is what drives decisions; the portal satisfies "how's it going?" between reports.

5. **Do we need a customer-facing dashboard?** Not at launch. Monthly email report is the product interface. A portal for real-time data is a post-launch addition when customers ask for it (and they will — but the monthly report must work standalone first).

6. **Landing page hosting architecture.** Resolved — routes on `surface-website` with `template_id` per campaign selecting Svelte components. Extract to `surface-offers` at scale. See Landing Page Hosting Architecture section.

### Unresolved

7. **Sales channel — deep dive needed.**

    To get up to speed on this question, read the GTM Model and Who to Sell To First sections above, then work through the phased thinking below. The pitch is settled. The delivery mechanism is not.

    **Phase 0 — Founder as customer #1.** Use the product on your own offline attribution project. Learn what onboarding requires. Generate the first real funnel data. Not a sales phase.

    **Phase 1 — Eat your own dog food.** The strongest opening move: send a direct mailer to ~200 local home service businesses with a QR code that lands on your own offer page, built with your own system. The prospect experiences the entire product as part of the sales pitch. Track who scans. Follow up with scanners — they're warm leads, not cold calls. Target: 2-3 free or discounted customers from this batch in exchange for case study permission. Cost: ~$300-500 for printing and postage.

    **Phase 2 — Case studies unlock peer selling.** With 3 real case studies, the pitch shifts from "try this" to "here's what your competitor learned." Referral incentive (one month free per signup) leverages the tight social network between local trades — the HVAC owner knows the plumber, electrician, roofer. Target: 10 paying customers.

    **Phase 3 — Systematic outreach.** Repeat the mailer at scale (now with case study data in the mailer itself). BNI / local networking groups (weekly meetings, designed for referral selling). Trade association events (ACCA, PHCC, local chapters). Local business owner Facebook groups (post the case study as a story, not a pitch).

    **Phase 4 — Partnerships.** Print shops (referral fee or rev share, they mention the option and hand you the lead). Local marketing consultants (your reports give them data they can't get elsewhere). Franchise networks (one relationship = many locations).

    **Seasonal timing matters.** HVAC ramps marketing in March-April (spring AC) and September-October (heating). Roofers push after storm seasons. Landscapers push early spring. Pitch right before they print their next campaign: "Before you print your spring mailers, let me put tracking on them."

    Questions still open:
    - What metro area / local market to target first?
    - What does the phase 1 mailer actually say? (Design the mailer as a product exercise — you're customer #0.)
    - BNI chapter selection — which local groups have the right trade mix?
    - What's the referral incentive structure? One month free? Discount? Credit toward additional campaigns?

8. **What does the cancellation redirect experience look like?** Codes redirect to customer's primary URL. 301 vs 302? Generic interstitial vs clean redirect? Free-rider risk (see On Cancellation section) may influence the design — e.g., a branded interstitial "This offer was powered by nvites.me" as a middle ground.

9. **Print partnership logistics.** Revenue share, white-labeling, who sells. Deferred — direct consulting is the launch GTM, print partnership is a phase 4 scale play.

10. **MVP definition.** What is the minimum feature set to onboard customer #1 (the founder)? The build table describes the full product, not the first usable version. A hand-built landing page, engagement event tracking, and raw funnel data may be enough for the founder's own project. Sequencing the build table into "MVP for me" vs "product for customer #10" is needed before development starts. No longer blocked on architecture — landing page hosting is decided.
