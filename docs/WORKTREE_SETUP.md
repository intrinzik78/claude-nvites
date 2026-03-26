# Worktree Setup

This project uses git worktrees to isolate work on different surfaces and the server. Worktrees are fluid — create and destroy as needed — but the branch names and directory convention are stable.

## Convention

Worktrees live at `../worktrees/` relative to the monorepo root. Each worktree tracks a named branch that maps to a `handoffs/` subdirectory and a `NEXT.md` section.

| Branch | Path | Purpose |
|--------|------|---------|
| `server` | `../worktrees/server` | Rust server, API, database |
| `surface-command-center` | `../worktrees/surface-command-center` | Tauri staff desktop app |
| `surface-website` | `../worktrees/surface-website` | SvelteKit public website |

## Creating worktrees from a fresh clone

From the monorepo root on the `dev` branch:

```bash
mkdir -p ../worktrees

git worktree add ../worktrees/server server
git worktree add ../worktrees/surface-command-center surface-command-center
git worktree add ../worktrees/surface-website surface-website
```

If the branches don't exist yet (first clone), create them from dev:

```bash
git branch server dev
git branch surface-command-center dev
git branch surface-website dev
```

Then run the `git worktree add` commands above.

## Integration flow

Worktree branches merge into `dev` via the `/integrate` skill (run from dev in the monorepo root). After merging, all worktrees are fast-forwarded to dev so every branch stays in sync. Never merge worktree branches directly into each other.

## Adding or removing worktrees

```bash
# Add a new worktree
git worktree add ../worktrees/<name> <branch>

# Remove a worktree
git worktree remove ../worktrees/<name>

# Clean up stale worktree references (if directory was manually deleted)
git worktree prune
```
