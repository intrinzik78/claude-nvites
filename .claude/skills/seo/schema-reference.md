# Schema.org Property Reference

Validation reference for JSON-LD structured data generation. Each type lists required properties, recommended properties, common mistakes, and Google Rich Results eligibility.

Use this when auditing or generating structured data. If a required property is missing, flag as **blocker**. If a recommended property is missing, flag as **warning**.

---

## Organization

**When to use:** Site-wide, on the home page. Establishes the entity behind the site.

| Property | Required | Notes |
|---|---|---|
| `@type` | Yes | `"Organization"` |
| `name` | Yes | Legal or commonly known business name |
| `url` | Yes | Canonical home URL |
| `logo` | Recommended | `ImageObject` or URL. Min 112x112px, square preferred |
| `sameAs` | Recommended | Array of social profile URLs (Facebook, Instagram, etc.) |
| `contactPoint` | Recommended | `ContactPoint` with `telephone`, `contactType` |

**Google Rich Results:** Organization logo can appear in Knowledge Panel. Requires `logo` and `name` at minimum.

**Common mistakes:**
- Using a relative URL for `logo` (must be absolute)
- Listing social URLs that don't actually belong to the business
- Duplicating Organization on every page (should be on home page only, or use `@id` references)

---

## LocalBusiness

**When to use:** Home page for businesses with a physical location. Extends Organization.

| Property | Required | Notes |
|---|---|---|
| `@type` | Yes | Specific type: `"SportsActivityLocation"`, `"EntertainmentBusiness"`, etc. |
| `name` | Yes | Business name |
| `url` | Yes | Canonical URL |
| `address` | Yes | `PostalAddress` with `streetAddress`, `addressLocality`, `addressRegion`, `postalCode`, `addressCountry` |
| `telephone` | Recommended | Include country code |
| `openingHoursSpecification` | Recommended | Array of `OpeningHoursSpecification` with `dayOfWeek`, `opens`, `closes` |
| `geo` | Recommended | `GeoCoordinates` with `latitude`, `longitude` |
| `priceRange` | Recommended | `"$"` to `"$$$$"` |
| `image` | Recommended | Representative photo of the business |
| `logo` | Recommended | Business logo |
| `sameAs` | Recommended | Social profile URLs |

**Google Rich Results:** Eligible for local Knowledge Panel, Maps integration, and local pack results. Requires `name`, `address`, and `@type` at minimum.

**Common mistakes:**
- Using generic `"LocalBusiness"` instead of a specific subtype (`SportsActivityLocation`)
- `openingHoursSpecification` format errors — must use ISO day names (`Monday`, not `Mon`)
- Missing `addressCountry` (required for unambiguous geocoding)
- `priceRange` left as `"TODO"` in production

**Note on `openingHours` vs `openingHoursSpecification`:**
- `openingHours` is the simple format: `"Mo-Fr 10:00-22:00"` — easier to write, less precise
- `openingHoursSpecification` is the structured format — supports seasonal hours, holidays, etc.
- For businesses with simple consistent hours, `openingHours` is sufficient. For complex schedules, use `openingHoursSpecification`.

---

## Product

**When to use:** Pages displaying products/packages with prices.

| Property | Required | Notes |
|---|---|---|
| `@type` | Yes | `"Product"` |
| `name` | Yes | Product name |
| `description` | Recommended | Product description, plain text |
| `image` | Recommended | Product image URL(s) |
| `offers` | Yes (for rich results) | `Offer` or `AggregateOffer` |
| `offers.price` | Yes | Numeric price |
| `offers.priceCurrency` | Yes | ISO 4217 code (e.g., `"USD"`) |
| `offers.availability` | Recommended | `"https://schema.org/InStock"`, `"OutOfStock"`, etc. |
| `offers.url` | Recommended | URL to purchase/book |
| `sku` | Recommended | Unique product identifier |
| `brand` | Recommended | `Brand` or `Organization` |

**Google Rich Results:** Eligible for product snippets (price, availability, rating in search results). Requires `name` + `offers` with `price` and `priceCurrency`.

**Common mistakes:**
- `price` as a string with currency symbol (`"$25"`) instead of numeric (`25`) with separate `priceCurrency`
- Missing `priceCurrency` — Google requires it for rich results
- `availability` using plain text instead of Schema.org URL (`"In Stock"` vs `"https://schema.org/InStock"`)
- Structured data price doesn't match the visible price on the page — Google will penalize or suppress the rich result
- Using `Product` for service packages — technically valid, but `Service` with `offers` may be more accurate

**For per-person pricing:**
```json
{
  "@type": "Offer",
  "price": "25",
  "priceCurrency": "USD",
  "eligibleQuantity": {
    "@type": "QuantitativeValue",
    "unitText": "per person"
  }
}
```

---

## BreadcrumbList

**When to use:** Every public page. Reflects the navigational hierarchy.

| Property | Required | Notes |
|---|---|---|
| `@type` | Yes | `"BreadcrumbList"` |
| `itemListElement` | Yes | Array of `ListItem` |
| `itemListElement[].@type` | Yes | `"ListItem"` |
| `itemListElement[].position` | Yes | Integer, 1-indexed |
| `itemListElement[].name` | Yes | Human-readable label |
| `itemListElement[].item` | Yes (except last) | URL of the breadcrumb. Omit on the current/last item. |

**Google Rich Results:** Eligible for breadcrumb trail in search results. Replaces the raw URL with a navigational path.

**Common mistakes:**
- Including `item` URL on the last breadcrumb (current page) — should be omitted per Google's guidelines
- `position` starting at 0 instead of 1
- Breadcrumb trail not matching actual site navigation (fabricated hierarchy)
- Missing the home page as position 1

**Example:**
```json
{
  "@type": "BreadcrumbList",
  "itemListElement": [
    { "@type": "ListItem", "position": 1, "name": "Home", "item": "https://example.com/" },
    { "@type": "ListItem", "position": 2, "name": "Packages" }
  ]
}
```

---

## ImageGallery

**When to use:** Pages displaying collections of images (gallery index, album detail).

| Property | Required | Notes |
|---|---|---|
| `@type` | Yes | `"ImageGallery"` |
| `name` | Yes | Gallery/album name |
| `description` | Recommended | What the gallery contains |
| `url` | Recommended | Canonical URL of the gallery page |
| `image` | Recommended | Array of `ImageObject` |
| `datePublished` | Recommended | When the gallery was created/published |
| `author` | Recommended | `Organization` or `Person` |

**Nested ImageObject:**

| Property | Required | Notes |
|---|---|---|
| `@type` | Yes | `"ImageObject"` |
| `contentUrl` | Yes | Direct URL to the image file |
| `name` | Recommended | Descriptive name |
| `description` | Recommended | What the image shows |
| `thumbnail` | Recommended | `ImageObject` with smaller version |
| `width` | Recommended | Integer pixels |
| `height` | Recommended | Integer pixels |

**Google Rich Results:** Images may appear in Google Images with enhanced metadata. No specific rich result card, but proper `ImageObject` markup improves image search visibility.

**Common mistakes:**
- Using `url` instead of `contentUrl` for the image file
- Missing `width`/`height` (helps Google understand layout without fetching)
- Empty or generic `description` on every image
- Not including a representative `image` on the gallery container itself

---

## FAQPage

**When to use:** Pages with question-and-answer content. Only if the page genuinely has FAQ format.

| Property | Required | Notes |
|---|---|---|
| `@type` | Yes | `"FAQPage"` |
| `mainEntity` | Yes | Array of `Question` |
| `mainEntity[].@type` | Yes | `"Question"` |
| `mainEntity[].name` | Yes | The question text |
| `mainEntity[].acceptedAnswer` | Yes | `Answer` object |
| `mainEntity[].acceptedAnswer.@type` | Yes | `"Answer"` |
| `mainEntity[].acceptedAnswer.text` | Yes | The answer (can include HTML) |

**Google Rich Results:** Eligible for FAQ rich result (expandable Q&A in search results). High-value SERP real estate.

**Common mistakes:**
- Using FAQPage on pages without visible Q&A content (SEO theater — Google will suppress)
- `text` containing only a link ("See our pricing page") instead of a real answer
- Duplicating FAQ structured data across multiple pages with the same questions
- More than ~10 questions (Google may truncate)

---

## Event

**When to use:** Pages promoting specific scheduled events (if applicable).

| Property | Required | Notes |
|---|---|---|
| `@type` | Yes | `"Event"` or specific subtype (`"SportsEvent"`) |
| `name` | Yes | Event name |
| `startDate` | Yes | ISO 8601 datetime |
| `location` | Yes | `Place` with `name` and `address` |
| `description` | Recommended | Event description |
| `endDate` | Recommended | ISO 8601 datetime |
| `image` | Recommended | Event image |
| `offers` | Recommended | Ticket/booking `Offer` |
| `organizer` | Recommended | `Organization` or `Person` |
| `eventStatus` | Recommended | `"EventScheduled"`, `"EventCancelled"`, etc. |
| `eventAttendanceMode` | Recommended | `"OfflineEventAttendanceMode"` for in-person |

**Google Rich Results:** Eligible for event snippets in search. Requires `name`, `startDate`, `location` at minimum.

**Common mistakes:**
- `startDate` without timezone offset (`2026-03-15` instead of `2026-03-15T10:00:00-05:00`)
- Using Event for recurring availability (like "open every Saturday") — Event is for specific occurrences
- Missing `eventStatus` (defaults to scheduled, but explicit is better)

---

## @graph Pattern

When a page needs multiple types, wrap them in a single `@graph`:

```json
{
  "@context": "https://schema.org",
  "@graph": [
    {
      "@type": "LocalBusiness",
      "@id": "https://example.com/#business",
      "name": "...",
      ...
    },
    {
      "@type": "BreadcrumbList",
      "itemListElement": [...]
    },
    {
      "@type": "Product",
      "name": "...",
      ...
    }
  ]
}
```

**Rules:**
- One `<script type="application/ld+json">` tag per page, containing the `@graph`.
- Use `@id` on the Organization/LocalBusiness so other types can reference it (e.g., Product's `brand`).
- `@context` appears once at the top level, not on each item.
