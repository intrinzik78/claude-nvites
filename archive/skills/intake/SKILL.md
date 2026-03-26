---
name: intake
description: Project intake. Asks key questions and generates a starter project-schema.json. Run when setting up a new project.
---

# Intake — Project Schema Generator

Generate a `project-schema.json` for a new project by asking the essential questions. This captures what you know on day 1. Contracts, risks, and detailed evidence evolve later through development (maintained by `/GUARDIAN`).

## Pre-flight

1. Check if `project-schema.json` already exists in the project root.
   - If yes: warn the user and ask whether to **overwrite**, **back up and overwrite** (rename existing to `project-schema.backup.json`), or **abort**.
   - If no: proceed.

2. Read `docs/project-schema.template.json` (from the shared config) as structural reference. If not found, use the schema structure defined below.

## Intake Rounds

Ask questions via `AskUserQuestion`. Keep it conversational — 2-3 rounds, not an interrogation. Use free-text options where the user needs to describe things in their own words.

### Round 1: Project Identity

Ask these questions (adapt phrasing to feel natural):

1. **What does this project do?** — One sentence. This becomes `project.intent`.
2. **What's the tech stack?** — Languages, frameworks, database, deployment target. Offer common stacks as options with an "Other" escape. This becomes `project.orientation`.
3. **How is the repo structured?** — Monorepo vs multi-repo, major directories, branch strategy. This becomes `structure.repo`.

### Round 2: Components & Architecture

Based on Round 1 answers:

1. **What are the major components?** — List the crates, packages, or services. For each: name and one-line description. This becomes `structure.crates`.
2. **How do they relate?** — Ask for the mental model. "Server is the platform, frontends are consumers" or "microservices behind a gateway" etc. This becomes `structure.mental_model`.
3. **Are there distinct apps or surfaces?** — End-user-facing applications. For each: name, what it does, distribution targets (web, desktop, mobile). This becomes `surfaces`. If there's only one surface (e.g. a single web app), that's fine — capture it.

### Round 3: Principles & Unknowns

1. **What are 2-3 rules that should never be broken?** — Architectural or design non-negotiables. For each, also ask: "How would you know if this rule was broken?" These become `principles` with `origin: "human"`.
2. **What questions are already on your mind?** — Things you know you don't know yet. Technical decisions deferred, unknowns about requirements, architectural choices not yet made. These become `open_questions`.

## Schema Generation

After collecting answers, generate `project-schema.json` with this structure:

```json
{
  "version": "1.0",
  "project": {
    "intent": "<from round 1>",
    "orientation": "<from round 1>"
  },
  "principles": [
    {
      "id": "<kebab-case-derived-from-statement>",
      "statement": "<the rule>",
      "violation": "<how to detect breach>",
      "origin": "human"
    }
  ],
  "platform": {
    "components": ["<platform-level components from round 2>"],
    "capabilities": {}
  },
  "structure": {
    "repo": "<from round 1>",
    "crates": {
      "<name>": "<description>",
    },
    "docs": {},
    "mental_model": "<from round 2>"
  },
  "surfaces": [
    {
      "id": "<short-id>",
      "crate": "<crate-or-package-name>",
      "intent": "<what it does>",
      "distribution": { "web": false, "desktop": [], "mobile": [] }
    }
  ],
  "contracts": [],
  "risks": [],
  "open_questions": ["<from round 3>"]
}
```

**Rules for generation:**
- Principle IDs: derive `kebab-case` from the core concept (e.g. "Never expose internal APIs" → `internal-api-isolation`)
- All principles get `origin: "human"` — these are the founder's rules
- `contracts` and `risks` are empty arrays — they evolve through development
- `platform.capabilities` is an empty object — grows as features are built
- `structure.docs` is an empty object — tracked as docs are created
- Surface IDs: short, lowercase (e.g. `web`, `mobile`, `admin`, `dashboard`)
- Remove all `_tier` and `_guide` metadata from the template — the output is clean JSON

## Output

1. Write `project-schema.json` to the project root.
2. Print a summary:
   - What was captured (intent, component count, principle count, surface count, open question count)
   - What evolves later: "Contracts, risks, and evidence are populated through development. Use `/GUARDIAN` to maintain the schema as the project grows."
3. Suggest next steps: "Run `/orient` at session start to load the schema into context."

$ARGUMENTS
