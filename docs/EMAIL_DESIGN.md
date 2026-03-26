# Email Design Guide

## Image Hosting

- **Location:** `surface-website/static/images/email/transactional/`
- **URLs:** `{{site_url}}/images/email/transactional/{filename}`
- **Files:** `email-header.png`, `email-footer.png`
- **`site_url`:** Every email struct carries `site_url: &'a str`, sourced from `shared.settings().site_url`. Templates use `{{site_url}}` for image paths. Renders correctly in local dev, staging, and production.
- **Fallback:** If domain-hosted images hit deliverability issues in any client, migrate to a GCS bucket. The switch is URL-only - no structural rework.
- **Rationale:** Domain alignment between sender address and image host is a positive deliverability signal. Postmark delivers HTML as-is (no image proxying like Constant Contact).

## Layout

- **Structure:** Header image -> light content area -> footer image -> legal line
- **Header/Footer:** Pre-built branded images, same across all templates. Dark backgrounds, green accents.
- **Header section:** `background-color="#ffffff"` on the wrapping `<mj-section>` to prevent transparency bleed.
- **Content area:** White (`#ffffff`) background. Left-justified details, centered headings and totals.
- **Location:** Hardcoded in template with Google Maps link (single location business).
- **Times:** Local time only, no UTC offset. Local business.

## Typography

- **Headings:** Black Ops One (Google Fonts). Name-first format ("{name}, mission confirmed").
- **Section labels:** Black Ops One, uppercase, underlined, brand accent green.
- **Body text:** System font stack (`system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial, sans-serif`)
- **Detail labels:** Bold inline labels ("**Booked:** ...", "**Date:** ...").

## Color Palette (from `surface-website/src/app.css`)

- `#047857` (emerald-700) - brand primary. Use for authoritative elements: price totals, links.
- `#10b981` (emerald-500) - brand accent. Use for decorative/navigational: section labels, reference codes.
- `#18181b` (zinc-900) - headings, detail labels.
- `#52525b` (zinc-600) - secondary body text.
- `#71717a` (zinc-500) - muted text, fine print.
- `#e4e4e7` (zinc-200) - divider lines.
- `#a1a1aa` (zinc-400) - legal/footer text.
- `#f5f5f7` - outer body background.
- `#ffffff` - content area background.

## Copy Tone

- **Confirmation/positive emails:** Tactical brand voice in headings ("{name}, mission confirmed"). Details section uses plain, scannable labels.
- **Cancellation/refund/negative emails:** Straight transactional. Clarity over personality when the situation involves money or bad news.
- **Subject lines:** Always clear and literal ("Booking Confirmed", "Booking Cancelled"). Tactical voice stays inside the email body, never in the subject line.
- **Blend rule:** Tactical headings, straight details, clear subject lines.
- **No LLM tells in customer-facing copy.** No em dashes, no "I'd be happy to", no filler. Use plain hyphens. All copy should read like a human wrote it.

## MJML / MRML Technical Notes

- **Font loading:** `<mj-font>` and CSS `@import` are stripped by MRML. The only reliable method is `<mj-class>` with inline `font-family` + registering the font in the `mrml_opts()` HashMap in `render_engine.rs`.
- **`render_strict` validation:** Every key in `to_vars()` must appear in both the MJML and text templates. If a var is HTML-only (like `site_url` for images), find a natural place in the text version.
- **Preview tests:** Every template gets an `#[ignore]` test that dumps rendered HTML to `/tmp/` for visual iteration. Run with `cargo test -p email-template -- preview_* --ignored --nocapture`.
- **Rendering:** MJML compiled to HTML + plain text via `mrml` in the `email-template` crate.
- **Sending:** Postmark transactional API, fire-and-forget via `actix_web::rt::spawn`.
- **Gate:** All sends guarded by `shared.settings().postmark_email_service == SystemFlag::Enabled`.
- **Logging:** Every send logged to `PostmarkLog` with status (Accepted/Rejected).
- **Message stream:** `Sales` for customer-facing transactional emails.
- **Copyright:** Urban War Zone Paintball.
