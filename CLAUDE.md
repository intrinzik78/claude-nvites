# CLAUDE.md

Run `/orient` at session start.

Build: `cd server && cargo xtask build-all` — api-contracts → schema-emitter → dist/openapi.json → server (include_str!). api-contracts type changes are contract changes.

## Anti-patterns
- **working outside the current working directory tree** - explicitly ask for permission to do work in other directory trees, worktrees or repo branches.
- **commiting docs/ or archive/ dirs** - these folders are symlinked from another repo. they can't be committed here. remind the user during handoff if there are uncommited files there.
- **reading the .env file** - .env is not in the repo, dotenvy will traverse the tree to find it, but it's outside the monorepo for security. ask if you need a value, don't search for or read .env files if you ls them naturally.