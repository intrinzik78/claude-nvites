# DISPATCH: Waiver Document Content + Post-Signing Email

**Date:** 2026-03-14
**Target:** server branch

---

## 1. Populate waiver document with real content

The seed document (`20260225100000_waiver_document_seed.sql`) has placeholder JSON:

```json
{"title":"Waiver of Liability","sections":[]}
```

This means:
- The `details_confirmed` checkbox on the waiver form is confirming a name/DOB but no waiver text — the ESIGN audit trail records the confirmation, but the UX is hollow.
- The signed waiver detail page (`/portal/waivers/{uuid}`) renders an empty document body.
- The `WaiverRecordView` component displays `docBody.title` and iterates `docBody.sections` — sections need to be an array of strings.

**Action:** Add a migration that updates the document body with real waiver-of-liability text. The JSON shape consumed by the surface is:

```json
{
  "title": "Waiver of Liability, Assumption of Risk, and Indemnity Agreement",
  "sections": [
    "Section 1 text...",
    "Section 2 text...",
    "..."
  ]
}
```

This does NOT require a template editor or contract change. The `DocumentDto` fields are `serde_json::Value` — the JSON shape is a runtime convention, not a compiled contract. When a template editor ships, the contract should tighten `body`/`signature`/`footer` to proper structs and the surface `as Record<string, unknown>` cast can be removed. Until then, this populates what already works.

**Signature and footer** can stay as-is or be updated to match:
- signature: `{"type": "typed", "label": "Type your full legal name"}`
- footer: `{"text": "By signing this document you acknowledge..."}`

## 2. Post-signing confirmation email with link to signed record

After a waiver is successfully created (`POST /v1/portal/waivers` and `/child`), the server should send a confirmation email to the signer containing:

- Confirmation that the waiver was signed electronically
- Participant name and signing timestamp
- A link to view the signed record: `{PUBLIC_HOSTNAME}/portal/waivers/{uuid}`

The `uuid` field is available on the `WaiverDto` returned by the creation handler. The signer's email is available from the authenticated session (`AuthContext`).

This satisfies ESIGN's record accessibility requirement more completely — the user receives a durable pointer to their signed record without needing to remember to check the portal.

**Scope boundary:** This dispatch covers the email trigger and template. The surface already handles the detail page at `/portal/waivers/{uuid}` (shipped in `e86fa82` on `surface-website`).

## What NOT to do

- **Do not tighten `DocumentDto` types yet.** That's a contract change (`api-contracts/`) that should ship with the template editor, not with placeholder content.
- **Do not add a template editor.** This dispatch is about populating the existing seed, not building CRUD for document templates.
