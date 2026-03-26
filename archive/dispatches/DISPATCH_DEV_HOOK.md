# Dispatch: Scope pre-commit hook to staged files

**Date:** 2026-03-24
**Branch:** dev
**Status:** Not started

## Problem

The pre-commit hook (`monorepo/.git/hooks/pre-commit`) runs `cargo fmt --check` against every Rust crate unconditionally — regardless of which files are staged. On worktree branches that only touch TypeScript/Svelte, this blocks commits when Rust formatting has drifted from other branches. The developer didn't cause the drift and can't fix it without touching files outside their workstream.

Discovered on `surface-website` (2026-03-24): a pure TS/Svelte commit was blocked by `cargo fmt` diffs in `server/`, `api-contracts/`, and 10+ Rust files. Hook is currently disabled (`chmod -x`) as a workaround.

## Fix

Scope the hook to only check crates that have staged `.rs` files. If no `.rs` files are staged, skip the Rust fmt check entirely.

```bash
# Get list of staged .rs files
STAGED_RS=$(git diff --cached --name-only --diff-filter=ACMR -- '*.rs')
[ -z "$STAGED_RS" ] && exit 0
```

Then for each crate entry, only run `cargo fmt --check` if `$STAGED_RS` contains files under that crate's directory.

## Why not move to CI only

The hook catches fmt errors before they hit CI — that fast feedback loop is valuable on Rust branches. Removing it entirely would mean waiting for CI to catch trivial formatting issues. Scoping it preserves the benefit without the cross-worktree pain.

## Current state

Hook is disabled (`chmod -x monorepo/.git/hooks/pre-commit`) as of 2026-03-24. All worktrees share this hook file — no worktree has a pre-commit check right now. CI still catches fmt issues.

After the fix lands, re-enable: `chmod +x monorepo/.git/hooks/pre-commit`
