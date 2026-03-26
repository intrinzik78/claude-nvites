# Form & BFF Security Audit — surface-website

**Date:** 2026-03-17 (original), 2026-03-17 (verified & revised)
**Scope:** Every form on surface-website, BFF request flow, rate limiting posture, IP forwarding
**Trigger:** Pre-payment workflow readiness assessment
**Verification:** All claims independently verified against source code. Corrections applied below.

---

## Executive Summary

The form architecture is sound — ViewModel pattern, SSR-only data loading, shared form components with accessibility support. The server is the validation authority and enforces all constraints. Actix-web's 256KB payload limit and per-endpoint rate limiting provide defense against payload stuffing and spam.

Two issues require action before launch:

1. **The BFF does not forward client IP to the API server.** Rate limiting sees the SvelteKit server's IP, not the end user's — all website traffic shares one rate-limit bucket. ESIGN waiver audit logs capture the SvelteKit server's IP, not the signer's.

2. **`X-Forwarded-For` is spoofable.** Many hosting platforms do not strip client-supplied `X-Forwarded-For` values. The original rate limiter read `realip_remote_addr()` which prefers `X-Forwarded-For` — meaning any direct API client could spoof their IP. **Fixed:** server now reads Railway's `X-Real-IP` (DEC-141).

3. **Two mechanical code quality issues** — FormField component lacks `maxlength`/`minlength` props, and the waiver BFF has an unsafe `as` type assertion on unvalidated input.

Client-side validation is absent beyond HTML `required` attributes. This is a UX concern, not a security concern — the server validates everything. A validation library is deferred until payment forms are built.

---

## FINDING: Client IP Identification Is Broken

**Severity:** High — affects rate limiting effectiveness, ESIGN audit trail accuracy, and abuse resistance.

### Two problems, same root cause

**Problem 1 — BFF does not forward client IP:**
When a browser request reaches the SvelteKit server, SvelteKit's BFF handlers (`+server.ts`, `+page.server.ts`) make HTTP calls to the API server via the TypeScript SDK. The SDK (`sdk-ts/src/client.ts`) sets only `Authorization` and `Content-Type` headers — no IP-forwarding headers. The API server sees the SvelteKit deployment's IP for all website-originated requests.

**Problem 2 — `X-Forwarded-For` is spoofable:**
Many hosting platforms (including Render, the original host candidate) do not strip client-supplied `X-Forwarded-For` headers — they only append to them. A malicious client can prepend arbitrary IPs, and those values arrive at the application intact.

The server's rate limiter originally used `connection.realip_remote_addr()` which reads `X-Forwarded-For` first. This means:
- **BFF traffic:** all website users share one rate-limit bucket (the SvelteKit server's IP)
- **Direct API traffic:** any client can spoof their IP and get a fresh rate-limit bucket per request

### Consequences

| System | Impact |
|--------|--------|
| **Rate limiting (BFF)** | All website users share one IP bucket. The 10 req/min queue limit is shared across ALL visitors, not per-user. Legitimate users can rate-limit each other. |
| **Rate limiting (direct)** | Any client setting `X-Forwarded-For: <random-ip>` bypasses per-IP rate limiting entirely. Each request gets a fresh bucket. |
| **ESIGN audit trail** | Waiver endpoints log `realip_remote_addr()` for the signer's IP (begin, consent, confirm, sign). All website waivers would record the SvelteKit server's IP, not the signer's. |
| **Registration limiter** | 5 req/min shared across all website registration attempts (BFF), or bypassable (direct). |

### What's NOT affected

- **Payload size** — Actix-web's 256KB JSON limit (`api_server.rs:48-49`) prevents oversized payloads regardless of IP identification.
- **Authenticated endpoints** — session/token auth is independent of IP. An attacker still needs valid credentials.

### Resolution — Railway hosting (DEC-141)

Railway provides `X-Real-IP` — a documented, authoritative header set by their edge proxy. Private networking via WireGuard (`service.railway.internal:PORT`) allows the BFF to forward `X-Real-Client-IP` without proxy interference.

| Header | Set by | Spoofable? | Notes |
|--------|--------|------------|-------|
| `X-Real-IP` | Railway edge proxy | No | Documented, authoritative, single value |
| `X-Real-Client-IP` | BFF (custom) | No | Only reachable via Railway private network |
| `X-Forwarded-For` | Client + proxies | **Yes** | Banned — never used for IP identification |

**Source:** [Railway docs — Public Networking Specs](https://docs.railway.com/networking/public-networking/specs-and-limits)

### Fix

See **Slice 1** below.

---

## 1. Validation Architecture

The server is the only layer that enforces constraints. Every other layer documents or partially checks:

| Layer | Example: `guest_name` | Enforced? |
|-------|----------------------|-----------|
| **Rust handler** | `MAX_GUEST_NAME_LEN = 200`, checked at runtime | Yes — server-side |
| **Rust doc comment** | `/// 1–200 characters.` | No — documentation only |
| **OpenAPI spec** | `{ "type": "string", "description": "1–200 characters." }` | No — no `minLength`/`maxLength` keywords |
| **SDK type** | `guest_name: string` (JSDoc: "1–200 characters.") | No — TypeScript can't enforce length |
| **ViewModel** | `if (!guestName.trim()) errors.guestName = 'Name is required.'` | Partially — checks required, not length |
| **HTML** | `<input required>` | Partially — no `maxlength` attribute |

This is acceptable because:
- **Actix-web enforces a 256KB JSON payload limit** (`api_server.rs:48-49`) — nobody can send megabyte-sized strings.
- **Per-endpoint rate limiting** exists for public endpoints — queue (10 req/min), registration (5 req/min), addons (10 req/min).
- **The server validates every field** with explicit constants and returns structured error codes.

Client-side validation would reduce round trips for obviously-wrong input (UX improvement) but does not change the security posture.

**OpenAPI gap:** `api-contracts` uses zero `#[schema(...)]` validation attributes. utoipa version `"5"` (semver range) supports `min_length`, `max_length`, `minimum`, `maximum`, `format`, `pattern` — none are used. The `party_size` field has `minimum: 0` (auto-derived from `u16`) while the business rule is `>= 1`. This is a spec accuracy issue, not a runtime issue (server enforces the correct rule).

---

## 2. Per-Domain Findings

### 2.1 Booking Flow

**Files:** `routes/(public)/book/_components/` — `bookingFlow.svelte.ts`, `bookingApi.ts`, `GuestInfoForm.svelte`, `BookingFlow.svelte`, `+server.ts`

**Architecture:** ViewModel pattern. `$state()` runes, getter/setter accessors, centralized validation, fetch to BFF endpoint. **This is the gold standard on the site.**

**What works:**
- Strong typing throughout — SDK types (`ProductDto`, `TimeSlot`, `CreateBookingBody`) used directly, no `any`, no unsafe casts
- Proper null handling — `guest_phone: guestPhone.trim() || null`
- Business logic validation — guest count checked against product's `min_guests`/`max_guests`
- Date range validation — tomorrow minimum, 90-day maximum
- Email format — regex check (`/^[^\s@]+@[^\s@]+\.[^\s@]+$/`)
- Error display — per-field via `Record<string, string>`, form-level via `submitError`
- Accessibility — `aria-invalid`, `aria-describedby`, `role="alert"`, `aria-live="polite"`

**What's missing:**
- No length validation for `guest_name` (server enforces 1–200)
- No length validation for `guest_email` (server enforces 5–254)
- No length validation for `guest_phone` (server enforces max 30)
- No `maxlength` HTML attribute on freeform text inputs (notes textarea has `maxlength={2000}`; ConfirmPanel has `maxlength={6}` on confirmation code — but name, email, phone have no length constraints)
- Email regex is simple, not RFC 5322 compliant (acceptable for UX, server validates definitively)

**BFF handler (`+server.ts`):**
- Passes request body directly to SDK with no validation
- Error handling via `sanitizeBffError()` — maps API error codes to user-facing messages
- Acceptable pattern — server is the authority — but means a round trip for every validation failure

### 2.2 Waiver Flow

**Files:** `lib/components/waiver/` — `waiverFlow.svelte.ts`, `waiverApi.ts`, `WaiverStepInfo.svelte`, `WaiverStepConsent.svelte`, `WaiverStepConfirm.svelte`, `WaiverStepSign.svelte`; `routes/(public)/waiver/api/begin/+server.ts`

**Architecture:** ViewModel pattern. 5-step flow (info → consent → confirm → sign → complete). Draft UUID tracks server-side state.

**What works:**
- `addressState` typed as `UsState` (literal union from `$lib/constants/usStates.ts`) — dropdown enforces valid selection
- `guardianRelationship` typed as `GuardianRelationship | null` — SDK enum type
- Step-by-step server validation — each step hits an API endpoint, server validates before advancing
- Conditional minor fields (DOB + guardian relationship) properly gated on `isMinor`
- Read-only confirmation step before signing
- Error code mapping via `handleApiError()` switch — specific UX per error (expired session resets to step 1, etc.)

**What's missing:**
- No length validation on any field — `participant_name`, all address fields, all emergency contact fields
- No format validation on phone, zip code, or date
- No email field in waiver flow (not applicable — but emergency contact phone has no format check)

**Unsafe type assertion in BFF layer:**
```typescript
// routes/(public)/waiver/api/begin/+server.ts line 39
guardian_relationship: raw.guardian_relationship as 'parent' | 'legal_guardian',
```
Unvalidated user input is cast directly to a union type. A malicious request with `"guardian_relationship": "admin"` would pass the BFF type check and only fail at the server. The cast provides false type safety. **Fix in Slice 2.**

**BFF handler coercion pattern:**
```typescript
const shared = {
  document_uuid: String(raw.document_uuid ?? ''),
  participant_name: String(raw.participant_name ?? ''),
  participant_dob: raw.participant_dob ? String(raw.participant_dob) : undefined,
  // ...all fields coerced to String with ?? '' fallback
};
```
All fields coerced to string regardless of input type. No validation — empty strings, garbage data all pass through. Server is the only safety net. Actix-web's 256KB payload limit prevents oversized payloads.

### 2.3 Auth — Login

**Files:** `routes/(auth)/login/+page.svelte`, `+page.server.ts`

**Architecture:** SvelteKit form action with `use:enhance`.

**What works:**
- Token set as httpOnly cookie (`uwz_token`) — secure, sameSite lax, 7-day max age
- Form state persisted on error (`form?.email` repopulates field)
- Specific error messages — 401 → "Invalid email or password", 500 → generic
- Redirect validation via `validateRedirect()` — prevents open redirects

**What's missing:**
- No client-side validation beyond HTML `required` — no email format check, no minimum length
- No per-field error display — single `FormAlert` for all errors
- No rate-limit feedback (server may rate-limit, but no specific UX for 429)

### 2.4 Auth — Register

**Files:** `routes/(auth)/register/+page.svelte`, `+page.server.ts`

**Architecture:** SvelteKit form action. **Endpoint not yet implemented — returns 501.**

**What works:**
- Per-field error display — `form?.errors?.f_name` etc. renders on each FormField. Best error UX of any form action page.
- Server-side validation: required fields, password >= 8 chars, confirm password match
- Form state persisted on error for all fields

**What's missing:**
- No email format validation (not even HTML `type="email"` check at server)
- No username constraints surfaced (server will enforce 1–16 chars once endpoint exists)
- **Endpoint is a stub** — no SDK type mapping yet

### 2.5 Profile

**Files:** `routes/portal/profile/_components/ProfileView.svelte`, `+page.server.ts`

**Architecture:** SvelteKit form action.

**What works:**
- All fields optional (correct for profile updates)
- SDK type `UpdatePortalProfileBody` properly maps nullable fields
- Success feedback via `FormAlert variant="success"`

**What's missing:**
- **Zero client-side validation** — no required checks, no format checks, no length checks
- No per-field error display — single form-level `FormAlert`
- Phone accepts any string, birthday accepts any date (no future-date guard)
- 422 from server shows generic "Please check your input" — no field-level guidance

### 2.6 Queue — Call Ahead

**Files:** `routes/(public)/queue/_components/CallAheadForm.svelte`, `+page.server.ts`

**Architecture:** SvelteKit form action. Public endpoint (no auth).

**What works:**
- Reactive time slot generation from operating hours — sophisticated `$derived.by()` logic
- Time normalization — HH:MM input → HH:MM:SS for API
- Server validation: name max 128, email 5–254 with `is_valid_email()`, party size >= 1, notes max 2000

**What's missing:**
- No client-side validation beyond HTML `required`
- No email format check client-side
- No length constraints on any field
- `party_size` has `minimum: 0` in OpenAPI (from `u16`) but business rule is >= 1 — spec discrepancy (server enforces correctly)

### 2.7 Portal — Waiver Attach

**Files:** `routes/portal/waivers/_components/WaiverAttachForm.svelte`, `+page.server.ts`

**Architecture:** SvelteKit form action with `use:enhance`. Checkboxes for multi-select.

**What works:**
- FormData extraction with proper type checking (`typeof booking_uuid !== 'string'`)
- Multi-select via `formData.getAll('waiver_uuid')`
- Validation: requires booking selection + at least one waiver
- `invalidateAll()` after success refreshes page data

**What's missing:**
- Nothing significant — this form is simple (select + checkboxes) and handles its scope correctly

---

## 3. Shared Form Components

**Location:** `lib/components/forms/`

### FormField.svelte
```typescript
interface Props {
    label: string;
    name: string;
    type?: 'text' | 'email' | 'password' | 'number' | 'tel' | 'date' | 'url' | 'search';
    value?: string | number;
    required?: boolean;
    min?: number;
    max?: number;
    error?: string;
    oninput?: (e: Event) => void;
}
```
- Display-only wrapper — renders label, input, error message
- No internal validation logic
- Supports `min`/`max` for number inputs via HTML attributes
- **Missing:** `maxlength`, `minlength`, `pattern` props — callers cannot set string length constraints through the component API. **Fix in Slice 2.**
- Good a11y: `aria-invalid`, `aria-describedby`, error `id` linked to input

### FormSelect.svelte
- Typed `Option[]` for dropdown items
- Placeholder support, required attribute
- Same error display pattern as FormField
- Used by: waiver (state, guardian relationship), queue (time slot), portal (booking attach)

### FormTextarea.svelte
- Supports `maxlength` prop (the only form component that does)
- Used by: booking notes, queue notes
- Same error display pattern

### FormAlert.svelte
- `variant: 'error' | 'success'`
- No dismiss mechanism — parent must clear
- Used for form-level (not field-level) messages

### SubmitButton.svelte
- Loading spinner, disabled state, `aria-busy`
- Clean and consistent

---

## 4. Two Form Patterns

| Pattern | Used by | Data flow | Validation |
|---------|---------|-----------|------------|
| **ViewModel + fetch** | Booking, Waiver | `$state()` → ViewModel method → `fetch()` to `+server.ts` BFF → SDK | Client-side in ViewModel, server-side in API |
| **Form action + enhance** | Login, Register, Profile, Queue, Waiver Attach | `<form method="POST">` → `+page.server.ts` action → SDK | Server-side in action handler, HTML attributes client-side |

Both patterns are valid. The ViewModel pattern is better for multi-step interactive flows. Form actions are better for single-submit CRUD. Payment forms will need the ViewModel pattern (multi-step, client-side state, real-time feedback).

---

## 5. TypeScript Leverage Assessment

### Type-level: strong
- SDK types flow through without `any` or gratuitous casts (one exception: waiver BFF guardian_relationship)
- ViewModel return types properly inferred via `ReturnType<typeof createXViewModel>`
- Component props use `interface Props` consistently
- Enum types used for step constants, booking status, guardian relationship, US states

### Constraint-level: absent
- Every `string` field in the SDK accepts any string — no branded types, no template literals, no runtime schemas
- TypeScript cannot enforce length, format, or pattern constraints at compile time
- No runtime validation library bridges the gap

This is a language limitation, not a code quality issue. The server enforces all constraints at runtime.

---

## 6. OpenAPI Spec Gap

### Current state
- utoipa version: **"5"** (semver range, not pinned — resolved version depends on Cargo.lock)
- Existing `#[schema(...)]` usage: `inline` (5), `value_type = Object` (3), `default = false` (1) — **zero validation attributes**
- All string fields: `{ "type": "string" }` with constraint info in `description` only
- Numeric fields: `minimum: 0` auto-derived from `u16`, but business minimums (e.g., `party_size >= 1`) not encoded
- No `format: "email"` on email fields
- No `format: "date-time"` explicitly set (some inferred from `DateTime<Utc>`)

### Spec accuracy issue
`party_size` in `CallAheadBody`, `CreateQueueEntryBody`, and `QueueEntryDto` shows `minimum: 0` (from `u16`). The server enforces `>= 1`. The spec description on `CallAheadBody` says "Must be at least 1" but the schema constraint says 0. Not a runtime bug — the server validates correctly — but the spec is inaccurate for consumers reading the schema.

---

## 7. BFF Layer Findings

### sanitizeBffError utility
**Location:** `lib/api/sanitizeBffError.ts`

Maps API error codes to user-safe messages. Hardcoded set of "user-facing" codes: 4013, 4016, 4017, 4018, 4019, 4020, 4021. Unknown errors default to "Something went wrong."

**Works well.** Only concern: as new endpoints are added (payments), the user-facing code set needs to grow. No mechanism to ensure new codes are registered.

### handleLoadError utility
**Location:** `lib/api/handleLoadError.ts`

Catches 401 in server loads, deletes cookie, redirects to `/login`. Used in portal layout and page loads.

**Works well.** Clean pattern.

### BFF body size limits
BFF handlers (`+server.ts` files) perform no explicit body size validation. They rely on Node.js/SvelteKit default body parsing limits (~100KB). The PostHog ingest proxy is the exception — it explicitly enforces a 1MB limit with a 413 response.

The Actix-web server enforces a hard 256KB limit regardless, so oversized payloads are rejected even if the BFF doesn't catch them.

---

## 8. Accessibility Findings

### Strong
- `aria-invalid` and `aria-describedby` on all FormField inputs when errors present
- `role="alert"` on error messages
- `aria-live="polite"` on dynamic content (availability slots, submission errors)
- `aria-busy` on SubmitButton during loading
- Semantic HTML — `<label>`, `<input>`, `<fieldset>` used appropriately
- Focus management in waiver flow — scroll-to-heading on step transitions

### Gaps
- No visible "required" indicator on fields (only HTML `required` attribute — screen readers announce it, but sighted users have no asterisk or label hint)
- FormAlert has no dismiss mechanism — persists until form resubmit
- Call Ahead form assumes timezone knowledge ("Central Time" hardcoded in label)

---

## 9. Existing Defenses

These protections exist today and were not surfaced by the original audit:

| Defense | Location | Limit |
|---------|----------|-------|
| JSON payload size | `api_server.rs:48` | 256KB hard limit |
| Raw payload size | `api_server.rs:49` | 256KB hard limit |
| Queue rate limit | `call_ahead_post.rs`, `queue_entries_post.rs` | 10 req/min per IP |
| Registration rate limit | `users_register.rs` | 5 req/min per IP |
| Addon rate limit | `addons_post.rs` | 10 req/min per IP |
| General rate limit | `rate_limit_service.rs` | Configurable per env |
| SvelteKit body parser | Node.js default | ~100KB (implicit) |
| PostHog proxy limit | `ingest/[...path]/+server.ts` | 1MB explicit |

**Fixed:** Rate limiting now uses `extract_client_ip()` which reads `X-Real-IP` (Railway edge) and `X-Real-Client-IP` (BFF private network). See DEC-141.

---

## Slice 1 — Client IP Identification (COMPLETED)

**Status:** Implemented 2026-03-18. DEC-141.
**Scope:** server, sdk-ts, surface-website BFF, SvelteKit env config
**Host:** Railway (migrated from Render due to unreliable IP identification)

### What was built

| Component | Change |
|-----------|--------|
| **Server** | `extract_client_ip()` in `api/validation.rs` — reads `X-Real-IP` (Railway edge, public) then `X-Real-Client-IP` (BFF, private network). 14 files updated. `realip_remote_addr()` eliminated. |
| **SDK** | `ClientOptions.headers` — optional headers merged into every request. Non-breaking. |
| **BFF** | `hooks.server.ts` sets `locals.clientIp` via `event.getClientAddress()`. All 26 `createClient()` call sites forward `locals.clientIp` as `X-Real-Client-IP`. |
| **SvelteKit env** | `ADDRESS_HEADER=X-Real-IP` — tells `getClientAddress()` to read Railway's header. |

### Deployment config needed

- `ADDRESS_HEADER=X-Real-IP` on the SvelteKit service
- `API_BASE_URL` pointed at Railway private network: `http://server.railway.internal:PORT`
- `X-Forwarded-For` is never read — spoofable, banned per DEC-141

### Verification (post-deploy)

- [ ] Rate limiter uses `X-Real-IP` for public traffic — spoofed `X-Forwarded-For` ignored
- [ ] BFF-originated requests carry `X-Real-Client-IP` with the real client IP
- [ ] Waiver audit trail captures real signer IP
- [ ] `X-Forwarded-For` spoofing does not bypass rate limiting

---

## Slice 2 — Mechanical Fixes

**Priority:** Normal — code quality
**Scope:** surface-website only, no server changes

### 2a. FormField: add maxlength, minlength, pattern props

**File:** `lib/components/forms/FormField.svelte`

Add optional `maxlength`, `minlength`, and `pattern` props to the `Props` interface. Pass them through to the `<input>` element as HTML attributes. No validation logic — these are native HTML attributes that the browser enforces.

```typescript
interface Props {
    // ...existing props
    maxlength?: number;
    minlength?: number;
    pattern?: string;
}
```

Once available, callers can add constraints:
```svelte
<FormField label="Name" name="guest_name" maxlength={200} required />
<FormField label="Email" name="guest_email" type="email" maxlength={254} required />
<FormField label="Phone" name="guest_phone" type="tel" maxlength={30} />
```

**Not in scope:** wiring these props into existing forms. That's a follow-up if/when it matters.

### 2b. Fix guardian_relationship unsafe cast

**File:** `routes/(public)/waiver/api/begin/+server.ts` line 39

Replace:
```typescript
guardian_relationship: raw.guardian_relationship as 'parent' | 'legal_guardian',
```

With runtime validation:
```typescript
guardian_relationship: (() => {
    const val = raw.guardian_relationship;
    if (val === 'parent' || val === 'legal_guardian') return val;
    return undefined;
})(),
```

Or more concisely with a guard:
```typescript
const VALID_GUARDIAN = ['parent', 'legal_guardian'] as const;
const gr = VALID_GUARDIAN.includes(raw.guardian_relationship) ? raw.guardian_relationship : undefined;
// then use `gr` in the body
```

The server validates this field regardless — the fix is about not lying to TypeScript.

### Verification

- [ ] `svelte-check` passes
- [ ] Waiver begin flow works for both adult and minor paths
- [ ] FormField renders maxlength attribute when prop is set

---

## Slice 3 — Form Validation Service (DEFERRED)

**Priority:** Deferred — evaluate when payment forms are built
**Scope:** surface-website

### Context

Client-side validation would reduce round trips for obviously-wrong input. The server validates everything, so this is a UX improvement, not a security fix. The decision to add a validation library should be made when payment forms create a concrete need — not in advance.

### Decision factors (for when this is picked up)

**Valibot vs Zod:**
- Valibot: ~5KB gzipped, tree-shakeable, TypeScript-idiomatic
- Zod: ~13KB gzipped, not tree-shakeable, mature OpenAPI tooling
- For a customer-facing site with ~6 forms, Valibot's size advantage likely wins
- If codegen from OpenAPI is desired, Zod's ecosystem is stronger

**Scope:**
- Payment form validation first (the forcing function)
- Backfill existing forms only if the pattern proves worthwhile
- Hand-write schemas (6 forms is manageable), evaluate codegen later

**Where validation runs:**
- ViewModel pattern: validate in the ViewModel before fetch
- Form action pattern: validate in the `+page.server.ts` action before SDK call
- BFF `+server.ts` handlers: optional — validate before forwarding to save a round trip

**OpenAPI spec enrichment:**
- Adding `#[schema(min_length, max_length, ...)]` to `api-contracts` would make the spec machine-readable
- Enables future codegen of validation schemas from the spec
- This is a server-side change — dispatch separately if pursued

### Not recommended
- Codegen validation schemas from OpenAPI — over-engineering for 6 forms
- FormField accepting a `schema` prop — over-engineers the component
- Shared validators file (`$lib/utils/validators.ts`) — premature before the library decision; the library will provide these
