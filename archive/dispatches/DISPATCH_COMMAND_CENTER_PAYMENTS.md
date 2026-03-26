# Payment Management Surface — Command Center

**Date:** 2026-03-24
**Workstream:** surface-command-center
**Plan file:** `/home/zik/.claude/plans/wiggly-painting-lamport.md`

## Context

Authorize.Net payment integration is shipping on server/dev (DISPATCH_PAYMENTS.md). Slices 1–4 complete, Slice 5 (webhooks) today, Slice 6 (staff visibility) imminent. The command center needs a full payment management view — held transaction review, payment history, refund initiation — purpose-built for staff who understand bookings, not raw Authorize.Net dashboards.

## Dependencies

**Server Slice 6 (imminent):**
- `GET /v1/payments/held` — held-for-review with booking context
- `POST /v1/payments/{id}/approve` — approve held transaction
- `POST /v1/payments/{id}/decline` — decline held transaction
- `GET /v1/bookings/{id}/payments` — payment history per booking

**Rust SDK (dispatched via DISPATCH_SERVER_SDK_GAP.md):**
- `confirm_payment()` on WorkflowInstancesClient
- `PaymentsClient` wrappers for Slice 6 endpoints

## Contract Coordination Items

Two issues need server-side input before Phase 1 implementation:

**1. Booking identifier mismatch.** `GET /v1/bookings/{id}/payments` uses numeric `{id}`, but the surface works exclusively with `BookingDto.uuid` (string). The surface has no access to numeric booking IDs. Recommendation: endpoint should accept UUID — `GET /v1/bookings/{uuid}/payments` — matching the surface's UUID-centric model. Alternatively, add numeric `id` to `BookingDto`.

**2. Missing fraud signals in DTO.** `PaymentTransactionDto` does not include `avs_result_code` or `cvv_result_code`. These exist on the server's `PaymentTransaction` business type but are excluded from the DTO. The fraud review view needs them. Recommendation: either add to `PaymentTransactionDto` or create a dedicated `HeldTransactionDto` that includes fraud signals + booking context. The latter is cleaner (smaller surface for non-fraud contexts).

## Role Gating

| Action | Min Role |
|--------|----------|
| View payments nav + lists | Editor |
| View transaction detail + fraud signals | Editor |
| Initiate refund (cancel & refund) | Editor |
| Approve held transaction | sys_mod |
| Decline held transaction | sys_mod |

## Design Decisions

**Layout: Tabbed view** — "Needs Review" tab (default when held count > 0) and "Transactions" tab.

**"All Transactions" approach: Booking search gateway.** Staff thinks "show me today's paid bookings" — reuse existing `listBookingsByDate` / `listBookingsByEmail` commands, filter to bookings with `payment` present, drill into per-booking history. No new server endpoint needed.

**Refund UX: "Cancel & Refund" with confirmation modal.** Refund = cancel booking (server already handles payment reversal via `reverse_for_booking`). Modal text: "Cancelling this booking will void or refund the payment to the original card. This cannot be undone."

**Toast system: Svelte context** (consistent with auth/dayLock patterns). The poller callback captures the toast context as a closure from the layout's `onMount`.

---

## Phase 0: Foundation (buildable now, no server dependencies)

### 0a: Toast System

First toast implementation in the app. Shared infrastructure, not payment-specific.

**New files:**
- `src/lib/toastContext.svelte.ts` — context with `add(message, variant, duration?)`, `dismiss(id)`, reactive `toasts` array
- `src/lib/components/ToastContainer.svelte` — fixed top-right overlay, renders toast stack
- `src/lib/components/ToastItem.svelte` — individual toast: variant color, auto-dismiss timer, close button

**Variants:** `info` (indigo), `success` (green), `warning` (yellow), `error` (red) — reuse indicator color tokens.

**Behavior:** Auto-dismiss 5s default (0 = manual). Max 3 visible, stacked. Slide-in from right.

**Mount point:** `(app)/+layout.svelte` — create context and render `<ToastContainer />`.

### 0b: Payment Types

**Modify `src/lib/types.ts`:**

```typescript
// New payment types
export type TransactionType = 'auth_capture' | 'void' | 'refund';
export type TransactionStatus = 'approved' | 'declined' | 'error' | 'held_for_review';

export interface PaymentSummaryDto {
  transaction_id: string;
  status: TransactionStatus;
  subtotal_cents: number;
  tax_cents: number;
  total_cents: number;
  card_type: string | null;
  last_four: string | null;
}

export interface PaymentTransactionDto {
  id: number;
  booking_id: number;
  anet_transaction_id: string | null;
  transaction_type: TransactionType;
  subtotal_cents: number;
  tax_cents: number;
  total_cents: number;
  status: TransactionStatus;
  last_four: string | null;
  card_type: string | null;
  error_message: string | null;
  created_at: string;
}

// Shape depends on Slice 6 contract — assumed structure
export interface HeldTransactionDto {
  transaction: PaymentTransactionDto;
  booking: BookingDto;
  avs_result_code: string | null;
  cvv_result_code: string | null;
}
```

**Update existing `BookingDto`** — add `payment?: PaymentSummaryDto` (already in api-contracts, missing from surface type).

### 0c: StatusBadge Extension

**Modify `statusBadge.svelte.ts` + `StatusBadge.svelte`:**

Add `'transaction'` domain:
- `approved` → green, `declined` → red, `error` → red, `held_for_review` → yellow

Add `'transaction_type'` domain:
- `auth_capture` → green (label: "Charge"), `void` → unlit (label: "Void"), `refund` → yellow (label: "Refund")

### 0d: PaymentIcon + Nav Item + Route Shell

**New file:** `src/lib/icons/PaymentIcon.svelte` — credit card or dollar sign SVG

**Modify `src/routes/(app)/+layout.svelte`:**
- Add to `navItems`: `{ label: 'Payments', href: '/payments', minRole: 'editor', icon: PaymentIcon }`

**New files:**
- `src/routes/(app)/payments/+layout.svelte` — BreadcrumbBar wrapper
- `src/routes/(app)/payments/+page.svelte` — tab container with empty state

### 0e: Nav Badge

**Modify `AppNavButton.svelte`** — add optional `badge?: Snippet` prop, render absolute-positioned in top-right of button.

**In `(app)/+layout.svelte`** — conditionally render pulsing red dot badge snippet on the Payments nav button:
```svelte
{#snippet badge()}
  <span class="absolute -top-1 -right-1 h-2.5 w-2.5 rounded-full bg-red-500 animate-pulse"></span>
{/snippet}
```

AppNavButton needs `relative` added to its class for absolute positioning.

### 0f: Fraud Signals Utility

**New file:** `src/lib/utils/fraudSignals.ts`

Authorize.Net AVS result codes (A, B, E, G, N, P, R, S, U, W, X, Y, Z) and CVV codes (M, N, P, S, U) mapped to:
- Human-readable label
- Risk level: `'low' | 'medium' | 'high'`

Pure functions, unit-testable.

---

## Phase 1: Held Transaction Review (requires Slice 6)

### 1a: Tauri Commands (Rust)

**New file:** `src-tauri/src/commands/payments.rs`

```rust
pub async fn list_held_transactions(...) -> Result<Vec<HeldTransactionDto>, String>
pub async fn approve_held_transaction(id: i32, ...) -> Result<(), String>
pub async fn decline_held_transaction(id: i32, ...) -> Result<(), String>
pub async fn get_held_count(...) -> Result<u32, String>
```

**Modify:** `src-tauri/src/commands/mod.rs` (add `pub mod payments`), `src-tauri/src/lib.rs` (register in `generate_handler!`)

### 1b: Frontend Commands

**Modify `src/lib/api/commands.ts`:**

```typescript
export function listHeldTransactions(): Promise<HeldTransactionDto[]>
export function approveHeldTransaction(id: number): Promise<void>
export function declineHeldTransaction(id: number): Promise<void>
export function getHeldCount(): Promise<number>
```

### 1c: Held Transactions ViewModel

**New file:** `src/lib/components/heldTransactions.svelte.ts`

State: `transactions`, `loading`, `error`, `actionLoading` (id being acted on)
Methods: `fetch()`, `approve(id)`, `decline(id)`
On approve/decline: remove from list optimistically, fire success toast.

### 1d: Held Payment Poller

**New file:** `src/lib/components/heldPaymentPoller.svelte.ts`

Polls `getHeldCount()` every 15s with jitter (same pattern as `epochPoller.svelte.ts`). Callbacks: `onCountChange(count)`.

**Wire in `(app)/+layout.svelte` onMount** (after auth resolved):
- Start poller
- On count increase: fire warning toast ("N payment(s) held for review")
- Login check: one-shot `getHeldCount()`, toast if > 0
- Store count in layout state, pass to badge

### 1e: HeldTransactionCard Component

**New file:** `src/routes/(app)/payments/_components/HeldTransactionCard.svelte`

Card layout (Panel, elevated):
- **Header:** Total amount (large, via `formatPrice`), card type + last four, timestamp
- **Booking context:** Guest name, party size, product (needs product lookup or name in DTO), date/time, booking status badge
- **Fraud signals:** AVS result + CVV result (via `fraudSignals.ts` utility), color-coded risk indicators
- **Actions:** "Approve" (ActionButton success, gated to sys_mod), "Decline" (ActionButton danger, gated to sys_mod). Disabled while `actionLoading`.

### 1f: Needs Review Tab

Wire into `src/routes/(app)/payments/+page.svelte`:
- Mount `heldTransactionsVM`, fetch on mount
- Render `HeldTransactionCard` for each transaction
- Empty state: "No transactions held for review" with checkmark

---

## Phase 2: Transaction History + BookingDetail (requires Slice 6)

### 2a: Tauri Command

**Add to `src-tauri/src/commands/payments.rs`:**
```rust
pub async fn list_booking_payments(booking_uuid: String, ...) -> Result<Vec<PaymentTransactionDto>, String>
```

**Add to `commands.ts`:**
```typescript
export function listBookingPayments(bookingUuid: string): Promise<PaymentTransactionDto[]>
```

### 2b: BookingPayments ViewModel

**New file:** `src/lib/components/bookingPayments.svelte.ts`

State: `selectedBooking`, `transactions`, `loading`, `error`
Methods: `loadForBooking(uuid)`, `clear()`

### 2c: Transaction History Tab Components

**New files in `src/routes/(app)/payments/_components/`:**

- `TransactionHistoryTab.svelte` — Booking search (reuse date/email search pattern from command center header), results filtered to paid bookings only, click to drill in
- `PaymentBookingRow.svelte` — Booking row with payment summary: guest name, time, total, payment status badge
- `TransactionTimeline.svelte` — Per-booking transaction history as a timeline: each row shows transaction type badge, status badge, amount, card info, timestamp. "Cancel & Refund" button if charge is approved and booking is active.

### 2d: BookingDetail Payment Section

**Modify `src/lib/components/BookingDetail.svelte`:**

Add "Payment" section (conditional on `booking.payment`):
- Status badge, total via `formatPrice`, card type + last four
- "View History" link → navigates to `/payments` with booking pre-selected

### 2e: Cancel Booking Command

**Add to `src-tauri/src/commands/bookings.rs`:**
```rust
pub async fn cancel_booking(uuid: String, ...) -> Result<BookingDto, String>
```

Wraps `PATCH /v1/bookings/{id}/status` → Cancelled. Server handles payment reversal automatically.

**Note:** Requires Rust SDK to have `cancel_booking` or `update_booking_status` method. Verify SDK coverage.

---

## Phase 3: Refund Flow

### 3a: RefundConfirmModal

**New file:** `src/routes/(app)/payments/_components/RefundConfirmModal.svelte`

Uses existing modal pattern (`data-overlay`, backdrop click, Escape).
- Warning icon + booking summary (guest, product, amount)
- Clear text: "Cancelling this booking will void or refund the payment to the original card."
- "Cancel & Refund" (ActionButton danger) + "Keep Booking" (ActionButton neutral)
- Loading state while processing

### 3b: Wire Refund Action

In `TransactionTimeline.svelte`: "Cancel & Refund" button opens `RefundConfirmModal`. On confirm, calls `cancelBooking(uuid)`. On success: toast + refresh transaction list.

---

## File Summary

```
NEW FILES:
  src/lib/toastContext.svelte.ts
  src/lib/components/ToastContainer.svelte
  src/lib/components/ToastItem.svelte
  src/lib/components/heldTransactions.svelte.ts
  src/lib/components/heldPaymentPoller.svelte.ts
  src/lib/components/bookingPayments.svelte.ts
  src/lib/icons/PaymentIcon.svelte
  src/lib/utils/fraudSignals.ts
  src/routes/(app)/payments/+layout.svelte
  src/routes/(app)/payments/+page.svelte
  src/routes/(app)/payments/_components/HeldTransactionCard.svelte
  src/routes/(app)/payments/_components/TransactionHistoryTab.svelte
  src/routes/(app)/payments/_components/PaymentBookingRow.svelte
  src/routes/(app)/payments/_components/TransactionTimeline.svelte
  src/routes/(app)/payments/_components/RefundConfirmModal.svelte
  src-tauri/src/commands/payments.rs

MODIFIED FILES:
  src/lib/types.ts                         — payment types + BookingDto.payment field
  src/lib/api/commands.ts                  — payment + cancel commands
  src/lib/components/statusBadge.svelte.ts — transaction domains
  src/lib/components/StatusBadge.svelte    — transaction props union
  src/lib/components/nav/AppNavButton.svelte — badge snippet prop
  src/lib/components/BookingDetail.svelte  — payment section
  src/routes/(app)/+layout.svelte          — nav item, toast, held poller, badge
  src-tauri/src/commands/mod.rs            — payments module
  src-tauri/src/commands/bookings.rs       — cancel_booking command
  src-tauri/src/lib.rs                     — register new commands
```

## Verification

- **Phase 0:** `npm run build` passes. Toast renders and auto-dismisses. Route navigates. Badge animates.
- **Phase 1:** Held list loads via Tauri IPC. Approve/decline round-trips to server. Badge reflects count. Toast fires on login.
- **Phase 2:** Booking search filters to paid bookings. Transaction timeline renders. BookingDetail shows payment.
- **Phase 3:** Refund modal confirms. Cancellation succeeds. Transaction list refreshes showing void/refund.
- **All phases:** `/review-ts` on Svelte/TS. `/review-rs` then `cargo clippy` on Rust commands.
