# SvelteKit SEO Framework Adapter

SEO patterns specific to SvelteKit. The main SKILL.md defines *what* to audit; this file defines *how* it manifests in SvelteKit code.

## Meta Tag Placement

### `<svelte:head>` is the mechanism

All meta tags, titles, JSON-LD, and link elements go in `<svelte:head>` blocks.

**Layout vs. page responsibility:**

| Element | Where | Why |
|---|---|---|
| `<meta charset>`, `<meta viewport>` | Root layout (`+layout.svelte`) or `app.html` | Framework-provided, site-wide |
| `<meta name="theme-color">`, favicon | Root layout | Site-wide branding |
| `<meta name="robots" content="noindex">` | Group layout (e.g., `(auth)/+layout.svelte`) | Applies to all children in the group |
| `<title>`, `<meta description>` | Each `+page.svelte` | Must be unique per page |
| `<link rel="canonical">` | Each `+page.svelte` | Derived from `$page.url` |
| Open Graph / Twitter Card | Each `+page.svelte` | Page-specific content |
| JSON-LD structured data | Each `+page.svelte` | Page-specific schema |

**Key rule:** Layouts set defaults and noindex directives. Pages set page-specific meta. If a page doesn't set a `<title>`, SvelteKit won't provide a fallback — the page will have no title tag, which is a blocker.

### Dynamic titles from server data

```svelte
<script>
  let { data } = $props();
</script>

<svelte:head>
  <title>{data.product.name} | Urban Warzone</title>
  <meta name="description" content={data.product.description.slice(0, 160)} />
</svelte:head>
```

The title template from `seo.json → defaults.titleTemplate` should be applied manually in each page's `<svelte:head>`. SvelteKit has no built-in title template system.

### Canonical URLs

```svelte
<script>
  import { page } from '$app/state';
  // Use seo.json baseUrl, not $page.url (which reflects the request, not the canonical domain)
  const canonicalBase = 'https://urbanwarzonepaintball.com';
</script>

<svelte:head>
  <link rel="canonical" href="{canonicalBase}{$page.url.pathname}" />
</svelte:head>
```

**Warning:** Do NOT use `$page.url.origin` for canonicals — it reflects the request origin, which may be `localhost`, a preview URL, or a CDN domain. Always use the hardcoded canonical base from seo.json.

## Data Loading and SEO

### Server loads (`+page.server.ts`) are SSR-friendly

Data from `+page.server.ts` is available during SSR. Titles and meta tags that depend on this data will be rendered into the initial HTML — crawlers will see them.

```typescript
// +page.server.ts
export const load = async ({ locals }) => {
  const products = await api.getProducts();
  return { products };
};
```

```svelte
<!-- +page.svelte — title available at SSR time -->
<svelte:head>
  <title>Paintball Packages | Urban Warzone</title>
</svelte:head>
```

### Client-side state is NOT crawler-visible

Content that loads after hydration (client-side fetches, reactive state changes) will NOT be in the initial HTML. Crawlers may not execute JavaScript. Everything SEO-critical must be in the server-rendered output.

**Anti-pattern:**
```svelte
<!-- BAD: title depends on client-side state -->
<script>
  let selectedTab = $state('packages');
</script>
<svelte:head>
  <title>{selectedTab} | Urban Warzone</title>
</svelte:head>
```

The initial SSR will render the default value, but tab switches won't update the crawled title.

## Prerendering

### `export const prerender = true`

Pages with this flag are built at build time as static HTML. SEO implications:

- **Canonical URLs** are fine — the HTML is identical regardless of serving origin.
- **Dynamic data** is frozen at build time. Product prices in structured data will be stale if not rebuilt.
- **Sitemap** — prerendered pages have predictable URLs and can be enumerated at build time.

### Selective prerendering

SvelteKit can prerender some pages and SSR others. For SEO:
- Marketing pages (home, about) → prerender for performance (better LCP).
- Dynamic catalog pages (packages with live pricing) → SSR for freshness.
- Auth-gated pages → SSR (prerendering would expose the auth redirect).

## Sitemap Generation

SvelteKit does not generate sitemaps automatically. Options:

### 1. `+server.ts` endpoint (recommended)

```typescript
// src/routes/sitemap.xml/+server.ts
import type { RequestHandler } from './$types';

export const GET: RequestHandler = async () => {
  // Enumerate indexed routes from seo.json or database
  const pages = [
    { path: '/', changefreq: 'weekly', priority: 1.0 },
    { path: '/packages', changefreq: 'weekly', priority: 0.9 },
    // ... dynamically add /gallery/[id] entries from DB
  ];

  const xml = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${pages.map(p => `  <url>
    <loc>https://urbanwarzonepaintball.com${p.path}</loc>
    <changefreq>${p.changefreq}</changefreq>
    <priority>${p.priority}</priority>
  </url>`).join('\n')}
</urlset>`;

  return new Response(xml, {
    headers: { 'Content-Type': 'application/xml' }
  });
};
```

### 2. Build-time generation

For fully prerendered sites, generate `sitemap.xml` as part of the build pipeline. Not applicable when dynamic routes exist.

## robots.txt

### Static file approach

Place `robots.txt` in `static/robots.txt`:

```
User-agent: *
Allow: /
Disallow: /portal/
Disallow: /api/

Sitemap: https://urbanwarzonepaintball.com/sitemap.xml
```

### Dynamic approach

If robots.txt needs to vary by environment, use a `+server.ts` endpoint at `src/routes/robots.txt/+server.ts`.

## Trailing Slashes

Configure in `svelte.config.js`:

```javascript
const config = {
  kit: {
    trailingSlash: 'never' // or 'always' — pick one, be consistent
  }
};
```

This must match `seo.json → site.trailingSlash`. Mismatches cause duplicate URLs (with and without trailing slash), splitting link equity.

## Layout Groups and Noindex

SvelteKit's parenthesized layout groups (e.g., `(auth)`, `(public)`) affect SEO via shared layouts:

```
src/routes/
  (public)/        ← indexed pages, no robots meta needed
    +layout.svelte
    packages/
    gallery/
  (auth)/          ← noindex in layout
    +layout.svelte ← adds <meta name="robots" content="noindex, nofollow">
    login/
    register/
  portal/          ← noindex + auth guard
    +layout.svelte ← adds <meta name="robots" content="noindex, nofollow">
    +layout.server.ts ← redirects to /login if no token
```

The `noindex` meta should be in the group's `+layout.svelte`, not repeated in every child page. This is the **layout-level meta** referenced in the conflict resolution hierarchy.

## SvelteKit-Specific Anti-patterns

- **Universal loads for SEO data** — `+page.ts` (not `+page.server.ts`) runs on both server and client. It cannot access `$env/static/private` or `locals`. Never put SEO-critical data loading in universal loads if it requires server-only resources.
- **`goto()` for navigation** — programmatic navigation via `goto()` doesn't produce crawlable links. Crawlers follow `<a href>` elements. Use `goto()` for UX, but ensure every important destination also has an `<a>` link somewhere.
- **Missing `<svelte:head>` in pages** — SvelteKit doesn't warn about missing titles. A page without `<svelte:head>` will have no `<title>` tag — a silent blocker.
- **`$page.url` for canonicals** — reflects the runtime URL, not the canonical domain. Use the hardcoded base URL from seo.json.
