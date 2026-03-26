# DISPATCH: ESIGN Act — Server Phase 2 (Record Access + Audit Retrieval)

## What was completed (Phase 1)

Phase 1 enforced ESIGN compliance at the write boundary:

- `consent_given: bool` required on `CreateWaiverBody` / `CreateChildWaiverBody` — server
  rejects if false (§7001(c) affirmative consent)
- `signed_document_hash` (SHA-256) computed at sign time, validated against
  `document.content_hash`, stored on the waiver row (§7001(d) integrity)
- Audit subtable insertion at creation reduced to 4 rows (create, view, consent, sign) —
  accept moved to staff acceptance time; confirm/confirm_success deferred (see Gap 3)
- `waiver_audit_accept` now created at staff acceptance time with `accepted_by_user_id`,
  staff IP, and staff user-agent (attribution)
- Paper waivers now have `waiver_audit` + `waiver_audit_create` rows (staff context)
- Migration: `signed_document_hash CHAR(64)` on `waiver`, `accepted_by_user_id INT` on
  `waiver_audit_accept`
- Error variants: `WaiverConsentNotGiven` (4012, 422), `WaiverDocumentIntegrityFailed`
  (4013, 409)
- Hash delimiter fix: newline separators between body/signature/footer components to
  prevent boundary collisions

**All Phase 1 changes are complete, tested (319 server + 107 contract tests pass), and
built through `cargo xtask build-all`.**

## What's missing (Phase 2)

### Gap 1: Post-signing record access

**Problem:**
§7001(c)(1)(A)(v) requires the consumer be informed "how the consumer may obtain a paper
copy of the electronic record after consent." This implies the consumer must also be able
to access the electronic copy. Currently:

- `find_by_signer` returns `WaiverDto` (metadata including `signed_document_hash`) but
  **not** the actual document content they signed
- No endpoint returns a complete signed waiver record (waiver metadata + the document
  body/signature/footer that was presented at sign time)
- The `waiver_audit_view` row created at sign time records "they were on the page when
  they submitted" — not "they received their signed record back from the server"

**ESIGN progression should be:**
1. Consent → 2. Document presented → 3. Sign → 4. Server returns signed record →
5. `waiver_audit_view` records delivery of the signed record

We are currently collapsing steps 4 and 5 into step 3.

**Proposed solution:**

New endpoint: `GET /v1/portal/waivers/{id}`

- Auth: authenticated user, must be the signer (`signer_user_id` check)
- Returns: `SignedWaiverRecordDto` containing:
  - All `WaiverDto` fields
  - `document_body: serde_json::Value` — the body JSON from `document_body` table
  - `document_signature: serde_json::Value` — the signature config
  - `document_footer: serde_json::Value` — the disclaimer
  - `signed_document_hash: String` — integrity proof
- On successful retrieval, update `waiver_audit_view` timestamp to reflect actual
  record delivery (or create a new audit event if we want to distinguish "viewed during
  signing" from "retrieved signed copy")

**Confidence: HIGH** — this is a clear gap. The ESIGN Act requires the consumer be able
to access their record. Without this endpoint, the surface-website cannot show users
their signed waivers, and we cannot prove record delivery.

**Contract change:** Yes — new `SignedWaiverRecordDto` in `api-contracts/src/waivers.rs`.

**Considerations:**
- The document content is fetched via `document_id` FK on the waiver. Since document
  component FKs are RESTRICT (immutable), the content should be stable. But if component
  rows were UPDATE'd in place, the content may differ from what was signed. The
  `signed_document_hash` on the waiver proves what was signed — the endpoint should
  return both the current content AND the hash so the surface can verify/display
  accordingly.
- Alternative: store a snapshot of the document content at sign time (denormalized).
  This guarantees the exact content is always retrievable but adds storage overhead.
  For v1, relying on the hash + immutable FK constraints is sufficient. If document
  component UPDATE protection becomes a concern, a snapshot migration can be added later.

### Gap 2: Audit trail retrieval

**Problem:**
The 7 audit subtables are write-only. No API endpoint exists to read them. Staff cannot:
- See when a waiver was created, viewed, consented, signed
- See who accepted a waiver (even though `accepted_by_user_id` is now recorded)
- See IP addresses or user agents for any event
- Verify the audit chain for a disputed waiver

**Proposed solution:**

New endpoint: `GET /v1/bookings/{uuid}/waivers/{waiver_id}/audit`

- Auth: staff role (SysMod or higher)
- Returns: `WaiverAuditTrailDto` containing:
  - `waiver_id: i32`
  - `events: Vec<WaiverAuditEventDto>`
- Each `WaiverAuditEventDto`:
  - `event_type: String` — "create", "view", "consent", "sign", "accept"
  - `timestamp: DateTime<Utc>`
  - `ip_address: String`
  - `user_agent: Option<String>` (from parent `waiver_audit` row)
  - `accepted_by_user_id: Option<i32>` (only for "accept" events)

**Implementation:** Single SQL query joining `waiver_audit` with all subtables via
LEFT JOINs, or multiple targeted queries per subtable. The LEFT JOIN approach is simpler
(one round trip) but produces wide rows with many NULLs. Per-subtable queries are cleaner
but require 6+ queries.

**Recommended approach:** One query per audit parent, then fetch populated subtables
only. Since audit rows are small and per-waiver (not bulk), N+1 is not a concern here.

**Confidence: HIGH** — write-only audit data defeats the purpose of having an audit
trail. Staff must be able to retrieve it for dispute resolution. This is a core
operational need, not just a compliance checkbox.

**Contract change:** Yes — new `WaiverAuditTrailDto` and `WaiverAuditEventDto` in
`api-contracts/src/waivers.rs`.

**Considerations:**
- The audit trail endpoint should be staff-only. Signers should not see IP addresses
  or user agents of staff members.
- For the portal (signer-facing), the signed waiver record endpoint (Gap 1) is
  sufficient — they don't need the full audit trail, just their signed document.

### Gap 3: Confirm / confirm-success flow (detail verification step)

**Problem:**
The `waiver_audit_confirm` and `waiver_audit_confirm_success` tables were designed for a
real ESIGN flow step: the signer reviews their entered details (name, DOB, guardian
relationship) and explicitly confirms they are correct before the signature is applied.
Phase 1 stopped inserting phantom rows into these tables at creation time, but the
underlying flow they represent is a genuine service gap — not dead schema.

The ESIGN progression with confirmation:
1. Consent → 2. Document presented → 3. Enter details → **4. Confirm details are correct**
→ **5. Confirm success** → 6. Sign → 7. Server returns signed record

Without steps 4–5, there's no proof the signer reviewed their entered information before
signing. A challenge like "that's not my name, someone else filled in the form" has
weaker defense.

**Proposed solution:**

This is a two-sided change (server + surface):

**Server side:**
- Add `details_confirmed: bool` to `CreateWaiverBody` / `CreateChildWaiverBody`
  (or make confirmation a separate API call — see considerations)
- Server rejects if `details_confirmed != true`
- Insert `waiver_audit_confirm` row when details are confirmed
- Insert `waiver_audit_confirm_success` row when the waiver is successfully created
  after confirmation

**Surface side:**
- After the signer enters their details but before they sign, present a confirmation
  summary: "Please confirm the following details are correct: [name, DOB, etc.]"
- Required checkbox or "Confirm" button
- Only then reveal/enable the signature field

**Confidence: MEDIUM** — the tables exist because the flow was designed intentionally.
The legal benefit for a recreational paintball waiver is moderate (courts are lenient on
detail confirmation for low-stakes liability waivers), but having the infrastructure
already in the schema means the implementation cost is low. Worth doing.

**Considerations:**
- **Single request vs. multi-step:** Adding `details_confirmed: bool` to the existing
  create request body is simpler but conflates confirmation with signing into one HTTP
  call. A separate `POST /v1/portal/waivers/confirm` that returns a confirmation token
  (then passed to the create endpoint) would create a genuine two-step flow with distinct
  timestamps. The separate-call approach produces better audit evidence but adds UI
  complexity.
- **Recommendation:** Start with `details_confirmed: bool` on the existing request body
  (matches the `consent_given` pattern). If legal counsel requires distinct timestamps
  for confirm vs. sign, refactor to the two-step flow later. The audit tables support
  either approach.

### Gap 4: `waiver_audit_view` semantics

**Problem:**
The `waiver_audit_view` row is currently created at waiver creation time in `create_tx`.
It records "the signer was on the page that displayed the document when they submitted."
But in the ESIGN progression, "view" should mean "the signed record was delivered back to
the signer" — proof of record receipt, not just document presentation.

Phase 1 kept it at creation time because removing it entirely would leave zero evidence
of document presentation. But this means the view audit row is doing double duty:
it's evidence of both "document was presented" and "record was received."

**Proposed solution:**
When Gap 1 (record access endpoint) is implemented, the `waiver_audit_view` insertion
should move there — recording the moment the signer actually retrieves their signed
record. The creation-time evidence of document presentation is already covered by the
fact that the signer submitted the form (they were viewing the document to fill it out).

Alternatively, keep the creation-time view row as "document presented" and create a
second `waiver_audit_view` row when the signed record is retrieved, giving two distinct
view events with different timestamps. This preserves both pieces of evidence.

**Confidence: MEDIUM** — the current state is defensible ("they submitted from the page
displaying the document"), but the proper fix comes with Gap 1's endpoint.

**Both dispatch docs (this one and `DISPATCH_ESIGN_WAIVER.md`) reference this
semantics issue.** The surface-website dispatch tells implementers not to add a separate
view API call and explains why — the server records view at creation time for now.

## Files modified in Phase 1 (for reference)

| File | Change |
|------|--------|
| `api-contracts/src/waivers.rs` | `consent_given` on request bodies, `signed_document_hash` on `WaiverDto` |
| `server/api/src/enums/error.rs` | `WaiverConsentNotGiven`, `WaiverDocumentIntegrityFailed`, count bump to 98 |
| `server/api/src/types/waivers/waiver.rs` | Domain type + helpers + `create_tx` rewrite + `create_paper_tx` audit + `create_accept_audit_tx` + hash computation |
| `server/api/src/api/waivers/booking_waivers_accept_post.rs` | `AuthContext` + IP/UA extraction + accept audit call |
| `server/api/src/api/waivers/booking_waivers_paper_post.rs` | IP/UA extraction, pass to `create_paper_tx` |
| `server/api/src/api/portal/portal_waivers_post.rs` | Pass `consent_given` through |
| `server/api/src/api/portal/portal_waivers_child_post.rs` | Pass `consent_given` through |
| `server/api/Cargo.toml` | Added `sha2 = "0.10"` |
| `server/migrations/20260313200000_esign_enforcement.sql` | `signed_document_hash` + `accepted_by_user_id` columns |

## Artifacts produced

- `docs/waiver-esign-map.json` — table relationship map with ESIGN roles
- `docs/DISPATCH_ESIGN_WAIVER.md` — surface-website dispatch (consent UI requirements)
- `docs/DISPATCH_ESIGN_SERVER_PHASE2.md` — this document

## Priority recommendation

1. **Gap 1 (record access)** — legal requirement. Without it, we cannot prove the
   consumer received their signed record. Blocks surface-website waiver completion flow.
2. **Gap 3 (confirm/confirm_success)** — strengthens the signing flow. Low cost since
   tables already exist. Can ship with Gap 1 as a single phase.
3. **Gap 4 (view semantics)** — resolves with Gap 1. The retrieval endpoint is the
   natural place to record the proper view event.
4. **Gap 2 (audit retrieval)** — operational. Staff need it for dispute resolution, but
   audit data is being recorded correctly and can be queried directly from the database
   in the interim.
