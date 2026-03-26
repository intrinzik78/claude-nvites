---
name: dispatch
description: Optional. Deliver cross-cutting context to a worktree that the agent can't discover from files alone. Run from dev before opening a worktree session.
---

# Dispatch — Primary-to-Worktree Assignment

Dispatch a directed assignment to a worktree. This creates a `DISPATCH.md` file that the worktree agent reads at `/orient`, giving it curated context instead of cold-starting.

Use dispatch when you have context the agent can't find in the repo — customer feedback, requirements changes, observations from testing, cross-cutting decisions that affect the workstream.

## Invocation

`/dispatch <target> "<priority description>"`

- `<target>` — worktree name (e.g., `surface-website`, `server`, `cli-tako`, `surface-command-center`)
- `<priority description>` — one-line task description

Example: `/dispatch surface-website "Build /gallery page with album grid and lightbox"`

## Step 0: Validate

1. **Branch check:** Confirm you are on `dev`. If not, stop — dispatch runs from dev because the primary thread has cross-cutting context. Tell the user to switch to dev first.
2. **Target resolution:** Resolve the target name to a path:
   - `<target>` → `/home/zik/programming/uwz/worktrees/<target>/DISPATCH.md`
   - If the worktree directory does not exist, stop and tell the user. Do not create directories.
3. **Existing dispatch:** If a `DISPATCH.md` already exists at the target path, note this — the new dispatch will overwrite it. Mention the existing dispatch title to the user so they're aware.

## Step 1: Gather Context

Two tool calls — no subagent:

1. **Git history** — Run `git -C /home/zik/programming/uwz/worktrees/<target> log --oneline -5` to see recent commits. Flag any that overlap with the priority description.
2. **Latest handoff** — Read the most recent handoff from `handoffs/<target>/` (or `handoffs/<target-domain>/`). Extract open questions, blockers, and unblocks relevant to the priority.

### After gathering

1. **Evidence check** — Review the git history and handoff signals. If the work appears already done or substantially complete, **stop and tell the user** what you found — don't write a dispatch for shipped work. If partially done, narrow the priority description to what remains.
2. **Conversation context** — Add relevant decisions, discoveries, or constraints from the current conversation that aren't captured in handoffs. Only the main thread has this context.
3. **Curate** — Select the 2-5 most relevant signals for the Context section. Discard the rest.

**Antipattern — dispatching shipped work.** If commits or handoffs show the priority is already done, don't write the dispatch. Tell the user what you found. This is the most wasteful failure mode — an agent spends a full session rediscovering completed work.

**Antipattern — context dump.** The Context section should have 2-5 bullets. If you're writing more than 5, you're including things the agent doesn't need. Curate ruthlessly.

## Step 2: Assemble Draft

Build the DISPATCH.md using this format:

```markdown
# Dispatch: <one-line title>

**Date:** YYYY-MM-DD
**From:** dev
**Workstream:** <target>

---

## Priority

<Specific task. Name files, types, endpoints, components. One paragraph max.>

## Context

<2-5 bullets of relevant recent signals — DEC-### references, handoff
discoveries, unblocks from other workstreams. Only what matters for the
priority task.>

## Dependencies

- BLOCKED: <what this workstream is waiting on>
- BLOCKING: <what others are waiting on from this workstream>

## Quality Gates

<Completion criteria beyond standard build gates.>
```

**Rules for assembly:**
- Priority is singular — one task, not a menu.
- Omit Dependencies section if there are none.
- Omit Quality Gates section if standard build gates suffice (`cargo xtask build-all`, `pnpm check`).
- Keep the total document under 40 lines. This is a dispatch, not a design doc.

## Step 3: Present for Confirmation

Show the complete draft to the user. Ask:

> "Draft dispatch for **<target>**. Write this, or adjust?"

Wait for confirmation. If the user wants changes, adjust and re-present.

## Step 4: Write

Write the confirmed dispatch to the resolved target path.

## Rules

- **Dev only.** This skill runs from the dev branch. Dispatching from a worktree means stale context.
- **One dispatch per target.** A new dispatch overwrites the previous one. Dispatch is a current assignment, not a queue.
- **Does not start sessions.** The user opens the worktree terminal separately.
- **Ephemeral.** DISPATCH.md is consumed by `/handoff` (deleted after acknowledgment). It is not a persistent record — the handoff is.
- **DISPATCH.md is gitignored.** Never stage or commit it.

$ARGUMENTS
