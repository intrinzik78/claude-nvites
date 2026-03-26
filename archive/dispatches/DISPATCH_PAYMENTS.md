# Authorize.Net Payment Integration

**Date:** 2026-03-23
**Workstream:** server
**Plan file:** `/home/zik/.claude/plans/reflective-stargazing-melody.md`

## Context

Online bookings currently create as Pending with no money changing hands. This plan adds payment processing via Authorize.Net so customers pay at booking time (pay-to-book). Successful charge confirms the booking; failed charge cancels it. Full lifecycle: charge, void, refund, webhooks.

DEC-038 originally named Stripe/Square for Phase 2. This plan replaces that with Authorize.Net. A new decision should supersede the gateway reference in DEC-038.

**Scope:** Website bookings only. Walk-up/queue bookings are unaffected. Command center does not collect payment.

## Architecture

### New Crate: `server/authorizenet/`

Follows the Postmark pattern — isolated workspace crate, zero Actix dependencies.

```
authorizenet/
├── Cargo.toml          (reqwest, serde, serde_json, derive_more, hmac, sha2)
├── src/
│   ├── lib.rs
│   ├── types/
│   │   ├── mod.rs
│   │   ├── client.rs        AuthorizeNet struct (reqwest client, API credentials)
│   │   ├── env.rs           Env: API_LOGIN_ID, TRANSACTION_KEY, SIGNATURE_KEY, SANDBOX
│   │   ├── request.rs       createTransactionRequest (authCapture, void, refund)
│   │   ├── response.rs      transactionResponse, messages, error handling
│   │   └── webhook.rs       webhook payload parsing + HMAC-SHA512 signature verification
│   └── enums/
│       ├── mod.rs
│       └── error.rs         AuthorizeNetError (Reqwest, Api, SignatureInvalid)
```

**Key type: `AuthorizeNet`**
- `new()` reads env vars, builds reqwest Client
- `charge(nonce, amount, order_ref, email) → Result<ChargeResponse>`
- `void(transaction_id) → Result<VoidResponse>`
- `refund(transaction_id, amount, last_four) → Result<RefundResponse>`
- `approve_held(transaction_id) → Result<ApproveResponse>`
- `decline_held(transaction_id) → Result<DeclineResponse>`
- `get_transaction_details(transaction_id) → Result<TransactionDetails>`
- `verify_webhook_signature(body, signature) → bool`

**Env vars:**
- `AUTHORIZENET_API_LOGIN_ID`
- `AUTHORIZENET_TRANSACTION_KEY`
- `AUTHORIZENET_SIGNATURE_KEY` (webhook HMAC verification)
- `AUTHORIZENET_SANDBOX` ("true"/"false" → API base URL selection)

**API base URLs:**
- Production: `https://api.authorize.net/xml/v1/request.api`
- Sandbox: `https://apitest.authorize.net/xml/v1/request.api`

### Data Model

**New table: `payment_transaction`**
```sql
CREATE TABLE payment_transaction (
  id                INT NOT NULL AUTO_INCREMENT,
  booking_id        INT NOT NULL,
  anet_transaction_id VARCHAR(32),        -- Authorize.Net's transaction ID
  ref_id            VARCHAR(16),          -- booking UUID (idempotency key)
  transaction_type  TINYINT NOT NULL,     -- 1=AuthCapture, 2=Void, 3=Refund
  subtotal_cents    INT UNSIGNED NOT NULL,
  tax_cents         INT UNSIGNED NOT NULL,
  total_cents       INT UNSIGNED NOT NULL,
  status            TINYINT NOT NULL,     -- 1=Approved, 2=Declined, 3=Error, 4=HeldForReview
  response_code     VARCHAR(8),
  auth_code         VARCHAR(8),
  avs_result_code   VARCHAR(4),
  cvv_result_code   VARCHAR(4),
  last_four         VARCHAR(4),           -- stored for refund API requirement
  card_type         VARCHAR(16),          -- Visa, Mastercard, etc.
  error_message     VARCHAR(255),
  raw_response      TEXT,                 -- full JSON for debugging/disputes
  created_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_pt_booking (booking_id),
  KEY idx_pt_anet_txn (anet_transaction_id),
  CONSTRAINT fk_pt_booking FOREIGN KEY (booking_id) REFERENCES booking (id)
);
```

**New system_settings columns:**
- `payment_service` TINYINT NOT NULL DEFAULT 0 — SystemFlag (0=Disabled, 1=Enabled)
- `tax_rate_basis_points` SMALLINT UNSIGNED NOT NULL DEFAULT 0 — e.g., 825 = 8.25%

### Booking + Payment Flow (Pay-to-Book)

Leverages existing behavior: `NewBooking::into_db` already creates as **Pending** and reserves capacity via `SELECT ... FOR UPDATE`.

```
POST /v1/bookings (with payment nonce + optional addons)

1. Validate body (existing checks + nonce present when payment_service Enabled)
2. Validate product, guest count, operating hours (unchanged)
3. Look up or create Person (unchanged)
4. NewBooking::into_db → Pending booking, capacity reserved, committed
5. If addons provided: insert booking_addons (price snapshots from products)
6. Compute charge:
   subtotal = price_cents × guest_count + Σ(addon.quantity × addon.unit_price_cents)
   tax      = round(subtotal × tax_rate_bp / 10000)
   total    = subtotal + tax
7. Call AuthorizeNet::charge(nonce, total, booking_uuid, guest_email)
8a. APPROVED:
    - Insert payment_transaction (Approved)
    - Update booking → Confirmed
    - Fire confirmation email (existing fire-and-forget pattern)
    - Return 201 with BookingDto + PaymentSummaryDto
8b. DECLINED / ERROR:
    - Insert payment_transaction (Declined/Error) for audit trail
    - Cancel booking (releases capacity)
    - Return 422 with payment error details
8c. HELD FOR REVIEW (responseCode=4):
    - Insert payment_transaction (HeldForReview)
    - Booking stays Pending (capacity reserved)
    - No confirmation email yet
    - Return 202 with "booking is under review" message
    - Staff reviews in command center → approve or decline
    - Approve webhook → confirm booking + send confirmation email
    - Decline webhook → cancel booking + send decline notification
```

**Crash safety:**
- Crash before step 7: Pending booking, no charge. BookingSweeper cancels after 15 minutes.
- Crash after charge but before step 8a: Pending booking with successful charge. Webhook handler reconciles — sees `authcapture.created`, finds Pending booking, confirms it.
- Crash after step 8b: Pending booking with failed charge. BookingSweeper cancels.

**BookingSweeper interaction:** The sweeper must skip Pending bookings that have any `payment_transaction` row (Approved or HeldForReview). HeldForReview can take up to 5 days to resolve — the 15-minute sweep window would kill these bookings otherwise. Sweeper query gains a `NOT EXISTS (SELECT 1 FROM payment_transaction WHERE booking_id = booking.id)` condition.

**When `payment_service == Disabled`:** Steps 1-4 execute as today. Steps 5-8 are skipped. Booking stays Pending. Existing behavior preserved.

### Addon Inline Creation

`CreateBookingBody` gains an optional `addons` field. When present, addons are inserted in the same handler call (between steps 4 and 6 above), using the existing `BookingAddon` price-snapshot logic from `addons_post.rs`. The charge includes them.

If addon insertion fails after the booking is committed, the handler must cancel the Pending booking before returning the error.

Existing `POST /v1/bookings/{uuid}/addons` endpoint remains for adding addons after booking creation (facility use case, deferred to later slice).

### Booking Preview (Order Summary)

```
POST /v1/bookings/preview (public, no auth)

Body: product_id, guest_count, addons (same shape as CreateBookingBody minus payment nonce)

Returns:
  product_name, price_per_person_cents, guest_count
  line_items: [{ name, quantity, unit_price_cents, line_total_cents }]
  subtotal_cents
  tax_cents
  tax_rate_display ("8.25%")
  total_cents
```

No DB writes, no capacity check. Validates product exists and is active, looks up addon prices, computes breakdown using the same tax calculation helper as the charge flow. The website calls this when the customer changes guest count or toggles addons — shows the full breakdown before "Book Now."

Single source of truth for pricing math — prevents client/server divergence on tax rounding.

### Void / Refund Flow

On booking cancellation (portal or staff):

```
1. Look up approved payment_transaction for booking
2. If none → cancel booking as today (no payment to reverse)
3. Try void first (works for unsettled transactions — same-day)
4. If void fails with "already settled" → fall back to refund
   (refund requires last_four + amount, both stored on original transaction)
5. Insert void/refund payment_transaction record
6. Cancel booking
```

Both `POST /v1/portal/bookings/{uuid}/cancel` and `PATCH /v1/bookings/{id}/status` (→ Cancelled) trigger this logic.

### Webhook Flow

```
POST /v1/webhooks/authorizenet (no auth — signature-verified)

1. Read raw request body
2. Verify X-ANET-Signature header (HMAC-SHA512 of body with signature key)
3. Parse event type + transaction ID from payload
4. Call AuthorizeNet::get_transaction_details(transaction_id)
5. Match to local payment_transaction by anet_transaction_id
6. Handle by event type:
   - authcapture.created → reconcile (confirm Pending booking if unconfirmed)
   - void.created → confirm void processed
   - refund.created → confirm refund processed
   - fraud.declined → flag for review (log + potentially cancel)
7. Return 200
```

Registered via Authorize.Net dashboard (not API). Must respond within 10 seconds.

### Fraud Review (Command Center)

Staff reviews held-for-review transactions in the command center, not the Authorize.Net dashboard. The command center shows booking context alongside fraud signals — staff sees "party of 15, Deluxe package, Saturday 2pm" plus AVS/CVV results, not just a transaction ID and dollar amount.

**Server endpoints:**
- `GET /v1/payments/held` — list held-for-review transactions with booking context (Editor)
- `POST /v1/payments/{id}/approve` — approve held transaction via `updateHeldTransactionRequest` (Editor)
- `POST /v1/payments/{id}/decline` — decline held transaction via `updateHeldTransactionRequest` (Editor)

**Authorize.Net API:**
```json
{
  "updateHeldTransactionRequest": {
    "merchantAuthentication": { ... },
    "heldTransactionRequest": {
      "action": "approve" | "decline",
      "refTransId": "transaction_id"
    }
  }
}
```

**Outcome:** Approve fires `authcapture.created` webhook → confirm booking + send confirmation email. Decline fires `fraud.declined` webhook → cancel booking + send decline notification.

**Scope boundary:** The command center handles the common operational case (review held bookings with booking context). Staff still needs Authorize.Net dashboard access for edge cases: disputes, chargebacks, batch reporting, advanced fraud rules configuration.

## Contract Changes (api-contracts)

**Modified:**
```rust
// CreateBookingBody — add optional payment + addons
pub struct CreateBookingBody {
    // ... existing fields unchanged ...
    pub payment: Option<PaymentNonce>,          // required when payment_service Enabled
    pub addons: Option<Vec<AddonSelection>>,    // optional inline addons
}
```

**New types:**
```rust
pub struct BookingPreviewBody {
    pub product_id: i32,
    pub guest_count: u16,
    pub addons: Option<Vec<AddonSelection>>,
}

pub struct BookingPreviewDto {
    pub product_name: String,
    pub price_per_person_cents: u32,
    pub guest_count: u16,
    pub line_items: Vec<LineItemDto>,
    pub subtotal_cents: u32,
    pub tax_cents: u32,
    pub tax_rate_display: String,       // "8.25%"
    pub total_cents: u32,
}

pub struct LineItemDto {
    pub name: String,
    pub quantity: u16,
    pub unit_price_cents: u32,
    pub line_total_cents: u32,
}

pub struct PaymentNonce {
    pub data_descriptor: String,    // "COMMON.ACCEPT.INAPP.PAYMENT"
    pub data_value: String,         // opaque nonce from Accept.js
}

pub struct AddonSelection {
    pub product_id: i32,
    pub quantity: u16,
}

pub struct PaymentSummaryDto {
    pub transaction_id: String,
    pub status: TransactionStatus,
    pub subtotal_cents: u32,
    pub tax_cents: u32,
    pub total_cents: u32,
    pub card_type: Option<String>,
    pub last_four: Option<String>,
}

pub struct PaymentTransactionDto {
    pub id: i32,
    pub anet_transaction_id: Option<String>,
    pub transaction_type: TransactionType,
    pub subtotal_cents: u32,
    pub tax_cents: u32,
    pub total_cents: u32,
    pub status: TransactionStatus,
    pub last_four: Option<String>,
    pub card_type: Option<String>,
    pub created_at: DateTime<Utc>,
}
```

**New enums:**
```rust
pub enum TransactionType { AuthCapture = 1, Void = 2, Refund = 3 }
pub enum TransactionStatus { Approved = 1, Declined = 2, Error = 3, HeldForReview = 4 }
```

## Server Error Variants

```rust
// From conversion
#[from] AuthorizeNet(authorizenet::enums::AuthorizeNetError),

// Client-facing
PaymentDeclined,                    // 422 — card declined
PaymentError,                       // 502 — gateway error
PaymentHeldForReview,               // 202 — held for fraud review
PaymentNonceInvalid,                // 422 — invalid/expired nonce
PaymentNonceRequired,               // 422 — payment_service enabled but no nonce
PaymentVoidFailed,                  // 502 — void attempt failed
PaymentRefundFailed,                // 502 — refund attempt failed
PaymentWebhookSignatureInvalid,     // 401 — webhook signature mismatch
PaymentTransactionNotFound,         // 404 — no transaction for booking
BookingAddonInvalidInline,          // 422 — inline addon validation failure
```

Update `to_api_error_message()` mappings and bump `EXPECTED_CLIENT_FACING_COUNT`.

## AppState Changes

```rust
pub struct AppState {
    // ... existing fields ...
    authorizenet: AuthorizeNetStatus,   // Enabled(AuthorizeNet) | Disabled
}
```

Follow the `RateLimiterStatus` pattern — enum wrapping the service. Getter: `pub fn authorizenet(&self) -> &AuthorizeNetStatus`.

Settings gains: `pub payment_service: SystemFlag` and `pub tax_rate_basis_points: u16`. `with_database_settings` copies both from DB.

## Already Shipped (pre-Slice 1)

The following items from this plan were implemented during the 2026-03-23 `/book` page build:

- **`POST /v1/bookings/preview`** — endpoint live, public, no auth. Computes line-item breakdown with tax. Handler: `bookings_preview.rs`.
- **`BookingPreviewBody`, `BookingPreviewDto`, `LineItemDto`, `AddonSelection`** — contract types in `api-contracts/src/bookings.rs`.
- **OpenAPI path stub** registered in api-contracts and schema-emitter.
- **SDK wrapper** — `sdk.getBookingPreview(body)` in `sdk-ts/src/api/`, barrel-exported.
- **Website receipt** — BFF endpoint at `/book/preview/+server.ts`, receipt displayed in booking step 4 (BookingReview).
- **`tax_rate_basis_points`** — column exists in `system_settings` (added via migration, default 0).
- **u64→u32 overflow guard** — fixed in `bookings_preview.rs`: subtotal accumulates in u64, overflow guard before DTO construction. Was flagged HIGH in review.

**What remains in the plan below** has been annotated with `[SHIPPED]` where items overlap.

## Implementation Slices

### Slice 1: authorizenet crate (foundation) [SHIPPED — 53763e4]
- ~~Create `server/authorizenet/` crate~~
- ~~`Env`, `AuthorizeNet` client, request/response types~~
- ~~`AuthorizeNetError` enum~~
- ~~Methods: `charge`, `void`, `refund`, `approve_held`, `decline_held`, `get_transaction_details`~~
- ~~Webhook signature verification~~
- ~~Add to workspace Cargo.toml~~
- ~~Unit tests (serialization, signature verification)~~
- ~~Document crate-level and public API doc comments~~
- ~~`/review-rs` pass on crate~~
- ~~**Does not touch api-contracts or server crate**~~

### Slice 2: database + server types [SHIPPED — 53763e4]
- ~~Migration: `payment_transaction` table~~
- ~~Migration: `system_settings` add `payment_service` column (`tax_rate_basis_points` [SHIPPED])~~
- ~~`PaymentTransaction` business type in `server/api/src/types/payments/`~~
  - ~~`insert()`, `by_booking_id()`, `by_anet_transaction_id()`~~
- ~~`TransactionType`, `TransactionStatus` enums (api-contracts + server)~~
- ~~`PaymentSummaryDto`, `PaymentTransactionDto` DTOs (api-contracts)~~
- ~~Error variants + `to_api_error_message()` + bump sentinel~~
- ~~Wire `AuthorizeNet` into `AppState` + `Settings`~~
- ~~`AuthorizeNetStatus` enum (Enabled/Disabled)~~
- ~~Document new types, enums, and Settings fields~~
- ~~`/review-rs` pass on all new/modified server code~~
- ~~**Contract change: new enums + DTOs in api-contracts**~~

**Slice 1–2 session notes for next session:**
- `payment_service` flag gates authorizenet in both dev and prod. Dev needs DB flag + env vars.
- `ApiResult::bad_gateway()` (502) added to api-contracts for upstream failures.
- `BookingAddonInvalidInline` (error 7009) is a phantom variant — nothing produces it yet. Wire in slice 3 or remove if unneeded.
- `EXPECTED_CLIENT_FACING_COUNT` is 115. Integration tests for PaymentTransaction exist (5 tests).
- Security: `AuthorizeNet` Debug redacts credentials. `Env` Debug does not (transient, acceptable).
- Sandbox credentials needed before slice 3 manual testing.

### Slice 3: charge at booking [SHIPPED — 5990f3a]
- ~~`POST /v1/bookings/preview` [SHIPPED] — endpoint, contract types, SDK wrapper, website receipt all live~~
- ~~`BookingPreviewBody`, `BookingPreviewDto` [SHIPPED] — in api-contracts~~
- ~~Contract change: `CreateBookingBody` gains `payment` + `addons` fields~~
- ~~`PaymentNonce` DTO (api-contracts) (`AddonSelection` [SHIPPED])~~
- ~~Modify `bookings_post.rs`: two-phase flow (book → charge → confirm/cancel/held)~~
- ~~Handle responseCode=4 (HeldForReview): booking stays Pending, return 202~~
- ~~Inline addon creation (extract price-snapshot logic from `addons_post.rs` into reusable fn on `BookingAddon`)~~
- ~~Resolve `docs/DISPATCH_VALIDATION.md` during this slice: consolidate `MAX_ADDON_QUANTITY`/`MAX_ADDONS_PER_BOOKING` constants to `BookingAddon`, extract shared `validate_selections`, verify product `duration_minutes > 0` guard~~
- ~~Addon failure cleanup: cancel Pending booking before returning error~~
- ~~Tax calculation helper~~
- ~~`SystemFlag` gate: skip payment when Disabled~~
- ~~**BookingSweeper update:** skip Pending bookings with any `payment_transaction` row~~
- ~~Update `BookingConfirmationEmail` template to show subtotal, tax, and total (not just per-person price)~~
- ~~Document payment flow in handler module doc comment, tax calculation logic~~
- ~~`/review-rs` pass on handler changes and extracted helpers~~
- ~~**Heaviest slice — core behavioral change**~~

### Slice 3b: charge handler hardening [SHIPPED — 4f0cded]
- ~~Extract charge logic out of `bookings_post.rs` — handler is ~470 lines, past the 400-LOC god-file threshold. Move payment orchestration into a type or helper method; handler should orchestrate, not implement.~~
- ~~Add `tracing::warn` to all `let _ = Booking::update_status(...Cancelled...)` calls in the handler — ~6 silent cancellation failures in financial paths.~~
- ~~Move preview line-item u32 casts (`as u32`) to after the overflow guard in `bookings_preview.rs` — mathematically safe but brittle ordering.~~
- ~~`/review-rs` pass on refactored handler~~

### Slice 4: void + refund [SHIPPED]
- ~~Extract cancellation payment logic into a reusable method on `PaymentTransaction`~~
  - ~~`reverse_for_booking(booking_id, authorizenet, db) → Result<()>`~~
  - ~~Try void, fall back to refund~~
- ~~Integrate into `portal_cancel.rs` and `bookings_status_patch.rs`~~
- ~~New payment_transaction records for void/refund~~
- ~~Document void/refund decision logic and fallback behavior~~
- ~~`/review-rs` pass on cancellation + refund paths~~
- ~~`/security` pass — SEC-401 closed with `SELECT ... FOR UPDATE` transaction lock~~

### Slice 5: webhooks [SHIPPED]
- ~~`POST /v1/webhooks/authorizenet` handler in `server/api/src/api/webhooks/`~~
- ~~Route registration (no RouteLock — signature verification instead)~~
- ~~Signature verification via authorizenet crate~~
- ~~`getTransactionDetails` call for full payload~~
- ~~Reconciliation: confirm Pending bookings, confirm voids/refunds~~
- ~~**Must use `SELECT ... FOR UPDATE` on payment_transaction rows before reconciliation** — prevents race between webhook confirmation and concurrent cancellation/reversal (same pattern as `reverse_for_booking` in slice 4)~~
- ~~Held transaction outcomes: `authcapture.created` after approve → confirm booking + email; `fraud.declined` after decline → cancel booking + notification~~
- ~~Dedicated rate limiting (tight, separate from general limiter)~~
- ~~Document webhook event handling, reconciliation strategy, and signature verification~~
- ~~`/review-rs` pass on webhook handler and reconciliation logic~~

### Slice 6: staff visibility + fraud review [SHIPPED]
- ~~`GET /v1/bookings/{id}/payments` — payment history for a booking (Editor)~~
- ~~`GET /v1/payments/held` — held-for-review transactions with booking context (Editor)~~
- ~~`POST /v1/payments/{id}/approve` — approve held transaction (Editor)~~
- ~~`POST /v1/payments/{id}/decline` — decline held transaction (Editor)~~
- ~~Handlers in `server/api/src/api/payments/` (new domain subdirectory)~~
- ~~Returns booking context alongside fraud signals (AVS, CVV, card type, last four)~~
- ~~Document endpoints in handler module doc comments~~
- ~~`/review-rs` pass on handlers~~
- ~~`/security` pass — SEC-601 through SEC-604, all low/informational, no action required~~

## Frontend Dependency (surface-website)

Not in scope for server work, but noted as a dependency:
- Include Accept.js from Authorize.Net CDN (`https://js.authorize.net/v1/Accept.js` / `https://jstest.authorize.net/v1/Accept.js`)
- Tokenize card data client-side → receive nonce
- Send nonce in `POST /v1/bookings` body
- Handle payment error responses in UI

## Key Design Decisions to Record

1. **Authorize.Net over Stripe/Square** — supersedes DEC-038 gateway reference
2. **authCaptureTransaction** (immediate capture, not auth-only) — pay-to-book means money moves at booking time
3. **Two-phase flow** (Pending → charge → Confirmed) — leverages existing BookingSweeper for crash safety
4. **refId = booking UUID** — idempotency key for Authorize.Net, enables reconciliation
5. **Tax as basis points** in system_settings — single rate, integer math, no floats
6. **Accept.js nonce** — PCI SAQ-A compliant, card data never touches our server
7. **payment_service SystemFlag** — deploy code first (Disabled), enable when ready

## Verification

Per slice:
- **Slice 1:** `cd server && cargo test -p authorizenet` (unit tests for serialization, signature) → `/review-rs`
- **Slice 2:** `cd server && cargo xtask build-all` (contract change, schema, full pipeline) → `/review-rs`
- **Slice 3:** `cd server && cargo xtask build-all` + manual test with sandbox credentials (create booking with test card nonce) → `/review-rs`
- **Slice 4:** Manual test: create paid booking → cancel → verify void/refund in Authorize.Net sandbox dashboard → `/review-rs`
- **Slice 5:** Manual test: trigger webhook from sandbox → verify reconciliation → `/review-rs`
- **Slice 6:** `cd server && cargo xtask build-all` → `/review-rs`

End-to-end: Sandbox integration test — book → confirm → cancel → verify void → check webhook delivery.

**Final gate:** `/security` pass on all payment-related code (authorizenet crate, payment types, booking handler changes, webhook handler, error variants). Covers: credential handling, nonce validation, webhook signature verification, SQL injection surface, error leakage, rate limiting, input validation.

## Critical Files

| File | Change |
|------|--------|
| `server/authorizenet/` (new) | Entire new crate |
| `server/Cargo.toml` | Add authorizenet to workspace members |
| `api-contracts/src/bookings.rs` | CreateBookingBody, PaymentNonce, AddonSelection |
| `api-contracts/src/payments.rs` (new) | Payment DTOs + enums |
| `server/api/src/types/payments/` (new) | PaymentTransaction business type |
| `server/api/src/types/app_state.rs` | Add AuthorizeNetStatus field + getter |
| `server/api/src/types/settings.rs` | payment_service, tax_rate_basis_points |
| `server/api/src/api/bookings/bookings_post.rs` | Two-phase payment flow |
| `server/api/src/api/bookings/addons_post.rs` | Extract reusable addon creation |
| `server/api/src/api/webhooks/` (new) | Webhook handler |
| `server/api/src/api/payments/` (new) | Held review, payment history handlers |
| `server/api/src/enums/error.rs` | ~10 new variants + mappings |
| `server/api/src/types/route_collection.rs` | Webhook route, payment routes |
| `server/api/src/types/bookings/sweeper.rs` | Skip Pending bookings with payment_transaction |
| `server/email-template/` | BookingConfirmationEmail: subtotal, tax, total |
| `server/migrations/` | payment_transaction table, system_settings columns |
