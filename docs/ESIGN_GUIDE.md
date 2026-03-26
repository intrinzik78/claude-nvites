# ESIGN Compliance Guide

> Canonical reference for how UWZ complies with the Electronic Signatures in Global and National Commerce Act (15 U.S.C. §§ 7001-7006). This document is the authority on what ESIGN requires, how we meet each requirement, and what is operational practice vs. legal obligation.
>
> **Audience:** Agents and developers working on waiver-related code across server, surfaces, and SDKs.
>
> **Last audited:** 2026-03-15

---

## What ESIGN actually requires

ESIGN gives electronic signatures and electronic records the same legal weight as handwritten signatures and paper records — provided certain consumer protections are met. For UWZ's recreational liability waivers, the relevant requirements are:

### 1. Intent to sign — §7001(a)

The signer must demonstrate intent to sign. For typed-name signatures on a web form, the act of typing their name into a designated signature field on a page displaying the waiver document satisfies this. No additional proof of intent (scroll tracking, time-on-page, browser fingerprinting) is required or desirable.

### 2. Consumer consent — §7001(c)(1)

Before providing an electronic record to a consumer, the business must:

**(A)** Provide a clear statement informing the consumer of:
- (i) The right to receive a paper copy
- (ii) The right to withdraw consent (by not submitting)
- (iii) Whether consent applies to this transaction only
- (iv) Procedures for withdrawing consent
- (v) How to obtain a paper copy after consent

**(B)** Obtain affirmative consent that has not been withdrawn.

**(C)(ii)** Consent must be given "in a manner that reasonably demonstrates that the consumer can access information in the electronic form that will be used." Interacting with the web form is the demonstration.

### 3. Record integrity — §7001(d)

The electronic record must be accurately retained and reproducible. If a record's integrity cannot be verified, it may not be enforceable.

### 4. Record access — §7001(c)(1)(A)(v)

The consumer must be able to obtain a copy of their signed record after consent.

### 5. Record retention — §7001(d)

Electronic records must be retained in a form that accurately reproduces the original.

---

## What ESIGN does NOT require

These are common misconceptions. Agents should not frame operational practices as ESIGN obligations:

- **View audit logging.** ESIGN does not require proof that a consumer viewed their signed record on any particular date. Recording view events is operational best practice for dispute support — not a compliance requirement. A failed view audit INSERT is not a compliance gap.

- **Scroll tracking or time-on-page metrics.** Courts do not require proving how long someone looked at a document for recreational liability waivers.

- **Browser fingerprinting.** Privacy-invasive, legally questionable, adds complexity with no legal benefit. IP + user agent + authenticated session is sufficient.

- **Audit trail retrieval by the signer.** Signers need access to their signed record (§7001(c)(1)(A)(v)). They do not need access to the full audit trail (IPs, user agents, staff actions). The audit trail is an internal operational tool for dispute resolution.

---

## How we comply

Each ESIGN requirement maps to specific code. The signing flow uses four discrete endpoints, each capturing its own timestamp, IP address, and user agent.

### Discrete signing flow

```
POST /v1/portal/waivers/begin       → Draft waiver created (status=Draft)
POST /v1/portal/waivers/{uuid}/consent  → ESIGN consent recorded
POST /v1/portal/waivers/{uuid}/confirm  → Detail confirmation recorded
POST /v1/portal/waivers/{uuid}/sign     → Signature applied (status → Pending)
```

Each step enforces a state machine: begin must precede consent, consent must precede confirm, both consent and confirm must precede sign. The server verifies predecessor audit events exist inside a `FOR UPDATE` transaction — no step can be skipped.

### §7001(a) — Intent to sign

| What | Where |
|------|-------|
| Signer types their name into a signature field on a page displaying the waiver | Surface responsibility (see `archive/dispatches/DISPATCH_ESIGN_WAIVER_DISCRETE.md`) |
| Pre-sign document retrieval: `GET /v1/waivers/document/current` resolves active document UUID, `GET /v1/waivers/document/{uuid}` returns document content with integrity verification | `waiver_document_current_get.rs`, `waiver_document_get.rs` (public, no auth) |
| `signature_data` captured and stored on `waiver` row at sign step | `server/api/src/types/waivers/waiver.rs` — `sign_tx()` |
| `waiver_audit_sign` row records the signing event with IP/UA/explicit Rust-side timestamp | `sign_tx()` audit insertion |
| Signature format: typed name for v1 | DEC-085 |

### §7001(c) — Consumer consent

| What | Where |
|------|-------|
| ESIGN disclosure block displayed before consent | Surface responsibility (`archive/dispatches/DISPATCH_ESIGN_WAIVER_DISCRETE.md` §Step 2) |
| Consent recorded as a discrete step with its own timestamp + IP | `POST /v1/portal/waivers/{uuid}/consent` → `consent_tx()` |
| `waiver_audit_consent` row created with distinct timestamp from begin and sign | `consent_tx()` audit insertion |
| State machine: `sign_tx()` verifies `waiver_audit_consent` exists before accepting signature | `sign_tx()` prerequisite check |
| Consent is idempotent — duplicate calls return 200 without creating extra audit rows | `consent_tx()` SELECT-before-INSERT |

### §7001(c)(1)(A)(v) — Record access

| What | Where |
|------|-------|
| `GET /v1/portal/waivers/{uuid}` returns the complete signed record | `server/api/src/api/portal/portal_waiver_record_get.rs` |
| Returns `SignedWaiverRecordDto`: waiver metadata + document body/signature/footer + `signed_document_hash` | `api-contracts/src/waivers.rs` |
| Post-sign integrity verification: `verify_signed_document()` recomputes the signed hash on every retrieval and rejects tampered records | `waiver.rs` — `verify_signed_document()`, called from handler |
| UUID indirection prevents enumeration (DEC-128) | `server/migrations/20260314100000_waiver_uuid.sql` |
| Ownership verified: signer_user_id must match authenticated user | Handler ownership check |
| 404 for both not-found and not-owned (prevents existence oracle) | Handler not-found + ownership branches |

### §7001(d) — Record integrity

Two hashes protect integrity at different levels:

**Content hash** (`document.content_hash`) — proves the document template is unmodified:

| What | Where |
|------|-------|
| SHA-256 of document components (body + `\n` + signature + `\n` + footer) | `compute_document_hash()` in `waiver.rs` |
| Captured at begin: stored as `content_hash_at_begin` on the waiver row | `begin_tx()` |
| Re-verified at sign: recomputed from document components, compared to `content_hash_at_begin` | `sign_tx()` — detects document mutation between begin and sign |
| Validated at public retrieval: `fetch_document_by_uuid()` recomputes and verifies before serving | `waiver.rs` — public document endpoint |
| Mismatch rejects with `WaiverDocumentIntegrityFailed` (409, code 4013) | `server/api/src/enums/error.rs` |

**Signed document hash** (`waiver.signed_document_hash`) — binds the signature to the signing context:

| What | Where |
|------|-------|
| SHA-256 of (content_hash + `\n` + signature_data + `\n` + ip_address + `\n` + unix_timestamp) | `compute_signed_document_hash()` in `waiver.rs` |
| Timestamp is explicit `Utc::now()` in Rust, not MySQL DEFAULT (prevents non-determinism) | `sign_tx()` |
| Same timestamp bound to both `waiver_audit_sign` INSERT and hash computation | `sign_tx()` |
| Verified on portal record retrieval: `verify_signed_document()` recomputes from components + audit trail | `portal_waiver_record_get.rs` |
| `signed_document_hash CHAR(64)` stored on waiver row | `server/migrations/20260313200000_esign_enforcement.sql` |
| Document component FKs are RESTRICT (prevent deletion, but not UPDATE) | `document` table DDL |

**Cross-cutting contract:** Any code that populates `document.content_hash` (e.g., a future template editor) MUST use the same hash scheme: `sha256(body_json + 0x0A + signature_json + 0x0A + footer_json)`. A mismatch causes all subsequent sign attempts against that template to fail.

### §7001(d) — Record retention

| What | Where |
|------|-------|
| Signed waiver rows (Pending/Accepted) are never deleted | No DELETE endpoints exist for non-draft waivers |
| Draft waivers are ephemeral — deleted by sweeper after 24h expiry | `DraftWaiverSweeper` in `draft_sweeper.rs` |
| Document components retained via RESTRICT FKs | `document` table DDL |
| `signed_document_hash` proves what was signed even if components were later UPDATE'd | `waiver.signed_document_hash` column |

---

## Operational practices (not ESIGN-mandated)

These strengthen our legal position but are not required by ESIGN. A failure in any of these is NOT a compliance gap.

### Detail confirmation

| What | Where | Why it exists |
|------|-------|---------------|
| Discrete confirm step: `POST /v1/portal/waivers/{uuid}/confirm` | `confirm_tx()` in `waiver.rs` | Defends against "that's not my name" challenges |
| Server enforces ordering: `sign_tx()` verifies `waiver_audit_confirm` exists | `sign_tx()` prerequisite check | Ensures surface implements a confirmation step |
| `waiver_audit_confirm` row records the event with its own timestamp + IP | `confirm_tx()` audit insertion | Timestamped proof of detail review, distinct from sign timestamp |

### View audit logging

| What | Where | Why it exists |
|------|-------|---------------|
| `waiver_audit_view` inserted at begin time | `begin_tx()` | Records "signer was on the page displaying the document" |
| `record_view_audit()` called on signed record retrieval | `portal_waiver_record_get.rs` | Records "signed record was delivered to signer" |
| Retrieval-time audit is best-effort (logged, does not block delivery) | Handler audit block | Never deny record access because an audit INSERT failed |

### Staff acceptance attribution

| What | Where | Why it exists |
|------|-------|---------------|
| `accepted_by_user_id` on `waiver_audit_accept` | `create_accept_audit_tx()` | Proves which staff member reviewed and accepted |
| Staff IP + user agent recorded at acceptance time | Same function | Chain of custody for dispute resolution |

### Audit trail retrieval

| What | Where | Why it exists |
|------|-------|---------------|
| `GET /v1/bookings/{uuid}/waivers/{waiver_id}/audit` | `booking_waivers_audit_get.rs` | Staff can view chronological event chain for disputes |
| UNION ALL across 7 subtables, ordered by timestamp | `fetch_audit_trail()` in `waiver.rs` | Single query returns full event history |
| Staff role (SysMod) required | Handler auth check | Signers don't see staff IPs/UAs |

---

## Audit event chain

A correctly signed waiver (new discrete flow) produces this event sequence:

```
create     → Waiver draft created in system (begin step)
view       → [begin-time] Signer was on the document page (begin step)
consent    → Signer gave ESIGN consent (consent step — distinct timestamp)
confirm    → Signer confirmed entered details (confirm step — distinct timestamp)
sign       → Signature applied (sign step — distinct timestamp)
view       → [retrieval-time] Signed record delivered to signer (portal retrieval)
accept     → Staff reviewed and accepted (staff_user_id recorded)
```

Historical waivers (pre-refactor batch flow) may also have `confirm_success` events. The `fetch_audit_trail()` query includes `confirm_success` in its UNION ALL to preserve historical completeness.

Events are stored in 7 subtables under a parent `waiver_audit` row. Each subtable records `ip_address` and `timestamp`. The parent records `user_agent`. `waiver_audit_accept` additionally records `accepted_by_user_id`.

---

## Security conventions

### DEC-128 — Consumer paths use UUID, staff paths use ID

Consumer-facing API paths (`/v1/portal/...`) use non-guessable UUID path parameters. Staff-gated paths (`/v1/bookings/...`) may use integer IDs. Sequential IDs on consumer paths create:
- **Existence oracles** — 404 vs. 403 leaks whether a record exists
- **Write amplification** — endpoints that insert audit rows on GET can be enumerated

`WaiverDto` exposes `uuid` only. Staff endpoints use `StaffWaiverDto` which includes `id`.

### DEC-050 — Bearer tokens never reach client JS

Auth tokens are never exposed to client-side JavaScript. Web surfaces use SSR-only load functions (`+page.server.ts`). Desktop surfaces use secure storage + IPC.

---

## Known limitations

1. **Document component UPDATE protection.** RESTRICT FKs prevent DELETE of document components but not UPDATE. If a component row is UPDATE'd in place, the document content changes silently. Mitigation: `verify_signed_document()` runs on every portal record retrieval and recomputes both the content hash and signed document hash — a tampered component causes the endpoint to return 500 instead of silently serving altered content. The public `GET /v1/waivers/document/{uuid}` endpoint also verifies the content hash before serving. A denormalized content snapshot would guarantee exact retrieval but adds storage overhead.

2. **Paper waiver audit is minimal.** Paper waivers created via `POST /v1/bookings/{uuid}/waivers/paper` get `waiver_audit_create` only (staff context). No consent, confirmation, or sign events — the paper itself is the legal artifact.

---

## Reference files

| File | Purpose |
|------|---------|
| `docs/waiver-esign-map.json` | Machine-readable table/column map with ESIGN section references |
| `docs/archive/dispatches/DISPATCH_ESIGN_WAIVER_DISCRETE.md` | Surface-website implementation requirements (4-step discrete flow) |
| `server/migrations/20260313200000_esign_enforcement.sql` | Phase 1 migration (hash, staff attribution) |
| `server/migrations/20260314100000_waiver_uuid.sql` | Phase 2 migration (UUID column) |
| `server/migrations/20260314300000_document_retrieval.sql` | Phase 3 migration (document UUID, document_status, public retrieval) |
| `server/migrations/20260315120000_waiver_audit_rebase.sql` | Discrete flow migration (status rebase, address/emergency contact columns) |

## Relevant decisions

| DEC | Summary |
|-----|---------|
| DEC-050 | Bearer tokens never reach client JS |
| DEC-085 | Typed-name signature format for v1 |
| DEC-128 | Consumer-facing paths use UUID, staff paths use ID |
