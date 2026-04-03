# Dispatch: Fix explicit_auto_deref clippy warnings in cached_link.rs tests

**Date:** 2026-04-02
**Workstream:** dev

## Problem

4 `clippy::explicit_auto_deref` warnings in `cached_link.rs` integration tests (lines 248, 274, 299, 324). All are `&mut *tx` where `&mut tx` suffices. Harmless but noisy — they appear on every `cargo clippy --tests` run.

## Suggested Solution

Replace `&mut *tx` with `&mut tx` in the 4 `seed_link()` call sites.

## Confidence

**High** — trivial mechanical fix, clippy provides the exact replacement.
