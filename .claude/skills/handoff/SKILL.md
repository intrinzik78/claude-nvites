---
name: handoff
description: Session wind-down. Surfaces the unsaid, writes a handoff document, and commits. Run at end of session.
---

# Handoff — Session Wind-Down

Run this at session end. The handoff captures reasoning, concerns, and forward-looking signals — things git history alone cannot express. Git is the source of truth for *what happened*; the handoff is the source of truth for *intent and judgment*.

## Step 1: Surface the unsaid

Before writing anything, surface observations you wouldn't volunteer unprompted — patterns noticed during the build, concerns about the plan's next phases, doubts about a decision made earlier, things that feel relevant but don't fit a contract or skill check. Say them directly to the user.

Then ask:

> "Anything you'd like to discuss or add before we proceed?"

If the user raises anything substantive, discuss it before proceeding.

## Step 2: Determine handoff location

Check the current branch:
- `dev` → `handoffs/crosscutting/`
- Crate branch → `handoffs/<crate>/` (e.g., `handoffs/server/`)

Filename: `YYYY-MM-DD-<brief-slug>.md`

## Step 2.5: Acknowledge dispatches

Check `docs/dispatches/` for files matching the current branch/worktree using these prefixes:

| Prefix | Branch / worktree |
|--------|-------------------|
| `DEV_` | dev |
| `SERVER_` | server |
| `WEBSITE_` | surface-website |
| `COMMAND_` | surface-command-center |
| `TAKO_` | cli-tako |

For each matching dispatch, add a `## Dispatch Acknowledgment` section to the handoff in Step 3, placed immediately after `## Completed This Session`:

```markdown
## Dispatch Acknowledgment
**Dispatch:** <title from dispatch file>
**File:** <filename>
**Status:** completed | partial | blocked | deferred
**Notes:** <if not completed, what remains and why>
```

After writing the handoff in Step 4 (commit), delete completed dispatch files from `docs/dispatches/`. Leave partial/blocked/deferred dispatches in place. If no matching dispatches exist, skip this step silently.

## Step 3: Write the handoff document

Gather from the conversation and write the handoff. Format:

```markdown
# Handoff: <Title>

**Date:** YYYY-MM-DD
**Branch:** <branch name>
**Commit:** <latest commit hash, if work was committed>

---

## Completed This Session

One-liner referencing the commit range (e.g., `abc1234..def5678`). Do not restate
the diff in prose — git history is the record of what shipped. If context is needed
beyond what the commits convey, keep it to one sentence.

## Discoveries and Concerns

Surprises, edge cases, process observations, technical notes.
Include anything surfaced in Step 1. This is often the highest-value section.

## Unblocks

What this session's work enables for other workstreams. Include interface shapes,
type names, endpoint paths, or other concrete details that the next consumer needs
to proceed without reverse-engineering the code. Shift from prescriptive ("do X next")
to declarative ("X is now possible because Y shipped").

## Open Questions

Unresolved questions that block future work. Attribute to source doc if applicable.

## Provisional Decisions

*Crate branches only.* Decisions discovered this session that need promotion to
`docs/DECISIONS.md` after merge to dev. On dev, write "None — this session was on dev."
```

Omit sections that are genuinely empty (e.g., no open questions). Don't pad.

## Step 4: Commit
Then ask:

> "Do you want to commit just the handoff or all the work done in this session?"

Stage the handoff document and the session work if the user requests it. Commit with a message summarizing what the handoff covers. Do not stage unrelated changes.

The agent does not perform branch integration (merge, rebase, cherry-pick). Do not suggest or ask about merging — on worktree branches, the right process is commit and hold. The orchestrator on dev decides when to merge.

## Rules

- The handoff does not update `docs/Architecture.md` (read-only; `chmod +w` for approved edits).
- The handoff does not update `docs/DECISIONS.md` directly. On crate branches, provisional decisions go in the handoff. On dev, orient handles promotion from handoffs.
- Red team findings from the session are blocking — include them in the handoff if unresolved.
- Keep it concise. The next session reads this cold. Walls of text defeat the purpose.

## Antipatterns
- **Trying ommit files in the docs/ or archive/ directory** - those files are symlinked from another repo and cannot be commited here.
- **Placing handoffs in the wrong worktree** - place handoffs in the wortrktree established at session start.

$ARGUM Torit's wasted cycles.
