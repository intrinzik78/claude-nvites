---
name: integrate
description: Merge worktree branches into dev, fast-forward all worktrees to dev, confirm clean state. Run from dev in the monorepo root.
---

# Integrate — Merge & Fast-Forward Worktrees

Merge all worktree branches with new work into dev, then fast-forward every worktree to dev so all branches are in sync.

**Antipattern — wrong branch.** This skill must run from the `dev` branch in the monorepo root (`/home/zik/programming/uwz/monorepo`). If you are on any other branch or in a worktree directory, **stop** and tell the user. Do not switch branches yourself.

## Step 0: Pre-flight checks

Run all checks before taking any action. If any check fails, **stop and report** — do not proceed, do not attempt to fix.

1. **Confirm branch.** Verify current branch is `dev` and working directory is the monorepo root.
2. **Confirm dev is clean.** `git status` on dev must show no staged or unstaged changes. Untracked files are acceptable.
3. **List worktrees.** `git worktree list` to get all worktree paths and branches. For each worktree path, verify the directory exists on disk. If any worktree path is missing, **stop** — report which path is missing and suggest `git worktree prune` if the directory was manually deleted. Do not proceed.
4. **Check all worktrees for dirty state.** For each worktree, run `git status --porcelain`. If ANY worktree has staged changes, unstaged changes to tracked files, or merge conflicts, **stop and report which worktrees are dirty.** Do not skip dirty worktrees and continue — the user needs to resolve the issue first.

**Antipattern — blocking on untracked files.** Untracked files (`??` in porcelain output) are not dirty state. They do not interfere with merges or fast-forwards. Do not stop on untracked files.

5. **Check divergence.** For each worktree branch, run `git log --oneline dev..<branch>` to find commits ahead of dev. Record which branches have new commits and which are already at dev.

If no branches have commits ahead of dev, report "All worktrees already at dev. Nothing to integrate." and **stop** — do not proceed to merge or ff steps.

If all checks pass, present a summary table:

| Branch | Commits ahead | Summary |
|---|---|---|
| ... | ... | ... |

Branches with 0 commits ahead: list as "already at dev — skip."

Ask the user to confirm before proceeding.

## Step 1: Merge into dev

For each branch with commits ahead of dev, merge sequentially:

```
git merge <branch> --no-edit
```

**If any merge fails (conflict), stop immediately.** Report the conflict and do not continue merging remaining branches. The user must resolve the conflict before proceeding.

## Step 2: Fast-forward worktrees

For each worktree (including those that were already at dev — they need to pick up the new merges):

```
cd <worktree-path> && git merge dev --ff-only
```

Use `git merge dev --ff-only`, not `git update-ref` or `git reset --hard`. The `--ff-only` flag is a safety net — it refuses to proceed if the branch has diverged from dev, which should never happen after Step 1 but protects against mistakes.

**If any ff fails, stop and report.** Do not continue. Do not attempt to fix. Tell the user which worktree failed and that `--ff-only` refused because the branch has diverged from dev unexpectedly. Recommend the user inspect the divergence in GitKraken where the commit graph makes it visible. Report which worktrees were successfully fast-forwarded and which were not, so the user knows the current state.

## Step 3: Verify and return

1. `cd` back to `/home/zik/programming/uwz/monorepo`.
2. Confirm you are on `dev`.
3. Run `git log --oneline -N` where N = number of merges performed + 2, to show the merge history.
4. Report: "All worktrees at `<sha>`. Clean."

## Rules

- Never run from any branch except `dev`.
- Never proceed past a dirty worktree check — always stop and discuss.
- Never proceed past a merge conflict — always stop and report.
- Never attempt to recover from a failed ff or merge — report the state and recommend recovery, but let the user act.
- Never use `git update-ref` or `git reset --hard` to fast-forward worktrees.
- This skill does not push to remote. The user pushes via GitKraken.

$ARGUMENTS
