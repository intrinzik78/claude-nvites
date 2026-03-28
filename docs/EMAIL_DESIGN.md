# Email Design

Transactional email design guide for nvites.me.

## Stack

- **Delivery:** Postmark (sender allowlist derived from `EmailID` enum)
- **Rendering:** `email-template` crate — MJML templates compiled to HTML, with plaintext fallbacks
- **Locale:** English only (`Locale::En`), extensible

## Templates

| Template | Purpose |
|----------|---------|
| VerificationV1 | Email verification link |
| SystemAlertV1 | Dev/operator system alerts |

Future templates for nvites: campaign digest (daily/weekly analytics), account notifications.

## Adding a template

1. Create MJML + text files in `server/email-template/src/templates/{domain}/{name}/v1/`
2. Add variant to `Template` enum in `server/email-template/src/enums/template.rs`
3. Add match arms in `en_mjml()` and `en_text()`
4. Create receipt type in `server/email-template/src/types/receipts/`
