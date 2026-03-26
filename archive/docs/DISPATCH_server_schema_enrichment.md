# Dispatch: Enrich api-contracts with utoipa schema validation attributes

**Date:** 2026-03-17
**From:** surface-website
**To:** server

## Context

A full audit of every form on surface-website (booking, waiver, auth, queue, profile) revealed that validation is ad-hoc, duplicated, and disconnected from the API contract. The root cause is that `api-contracts` request body structs carry field constraints only as doc comments — utoipa's schema attributes (`min_length`, `max_length`, `minimum`, `maximum`, `format`) are unused. As a result:

1. **OpenAPI spec** — `guest_name` is `{ "type": "string" }` with a description that says "1–200 characters". No `minLength`/`maxLength` keywords. Every request body has this problem.
2. **SDK types** — `openapi-typescript` generates `guest_name: string`. No constraints survive into TypeScript. JSDoc comments preserve the prose but nothing enforces it.
3. **Surface forms** — each ViewModel hand-writes validation by reading doc comments and hoping it matches the server. Booking validates email format + guest count but not name/email/phone length. Waiver validates required fields but no format/length. Profile has zero client-side validation. Auth relies entirely on HTML `required`.
4. **Server handlers** — the real validation lives here, in constants like `MAX_GUEST_NAME_LEN = 200` and `MIN_GUEST_EMAIL_LEN = 5`. These are correct and comprehensive. But they're invisible to every consumer.

Payment workflows are next. We cannot build payment forms on this foundation — every constraint would be another hand-maintained copy with no contract enforcement.

## Prior dispatch (superseded)

The 2026-03-15 dispatch requesting a `UsState` enum for `address_state` is still valid and can be done as part of this work. It's the same category of problem: a string field that should be constrained at the contract level.

## Findings

### What the server already validates (handler code)

**Bookings** (`bookings_post.rs`):
- `guest_name`: 1–200 chars
- `guest_email`: 5–254 chars, `is_valid_email()` regex
- `guest_phone`: optional, max 30 chars
- `notes`: optional, max 2000 chars
- `guest_count`: within product's `min_guests..=max_guests`
- `start_at`: >= now + 60 minutes

**Waivers** (`waiver_validation.rs`):
- `participant_name`: 1–128 chars
- `address_street`: 1–256 chars
- `address_city`: 1–128 chars
- `address_state`: 1–64 chars (should become `UsState` enum per prior dispatch)
- `address_zip`: 1–16 chars
- `emergency_contact_name`: 1–128 chars
- `emergency_contact_phone`: 1–32 chars
- `emergency_contact_relationship`: 1–64 chars
- `signature_data`: 1–500,000 bytes, XSS-sanitized
- `participant_dob` (minor): age < 18

**Queue / Call Ahead** (`call_ahead_post.rs`):
- `name`: 1–128 chars
- `email`: 5–254 chars, `is_valid_email()`
- `party_size`: >= 1
- `notes`: optional, max 2000 chars

**Users** (`CreateUserBody`):
- `username`: 1–16 chars (doc comment only — handler validation not audited)

### What the OpenAPI spec currently encodes

Effectively nothing. The only numeric constraint found is `minimum: 0` on some `u16` fields (auto-derived by utoipa from the Rust type). No `minLength`, `maxLength`, `pattern`, `format`, or `example` attributes exist on any request body field across the entire spec.

### Current utoipa usage

- Version: **5.4.0** (supports all needed attributes)
- Existing `#[schema(...)]` usage: only `inline` and `value_type = Object` — zero validation attributes anywhere

### What the surface-website forms validate client-side

| Domain | Required fields | Email format | Length bounds | Format (phone/zip/date) |
|--------|----------------|-------------|-------------|------------------------|
| Booking | yes | regex | **no** | no |
| Waiver | yes | no | **no** | no |
| Auth (login) | HTML only | no | no | no |
| Auth (register) | yes | no | password >= 8 | no |
| Profile | **no** | n/a | no | no |
| Queue | HTML only | no | no | no |

### Unsafe patterns found in BFF layer

Waiver `begin/+server.ts` line 39:
```typescript
guardian_relationship: raw.guardian_relationship as 'parent' | 'legal_guardian',
```
Unvalidated user input cast directly to union type. Server catches it, but the BFF asserts type safety it doesn't have.

## Proposed Change

### Phase 1: Annotate api-contracts structs (server worktree)

Add utoipa `#[schema(...)]` attributes to every request body struct field that has a constraint. The doc comments already document the rules; the handler constants already define them. This phase makes them machine-readable.

Example for `CreateBookingBody`:
```rust
pub struct CreateBookingBody {
    pub product_id: i32,
    #[schema(min_length = 1, max_length = 200)]
    /// 1–200 characters.
    pub guest_name: String,
    #[schema(min_length = 5, max_length = 254, format = "email")]
    /// Valid email address, 5–254 characters.
    pub guest_email: String,
    #[schema(max_length = 30)]
    /// Optional. Max 30 characters.
    pub guest_phone: Option<String>,
    pub guest_count: u16,
    pub start_at: DateTime<Utc>,
    #[schema(max_length = 2000)]
    /// Optional. Max 2000 characters.
    pub notes: Option<String>,
}
```

Same treatment for: `BeginWaiverBody`, `BeginChildWaiverBody`, `SignWaiverBody`, `CallAheadBody`, `CreateQueueEntryBody`, `RegisterBody`, `CreateUserBody`, `CreateSessionBody`, `UpdatePortalProfileBody`, and any other request body struct with constrained fields.

**Confidence: high.** This is mechanical — the constants exist in handlers, the doc comments exist in structs, utoipa 5.4.0 supports the attributes. No behavioral change, no migration, just richer OpenAPI output.

### Phase 2: Include the UsState enum (server worktree, from prior dispatch)

Fold in the 2026-03-15 dispatch: add `UsState` enum to api-contracts, change `address_state: String` → `address_state: UsState` in waiver bodies. The surface-website `UsState` type and `FormSelect` are already in place.

**Confidence: high.** Same as prior dispatch — straightforward enum addition.

### Phase 3: Surface-website consumes enriched spec (surface-website worktree)

After `cargo xtask build-all` regenerates `dist/openapi.json` and `sdk-ts` types:

1. **Add a validation library** (Valibot or Zod — see open questions).
2. **Write schemas** derived from the OpenAPI spec's constraint keywords for the 4 active form domains (booking, waiver, queue, profile).
3. **Integrate schemas into ViewModels** — replace hand-written validation with schema-driven validation. Field errors still flow through `Record<string, string>` to FormField components.
4. **Add `maxlength` HTML attributes** to FormField/FormTextarea where the schema defines `maxLength` — defense in depth.
5. **Fix the `guardian_relationship` cast** — validate against the schema before passing to the API.

**Confidence: medium.** The pattern is sound but the codegen tooling (OpenAPI → Valibot) is less mature than OpenAPI → Zod. May need hand-written schemas initially, with codegen as a follow-up. Even hand-written schemas derived from one source (the enriched OpenAPI spec) are a massive improvement over the status quo.

### What this does NOT include

- No changes to server handler validation logic — it's already correct
- No `validator` crate adoption — utoipa attributes enrich the spec; server handlers continue to validate at runtime as they do today
- No changes to response/DTO schemas — this dispatch covers request bodies only
- No form UX redesign — validation integration uses existing FormField error display

## Impact

- **Contract change** — `api-contracts` types gain attributes, `dist/openapi.json` gains constraint keywords, `sdk-ts` generated types gain richer JSDoc. No breaking change to any consumer.
- **Build pipeline** — `cargo xtask build-all` propagates everything. No new build steps.
- **Existing tests** — no behavioral change; existing requests remain valid.

## Open Questions

1. **Should `format = "email"` go on email fields?** utoipa supports it, OpenAPI spec defines it, but `openapi-typescript` doesn't do anything special with `format`. It's documentation-only in the generated types. Worth adding for Swagger UI / external tooling consumers? I lean yes — it costs nothing and helps any tool that reads the spec.

2. **Should handler validation constants move to api-contracts?** Currently `MAX_GUEST_NAME_LEN = 200` lives in `bookings_post.rs` and the `#[schema(max_length = 200)]` would live in `api-contracts/src/bookings.rs`. Two sources for the same number. Options: (a) define constants in api-contracts, import in handlers — single source; (b) keep them separate, accept the duplication since it's small and stable. I lean (a) but it's a judgment call on api-contracts' scope.

3. **Valibot vs Zod?** Zod has better OpenAPI tooling (`zod-openapi`, `openapi-zod-schemas`). Valibot is smaller and more TypeScript-idiomatic. If codegen maturity matters more than bundle size, Zod may be the pragmatic choice. This decision lives in surface-website, not server — noting it here for context.

4. **Should `minimum: 1` go on `party_size` / `guest_count`?** The Rust type is `u16` (minimum 0 by nature), but the business rule is >= 1. utoipa will auto-derive `minimum: 0` from `u16`. Adding `#[schema(minimum = 1)]` overrides this to reflect the actual business constraint. I lean yes.

5. **Scope of "every request body"** — should this cover staff/admin endpoints too (e.g., `CreateResourceBody`, `UpdateProductBody`, `CreateWorkflowDefinitionBody`), or only customer-facing request bodies? Staff endpoints are lower risk (authenticated, smaller blast radius) but the same principle applies. I lean all, done incrementally — customer-facing first, staff endpoints in a follow-up.
