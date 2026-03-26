---
name: dispatch
description: Create a dispatch file in docs/dispatches/. Use when directing future work to a branch/worktree — features, blocking changes, or tasks to pick up later.
---

# Dispatch

Create a dispatch in `docs/dispatches/`. Dispatches are the user's "I'll need this later" tool — a recognized task, feature, or blocking change directed at a specific workstream.

## Invocation

`/dispatch <target> <description>`

- `<target>` — branch/worktree name or prefix shorthand (see table)
- `<description>` — natural language description of the work

Example: `/dispatch server update the dispatch skill with the new workflow`

## Prefix Map

| Target | Prefix | Branch / worktree |
|--------|--------|-------------------|
| `dev` | `DEV_` | dev |
| `server` | `SERVER_` | server |
| `website` | `WEBSITE_` | surface-website |
| `command` | `COMMAND_` | surface-command-center |
| `tako` | `TAKO_` | cli-tako |

## Steps

### 1. Resolve filename

Map `<target>` to its prefix. Derive a short `SCREAMING_SNAKE` task name from the description.

Result: `docs/dispatches/{PREFIX}_{TASK_NAME}.md`

Example: `/dispatch server update the dispatch skill` → `docs/dispatches/SERVER_DISPATCH_SKILL.md`

### 2. Draft

Spawn a **sonnet subagent** to draft the dispatch. The subagent should:

- Use conversation context and the user's description to write the dispatch
- Keep it tight — this is a note for a future agent, not a design doc
- Use this format:

```markdown
# Dispatch: <one-line title>

**Date:** YYYY-MM-DD
**Workstream:** <target branch>

## Problem

<What needs to happen and why. 1-3 sentences.>

## Reasoning

<Why this matters now, dependencies, constraints, relevant decisions (DEC-### refs if applicable). 2-5 bullets max.>

## Proposed Solution

<Concrete approach if known. Name files, types, endpoints. If no solution is obvious, say so — the receiving agent will figure it out.>

## Confidence

**High/Medium/Low** — <one line explaining the confidence level>
```

**Rules:**
- Under 50 lines total. This is a dispatch, not a design doc.
- Omit Proposed Solution if genuinely unknown — the section header too.
- Omit Reasoning if the problem statement is self-explanatory.
- Include only what the receiving agent needs to start. No filler.

### 3. Present and write

Show the draft. Ask: **"Write this, or adjust?"**

On confirmation, write to `docs/dispatches/`. Dispatches are committed to the repo — they're visible to any branch that merges dev.

## Rules

- **Multiple dispatches per target are fine.** Each dispatch is its own file. They accumulate until the receiving agent acts on them.
- **Dispatches are consumed by `/handoff`** — the handoff skill archives or removes completed dispatches.
- **Dispatches are committed**, not gitignored. They travel with the repo.
- **No exploration.** The sonnet subagent drafts from conversation context only — no git log, no file reads, no research. The user knows what they want; write it down fast.

$ARGUMENTS
