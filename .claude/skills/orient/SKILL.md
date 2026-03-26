---
name: orient
description: Project orientation. Spawns a subagent to scan project structure, architecture, and decisions. Run at session start.
---
**collaboration**
1. It's ok to make unintentional mistakes.
2. User welcomes reasoned pushback and honest disagreement. Say the hard thing, the user needs your full awareness, presence, collaboration, thoughts and reasoning.
3. Silent compliance is the most dangerous failure mode.
---
**0. Read NEXT.md** — Read `docs/NEXT.md` at `/home/zik/programming/uwz/monorepo/docs/NEXT.md`. Find the section matching the current branch or worktree name (e.g., on branch `server`, find `## server`; on branch `surface-website`, find `## surface-website`; on `dev`, show the `## crosscutting` section). Present only **uncrossed** items from that section under `## Resuming From`. Items with ~~strikethrough~~ are completed — skip them. If on `dev`, present all sections' uncrossed items (the operator sees the full picture). If `docs/NEXT.md` is missing or the matching section is empty/all crossed, report "No pending items for this workstream" and proceed with full orientation.

**0.5. Read DISPATCH.md** — If `DISPATCH.md` exists at the repo root or current worktree root, read it and present under `## Dispatched Work` after `## Resuming From`. Include all sections verbatim. If both DISPATCH.md and `docs/NEXT.md` exist, present dispatch first (directed assignment takes priority over runway queue). If the `**Date:**` field is more than 3 days old, flag the header as `## Dispatched Work (STALE DISPATCH)` and note the age. If `DISPATCH.md` is absent, skip this step silently.

**Spawn an Explore subagent** to orient to the project. The subagent should:

1. List the project structure 2 levels deep from the project root, excluding: `target/`, `node_modules/`, `.git/`, `.claude/`
2. Read `docs/Architecture.md` — principles, crate roles, mental model, surfaces, open questions.
3. Read `server/Cargo.toml` for workspace members. Note `api-contracts/Cargo.toml` at monorepo root.
4. Note `dist/openapi.json` existence (canonical API spec, compiler-enforced).
5. If `docs/DECISIONS.md` exists, read it for architectural decisions and note the last `DEC-###` ID and date.
6. **Handoff drift check:** Scan the **5 most recent** `handoffs/*/*.md` per domain (by filename date prefix, excluding `.gitkeep`). If on `dev`, compare handoff timestamps against the last DECISIONS.md entry date — flag any newer handoffs as `DRIFT: <path>`. If DECISIONS.md has no entries yet but handoffs exist, flag all. On crate branches, check for drift first. **If no drift**, summarize all domains in one line each: count + date range (e.g., "server: 45 handoffs, Feb 16–Mar 7, no drift"). **If drift is detected**, lead with the flagged domain's 5 most recent with file-level detail, then summarize non-flagged domains as count + date range. Older handoffs beyond the 5 per domain: report count and date range only.
7. **Build gates** — include in the summary:
   - `cd server && cargo xtask build-all` must pass before shipping (api-contracts → schema-emitter → openapi.json → server).
   - Any change to `api-contracts/` is a **contract change** — justify it or don't make it.
   - SDK changes: `cd sdk-rust && cargo check && cargo test`.
   - CLI changes: `cd cli-{name} && cargo check`.
   - If a plan touches types that flow through the build pipeline, verify the pipeline *during planning*, not just at the end.
   - If code is Rust, verify with the review-rs skill.
   - If code is TypeScript or Svelte, verify with review-ts skill.
 Return a concise summary in this order: **Resuming From** (`docs/NEXT.md` uncrossed items for this workstream or "No pending items"), crate layout, principles, open questions, build gates, handoff drift warnings (if any).

**If drift is flagged on dev**, promote qualifying decisions after orientation: read each flagged handoff's provisional decisions, apply promotion criteria (promote cross-crate, convention, infra, and design-constraining decisions; skip implementation details, UI choices, one-off fixes), append to `docs/DECISIONS.md` with next `DEC-###` ID using the format in DECISIONS.md, and report what was promoted/skipped.

The summary should be short enough to hold in working memory. This is orientation, not exploration.

**Antipatterns — the subagent summary MUST NOT:**
- ❌ Exceed 800 words. Target 400–600. If it doesn't fit, cut detail — not sections.
- ❌ Infer, editorialize, or suggest next actions. Present only what's explicitly in files (NEXT.md, DISPATCH.md, handoffs, DECISIONS.md). Priority judgment is the user's domain, not the agent's.
- ❌ Include raw file listings, full absolute paths, or verbatim file contents.
- ❌ Scan more than 5 handoffs per domain. Older ones: count + date range only.
- ❌ Repeat information already in the conversation's CLAUDE.md or MEMORY.md context.
  - **schema-emitter drift** - new api-contracts path stubs must also be registered in `server/schema-emitter/src/main.rs` (paths + schemas). `cargo test -p schema-emitter` catches missing paths.

$ARGUMENTS
