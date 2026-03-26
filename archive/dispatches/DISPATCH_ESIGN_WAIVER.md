# DISPATCH: ESIGN Act — Waiver Signing Surface

## What changed on the server

The server now enforces ESIGN Act compliance at the API boundary. These changes affect
how the waiver signing form must behave.

### 1. `consent_given: bool` is now REQUIRED

**Endpoints affected:**
- `POST /v1/portal/waivers` (CreateWaiverBody)
- `POST /v1/portal/waivers/child` (CreateChildWaiverBody)

The server will reject with `WaiverConsentNotGiven` (422, code 4012) if `consent_given` is not `true`.

### 2. Document integrity is validated

The server computes a SHA-256 hash of the document content at sign time and compares it
to the stored `content_hash`. If mismatched, the request fails with
`WaiverDocumentIntegrityFailed` (409, code 4013).

No surface action required — this is transparent. But if users see this error, it means
the document template was modified after the page loaded. The surface should handle this
gracefully (e.g., "The waiver has been updated. Please refresh and try again.").

## What the surface MUST implement

### ESIGN §7001(c) — Consumer consent to electronic records

Before the signer can submit, the surface must:

1. **Display the ESIGN disclosure** — a visible block of text informing the user:
   - They are signing this waiver electronically
   - They have the right to request a paper copy (contact info or link)
   - They can withdraw consent by not submitting the form
   - The electronic record will be retained and accessible to them

2. **Require affirmative consent** — a checkbox (unchecked by default) with text like:
   > "I consent to sign this waiver electronically. I understand I can request a paper
   > copy by contacting Urban Warzone Paintball."

3. **Gate the submit button** — the sign button must be disabled until the consent
   checkbox is checked. This prevents accidental submission without consent.

4. **Send `consent_given: true`** — when the checkbox is checked and the form is
   submitted, include `consent_given: true` in the request body.

### Why this matters (legal reasoning)

**15 U.S.C. §7001(c)(1)** requires that before an electronic record is provided to a
consumer, the consumer must:

> (A) be provided with a clear and conspicuous statement informing the consumer of—
>   (i) any right or option to have the record provided or made available on paper...
>   (ii) the right to withdraw consent...
>   (iii) whether the consent applies to this transaction only or to identified
>         categories of records...
>   (iv) the procedures for withdrawing consent and updating contact information...
>   (v) how the consumer may obtain a paper copy after consent...
>
> (B) affirmatively consent to such use and has not withdrawn such consent

The consent checkbox + disclosure block satisfies (A) and (B). The server's
`consent_given: bool` enforcement ensures the surface cannot skip this step.

**15 U.S.C. §7001(c)(1)(C)(ii)** additionally requires that consent be given:
> "in a manner that reasonably demonstrates that the consumer can access information
> in the electronic form that will be used"

The fact that the consumer is viewing and interacting with the web form IS the
demonstration — they are proving they can access electronic information by using the form.

### WaiverDocumentIntegrityFailed error handling

If the server returns `WaiverDocumentIntegrityFailed`, the surface should:
1. Show a user-friendly message: "The waiver document has been updated. Please refresh
   the page to view the latest version."
2. Disable the submit button
3. Optionally auto-refresh the document content

This error means the document template changed between when the page loaded and when
the user submitted. It's a race condition, not a user error.

## Scope boundary — STOP HERE

The work above (consent disclosure, checkbox, gated submit, `consent_given: true`,
`WaiverDocumentIntegrityFailed` error handling) is the complete scope for this dispatch.

**Do NOT implement the following — they depend on server Phase 2 work that has not
shipped yet:**

- Post-signing "view my signed waiver" page — requires `GET /v1/portal/waivers/{id}`
  (Phase 2 Gap 1, endpoint does not exist yet)
- Detail confirmation step before signing — requires `details_confirmed: bool` on the
  request body (Phase 2 Gap 3, not in the contract yet)
- Signed record receipt/delivery tracking — requires Phase 2 Gap 4

A separate dispatch will be issued when the Phase 2 server endpoints are ready.

## What the surface SHOULD NOT do

- **Do not add scroll-tracking or time-on-page metrics.** Courts do not require proving
  how long someone looked at a document for recreational liability waivers. The act of
  typing their name on a page displaying the document is sufficient evidence of viewing.

- **Do not add browser fingerprinting.** Privacy-invasive, legally questionable, adds
  complexity with minimal legal benefit. The server already captures IP + user agent +
  authenticated session.

- **Do not add a separate "view" API call yet.** The server records `waiver_audit_view`
  at creation time. The submission itself is proof of viewing. A future Phase 2 endpoint
  (`GET /v1/portal/waivers/{id}`) will return the signed record to the signer and
  properly record view/receipt at that point. See `docs/DISPATCH_ESIGN_SERVER_PHASE2.md`
  Gap 1 and Gap 4.

## Reference

- ESIGN Act full text: 15 U.S.C. §§ 7001-7006
- Server relationship map: `docs/waiver-esign-map.json`
- Server migration: `server/migrations/20260313200000_esign_enforcement.sql`
- DEC-085 (signature format): typed name for v1, legally standard for online waivers
- DEC-050 (bearer tokens): tokens never reach client JS — auth via SSR-only loads
