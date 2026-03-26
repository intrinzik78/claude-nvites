# DISPATCH: Waiver Document Display, Content, and Post-Signing Email

**Date:** 2026-03-14
**Target:** server branch
**Supersedes:** `archive/DISPATCH_WAIVER_CONTENT_EMAIL.md` (items carried forward)

---

## 1. Document retrieval endpoint for signing page (CONTRACT CHANGE)

**Problem:** The waiver signing form requires the signer to sign "on a page displaying the waiver document" (ESIGN §7001(a), `docs/ESIGN_GUIDE.md`). No endpoint exists to fetch the document template before signing. The form hardcodes `document_id: 1` but never retrieves or displays the content. The `waiver_audit_view` event claims "signer was on the page displaying the document" — but the page doesn't display the document.

**Action:** Add a public or portal endpoint that returns the document template for display:

```
GET /v1/portal/waivers/document/{document_id}
```

Returns `DocumentDto` (body, signature, footer, content_hash). Auth required (portal scope) but no ownership check — the document template is not user-specific.

Alternatively, a simpler approach: a public endpoint (no auth) since the waiver template is not confidential — it's the same document shown to every signer. This would let the public `/waiver?code=...` route display the document before the user logs in.

**Surface impact:** The signing page (`WaiverSignForm.svelte` or its parent) will load and display the document body above the form fields. The signer reads the waiver, then fills in the form below it.

**This is a contract change** — new path in `api-contracts/src/paths/`, new handler, `DocumentDto` already exists in the contract.

## 2. Populate waiver document with real content

The seed document (`20260225100000_waiver_document_seed.sql`) has placeholder JSON:

```json
{"title":"Waiver of Liability","sections":[]}
```

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

The `DocumentDto` fields are `serde_json::Value` — the JSON shape is a runtime convention, not a compiled contract. When a template editor ships, the contract should tighten `body`/`signature`/`footer` to proper structs.

**Signature and footer** can stay as-is or be updated to match:
- signature: `{"type": "typed", "label": "Type your full legal name"}`
- footer: `{"text": "By signing this document you acknowledge..."}`

## 3. Post-signing confirmation email with link to signed record

After a waiver is successfully created (`POST /v1/portal/waivers` and `/child`), the server should send a confirmation email to the signer containing:

- Confirmation that the waiver was signed electronically
- Participant name and signing timestamp
- A link to view the signed record: `{PUBLIC_HOSTNAME}/portal/waivers/{uuid}`

The `uuid` field is available on the `WaiverDto` returned by the creation handler. The signer's email is available from the authenticated session (`AuthContext`).

**Scope boundary:** This dispatch covers the email trigger and template. The surface already handles the detail page at `/portal/waivers/{uuid}`.

## Sequencing

Item 1 (endpoint) unblocks the surface from displaying the document on the signing page. Item 2 (content) makes that display meaningful. Item 3 (email) is independent and can ship in any order.

The surface will build the document display component as soon as the endpoint is available. Until then, the signing form works but does not display the waiver text.

## What NOT to do

- **Do not tighten `DocumentDto` types yet.** That's a contract change for the template editor, not for document retrieval.
- **Do not add a template editor.** This dispatch is about retrieval and seed content, not CRUD.
- **Do not add scroll tracking or view-time metrics.** ESIGN does not require them (see `docs/ESIGN_GUIDE.md` § "What ESIGN does NOT require").
