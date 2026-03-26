# Structured Data Directory

Shared reference data that multiple skills need but no single skill owns.

## What belongs here

- Business identity data referenced by multiple skills (e.g., canonical NAP, site URL)
- Cross-cutting reference tables not tied to a specific skill's lifecycle

## What does NOT belong here

- **Skill-owned configs** — stay co-located in `.claude/skills/<name>/` (e.g., `seo.json`, `discoverability.json`)
- **Branch-specific design specs** — `route-map.json`, `command-center.json`, `concurrency.json` now live here. Previously at monorepo root, moved 2026-03-19.
- **Prose documentation** — stays in `docs/` proper (e.g., `Architecture.md`, style guides)
