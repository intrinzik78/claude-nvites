# Upgrade Remaining Email Templates to New Design Pattern

**Date:** 2026-03-25
**Workstream:** server
**Origin:** handoff from email notification session - visual inconsistency flagged

## Problem

The booking confirmation and cancellation emails now use the production design pattern (branded header/footer images via `site_url`, Black Ops One headings via `<mj-class>`, light body layout, brand color palette). Three other customer-facing templates still use the old scaffolding: placeholder images, dark card layout, no `site_url` field.

Templates needing upgrade:
1. **WaiverConfirmationEmail** - `email-template/src/templates/waivers/confirmation/v1/`
2. **CallAheadConfirmationEmail** - `email-template/src/templates/queue/call_ahead_confirmation/v1/`
3. **InitialVerificationEmail** - `email-template/src/templates/verification/initial_verification/v1/`

## Approach

For each template:
1. Add `site_url: &'a str` field to the struct and `to_vars()`
2. Rewrite MJML to match the new pattern: `<mj-section background-color="#ffffff">` header image, `<mj-class name="heading">` for Black Ops One, light body, brand palette from `docs/EMAIL_DESIGN.md`
3. Update text template to include `{{site_url}}`
4. Update call sites to pass `shared.settings().site_url`
5. Add `#[ignore]` preview test
6. Copy tone: waiver and call-ahead are positive (tactical headings ok), verification is neutral/functional

**SystemAlertEmail is internal/operator-facing - skip it.**

## Reference

- `docs/EMAIL_DESIGN.md` - full design guide with color palette, typography, technical notes
- Booking confirmation template as the canonical example
- `render_engine.rs` already has Black Ops One in `mrml_opts()` - no engine changes needed

**Confidence:** High. Mechanical - same pattern applied three times.
