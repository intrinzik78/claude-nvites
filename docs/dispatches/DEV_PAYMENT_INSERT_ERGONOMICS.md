# Dispatch: Refactor PaymentTransaction insert signatures to builder or struct

**Date:** 2026-03-28
**Workstream:** dev

## Problem

`PaymentTransaction::insert()` takes 16 parameters and `insert_in()` takes 13. Both have `#[allow(clippy::too_many_arguments)]` suppressing the lint. When subscription CRUD handlers are built, these will be the first call sites — constructing a 16-argument function call is error-prone and hard to review (positional `None::<&str>` arguments for optional fields are especially fragile).

## Suggested Solution

Introduce a `NewPaymentTransaction` struct that collects the required and optional fields, then pass it to `insert()` and `insert_in()`. The struct replaces positional arguments with named fields, making call sites self-documenting and eliminating the clippy suppression.

```rust
pub struct NewPaymentTransaction<'a> {
    pub subscription_id: i32,
    pub anet_transaction_id: Option<&'a str>,
    pub ref_id: Option<&'a str>,
    pub transaction_type: TransactionType,
    pub subtotal_cents: u32,
    pub tax_cents: u32,
    pub total_cents: u32,
    pub status: TransactionStatus,
    // ... optional gateway response fields
}
```

## Reasoning

The style guide prefers builder patterns for complex construction. 16 positional params violates that spirit even though clippy is suppressed. The refactor is low-risk (the methods have zero external callers today) and should happen before subscription handlers introduce call sites that would need to be rewritten.

## Confidence

**High** on the problem, **medium** on the exact shape — the struct design should be driven by the first real call site (subscription charge handler), not speculated now.
