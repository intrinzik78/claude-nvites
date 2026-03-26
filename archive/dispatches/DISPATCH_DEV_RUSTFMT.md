# Dispatch: Verify rustfmt edition alignment

**Date:** 2026-03-24
**Branch:** dev
**For:** next dev session

---

## Problem

`rustfmt.toml` at the repo root sets `edition = "2021"`, but several `Cargo.toml` files declare `edition = "2024"`. rustfmt uses its own edition setting (not Cargo.toml) to decide how to parse and format code.

This means rustfmt may be parsing edition-2024 syntax (let-chains, `gen` keyword, etc.) under edition-2021 rules. Today this works by accident because rustfmt is lenient, but it can produce phantom formatting diffs — CI passes locally but fails on a different rustfmt version, or vice versa.

We just landed let-chains (`if let ... && let ...`) and `is_multiple_of()` across the server crate in clippy fixes. Both compiled and formatted cleanly, but the edition mismatch is a latent risk.

## Proposed Solution

1. Update `rustfmt.toml` to `edition = "2024"` (matching the Cargo.toml declarations).
2. Run `cargo fmt` across all 6 crates and verify no unexpected reformatting.
3. If reformatting occurs, inspect the diffs — they should be improvements (edition-2024-aware formatting). Commit them.
4. Verify CI passes.

## Reasoning

- rustfmt edition should match the code's actual edition to avoid parse ambiguity.
- Edition 2024 is what the crates declare and what the compiler uses. rustfmt should agree.
- The fix is one line in `rustfmt.toml` + a formatting pass. Low risk.

## Confidence

High. This is a configuration alignment, not a behavioral change. The only risk is unexpected reformatting, which is cosmetic and easily reviewed.
