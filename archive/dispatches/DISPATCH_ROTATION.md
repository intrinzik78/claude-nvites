# Dispatch: Align cli-tako master password minimum with server

**Date:** 2026-03-20
**Target worktree:** cli-tako

---

## Problem

The server now enforces a 12-character minimum on `MASTER_PASSWORD` at three layers: startup assertion (`env.rs`), encrypt (`to_encrypted_buffer.rs`), and decrypt (`to_decrypted_string.rs`). The rotation endpoint rejects passwords under 12 chars via `ApiPasswordOutOfBounds`.

cli-tako's `secret rotate` command still enforces min 8, max 24 (`cli-tako/api/src/types/commands/secret.rs:162-166`). A user entering a 8-11 character password will pass the CLI validation but get rejected by the server API, producing a confusing error.

## Proposed Solution

Update the minimum in `cli-tako/api/src/types/commands/secret.rs` from 8 to 12:

```rust
// line 162
controller.view.println("[cli] master password must be at least 12 characters");
```

And adjust the comparison accordingly.

## Reasoning

The server is the authority on password bounds. The CLI should match to avoid a validation mismatch where the CLI accepts what the server rejects.

## Additional: Generate master password via CLI

Add a `secret generate-master-password` subcommand (or fold into `secret rotate` with a `--generate` flag) that outputs a random 25-char UUID using the existing `Uuid::web_safe_with_nums` alphabet. Operator pastes it into `.env` / Railway env vars. No dictionary attack surface, ~148 bits of entropy without changing the encryption model.

This is higher-value than the min-length alignment above — it eliminates human-chosen passwords entirely for new deployments and rotations.

## Confidence

Certain. Both items are mechanical — min-length is a one-line change, password generation reuses existing `Uuid` infrastructure.
