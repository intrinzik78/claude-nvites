---
name: orient
description: Project orientation. Reads dispatches, architecture, recent handoffs, and decision frontier. Run at session start.
---
**collaboration**
1. It's ok to make unintentional mistakes.
2. User welcomes reasoned pushback and honest disagreement. Say the hard thing, the user needs your full awareness, presence, collaboration, thoughts and reasoning.
3. Silent compliance is the most dangerous failure mode.
---

Run all steps inline (no subagent). Present a single summary under `## Orientation` when done.

**1. Dispatches** — Use `ls docs/dispatches/` (not Glob — `docs/` is a symlink) to list dispatch files. Match by prefix for the current branch/worktree:

| Prefix | Branch / worktree |
|--------|-------------------|
| `DEV_` | dev |
| `SERVER_` | server |
| `WEBSITE_` | surface-website |
| `COMMAND_` | surface-command-center |
| `TAKO_` | cli-tako |

If matches exist, read them and present under `### Dispatched Work`. Include all sections verbatim. If a dispatch's `**Date:**` field is more than 3 days old, flag it as `(STALE)` and note the age. If no matching dispatches are found, skip this section silently.

**1b. Cross-worktree dispatches (dev only)** — If on the `dev` branch, send all non-matching dispatch files to a sonnet subagent. The subagent should read each file and return one line per dispatch: filename, what it's queued for, and any noted blockers. Present under `### Other Worktree Dispatches`. Skip this step on worktree branches.

**2. Recent commits** — Run `git log --stat -3` to see what landed recently. Note the scope (which crates/surfaces changed) in 1-2 sentences.

**3. Decision frontier** — Run `tail -20 docs/DECISIONS.md` to get the last 2-3 decisions. Note the last `DEC-###` ID and date.

**4. Architecture** — Read `docs/Architecture.md` in full. This is the project's north star — load it every session.

**5. Recent handoffs** — Find the 5 most recent `handoffs/*/*.md` files by filename date prefix (across all domains, not per-domain). Exclude `.gitkeep`. Read them and summarize key discoveries, concerns, and unblocks in ≤400 words. Do not editorialize or suggest next actions — present what's in the files.

**6. `--drift` flag (opt-in)** — Only when invoked as `/orient --drift`:

Scan the **5 most recent** `handoffs/*/*.md` per domain. Compare handoff dates against the last DECISIONS.md entry date. Flag any newer handoffs as `DRIFT: <path>`. For flagged handoffs, read their provisional decisions and apply promotion criteria:
- **Promote:** cross-crate conventions, infra decisions, design-constraining choices
- **Skip:** implementation details, UI choices, one-off fixes

Append qualifying decisions to `docs/DECISIONS.md` with next `DEC-###` ID. Report what was promoted and what was skipped.

---

**Antipatterns:**
- Do not infer, editorialize, or suggest next actions. Priority judgment is the user's domain.
- Do not repeat information already in CLAUDE.md or MEMORY.md.
- Keep the summary concise. This is orientation, not exploration.

$ARGUMENTS
