# DISPATCH: ESIGN Act — Discrete Waiver Signing Flow

**Date:** 2026-03-15
**Target:** surface-website
**Supersedes:** `archive/DISPATCH_ESIGN_WAIVER.md`, `archive/DISPATCH_ESIGN_SERVER_PHASE2.md`

---

## What changed on the server

The server replaced the single-shot `POST /v1/portal/waivers` with a 4-step discrete flow. Each step is its own endpoint with its own timestamp, IP, and user-agent capture. The old `POST /v1/portal/waivers/child` is also removed (child flow deferred).

### New endpoints

| Step | Endpoint | Returns |
|------|----------|---------|
| 1. Begin | `POST /v1/portal/waivers/begin` | 201 + `WaiverDto` (draft) |
| 2. Consent | `POST /v1/portal/waivers/{uuid}/consent` | 200 (empty) |
| 3. Confirm | `POST /v1/portal/waivers/{uuid}/confirm` | 200 (empty) |
| 4. Sign | `POST /v1/portal/waivers/{uuid}/sign` | 200 + `WaiverDto` (signed) |

All endpoints require portal auth (authenticated user, `Role::User`).

### Removed endpoints

- `POST /v1/portal/waivers` (single-shot adult create)
- `POST /v1/portal/waivers/child` (single-shot child create)

### Removed DTOs

- `CreateWaiverBody` / `CreateChildWaiverBody` — replaced by `BeginWaiverBody` + `SignWaiverBody`

### Removed error codes

- `WaiverConsentNotGiven` (4012) — consent is now a discrete step, not a boolean field
- `WaiverDetailsNotConfirmed` (4014) — same

### New error codes

| Code | Variant | HTTP | Meaning |
|------|---------|------|---------|
| 4016 | `WaiverNotDraft` | 409 | Waiver is not in Draft state |
| 4017 | `WaiverAuditPrerequisiteMissing` | 422 | Required preceding step not completed |
| 4018 | `WaiverExpired` | 410 | Draft waiver expired (24h TTL) |
| 4019 | `WaiverAddressInvalid` | 422 | Address field validation failed |
| 4020 | `WaiverEmergencyContactInvalid` | 422 | Emergency contact validation failed |

### State machine

The server enforces strict ordering: begin -> consent -> confirm -> sign. Each step checks that the preceding audit event exists. Calling `/sign` without `/consent` returns 422 (code 4017). Each step also verifies the waiver is still in Draft status and has not expired.

Consent and confirm are **idempotent** — calling them twice returns 200 without creating duplicate audit rows.

Draft waivers expire after 24 hours. A background sweeper deletes expired drafts every 5 minutes.

---

## What the surface MUST implement

### Step 1: Begin (`POST /v1/portal/waivers/begin`)

Request body (`BeginWaiverBody`):
```json
{
  "document_uuid": "wvrD0c00000001X",
  "participant_name": "John Doe",
  "participant_dob": "1990-05-15",
  "address_street": "123 Main St",
  "address_city": "Springfield",
  "address_state": "IL",
  "address_zip": "62704",
  "emergency_contact_name": "Jane Doe",
  "emergency_contact_phone": "555-1234",
  "emergency_contact_relationship": "spouse"
}
```

The surface must:
1. Fetch the active document via `GET /v1/waivers/document/current` (public, no auth)
2. Display the waiver document above the form
3. Collect participant info, address, and emergency contact
4. Submit to `/begin` — returns a draft `WaiverDto` with a `uuid` for subsequent steps

The `document_uuid` comes from the document retrieval response.

### Step 2: Consent (`POST /v1/portal/waivers/{uuid}/consent`)

No request body. The `{uuid}` is the draft waiver UUID from step 1.

The surface must:
1. Display the ESIGN disclosure block (see below)
2. Require a consent checkbox (unchecked by default)
3. On check, call `/consent`

### Step 3: Confirm (`POST /v1/portal/waivers/{uuid}/confirm`)

No request body.

The surface must:
1. Present a confirmation summary: "Please confirm the following details are correct: [name, DOB, address, emergency contact]"
2. Require explicit confirmation (button or checkbox)
3. On confirm, call `/confirm`

### Step 4: Sign (`POST /v1/portal/waivers/{uuid}/sign`)

Request body (`SignWaiverBody`):
```json
{
  "signature_data": "John Doe"
}
```

The surface must:
1. Present the signature field (typed name for v1, per DEC-085)
2. On submit, call `/sign` — returns the signed `WaiverDto`
3. Show confirmation + link to signed record at `/portal/waivers/{uuid}`

The server sends a confirmation email to the signer after successful signing.

### ESIGN disclosure block (§7001(c))

Display before the consent checkbox:

> You are signing this waiver electronically. You have the right to request a paper copy by contacting Urban Warzone Paintball. You can withdraw consent by not submitting the form. The electronic record will be retained and accessible to you through your account.

### Error handling

| Error Code | Surface Action |
|------------|---------------|
| 4013 (`WaiverDocumentIntegrityFailed`) | "The waiver document has been updated. Please refresh and start over." |
| 4016 (`WaiverNotDraft`) | "This waiver has already been completed." |
| 4017 (`WaiverAuditPrerequisiteMissing`) | "Please complete the previous step first." |
| 4018 (`WaiverExpired`) | "This waiver session has expired. Please start a new waiver." |
| 4019 / 4020 | Show field-level validation error |

---

## What the surface SHOULD NOT do

- **Do not add scroll-tracking or time-on-page metrics.** See `docs/ESIGN_GUIDE.md` — not required by ESIGN.
- **Do not add browser fingerprinting.** IP + user agent + authenticated session is sufficient.
- **Do not implement the child waiver flow.** Deferred to a follow-on phase. The `POST /v1/portal/waivers/child` endpoint no longer exists.

## Existing endpoints (unchanged)

These are already implemented and require no surface changes:

- `GET /v1/portal/waivers` — list signer's waivers
- `GET /v1/portal/waivers/{uuid}` — view signed waiver record (§7001(c)(1)(A)(v) record access)
- `POST /v1/portal/waivers/attach` — attach waivers to a booking
- `GET /v1/waivers/document/current` — resolve active document UUID (public, no auth)
- `GET /v1/waivers/document/{uuid}` — fetch document content with integrity verification (public)

## Reference

- `docs/ESIGN_GUIDE.md` — compliance authority
- `docs/waiver-esign-map.json` — machine-readable table/column map
- DEC-085 (signature format): typed name for v1
- DEC-050 (bearer tokens): tokens never reach client JS — auth via SSR-only loads
- DEC-128 (UUID convention): consumer paths use UUID, staff paths use ID
