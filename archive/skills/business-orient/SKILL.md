---
name: business-orient
description: Business workspace orientation. Scans business content and code context, returns a concise summary. Run at session start in business workspaces.
---

**Read CLAUDE.md** at the project root. Extract: workspace name, key references listed. Note any workspace-specific rules.

**Spawn two Explore subagents in parallel** (use the Task tool with `subagent_type: "Explore"`):

### Subagent 1: Business Content & Schema

**Business Schema:** Read `business-schema.json` at the project root. If it exists:
- Report claim count by confidence level (validated/supported/assumed/challenged/untested)
- Flag any `challenged` claims (these need attention)
- Flag any claims with undated external evidence or evidence >90 days old
- Cross-reference: for each claim with `refs`, check if the referenced principle or crate role exists in `docs/Architecture.md`. Report any mismatches (missing refs, business `validated` depending on code `unbuilt`).
- List open questions from the schema

If `business-schema.json` does NOT exist, report: "No business schema found. Run `/business-GUARDIAN` to initialize."

**Content Directories:** Scan these directories at the project root if they exist: `strategy/`, `research/`, `users/`.

For each directory:
- If it contains files (excluding `.gitkeep`): summarize each file in 1-2 sentences — what it covers, key conclusions or open questions.
- If it is empty or only has `.gitkeep`: report it as empty and suggest what belongs there:
  - `strategy/` — product positioning, competitive analysis, pricing, go-to-market plans. Use `/business-strategy` to generate.
  - `research/` — market research, user interviews, industry analysis, competitor teardowns. Use `/business-competitor` to generate.
  - `users/` — personas, journey maps, pain points, feedback synthesis. Use `/business-persona` to generate.

If total content exceeds 500 lines across all files, switch to synopsis mode: first 50 lines per file plus topic clusters. Keep total output under 60 lines.

### Subagent 2: Code & Docs Context

Read-only scan. Do NOT use Edit or Write tools.

1. **docs/**: Scan `docs/` directory. Summarize each document in 1 sentence, grouped by business relevance (high/medium/low). High = vision, product spec, UX. Medium = architecture, build plan. Low = pure implementation details.
2. **Architecture**: Read `docs/Architecture.md`. Extract: product intent, principles (name + 1-line each), business-relevant contracts (anything touching user-facing behavior, data model, or API surface). Skip pure implementation contracts. Report open questions.
3. **DECISIONS.md**: Read `DECISIONS.md` if it exists. List only business-relevant decisions (product scope, user-facing features, data model choices). Skip pure refactoring/tooling decisions.

Keep total output under 60 lines.

**Assemble summary** from both subagents into a single orientation block (~100 lines max). Follow this structure (output as markdown, not a code block):

**## Business Orientation** — then sections for:
- **Product Identity** — 1-3 lines from schema intent + CLAUDE.md context
- **Claim Health** — confidence distribution, challenged claims listed, stale evidence flagged, cross-reference mismatches. If no schema: "No business schema. Run `/business-GUARDIAN` to initialize."
- **Business Content** — status of strategy/, research/, users/ (empty with suggestions, or file summaries)
- **Technical Context (Business-Relevant)** — high-relevance docs (1 line each), business-relevant decisions, user-facing contracts grouped by confidence, open questions from both schemas
- **Suggested Next Steps** — 3 concrete suggestions based on gaps or content state. Prioritize: challenged claims, empty directories, stale evidence.

Suggestions should be actionable and specific to the workspace's current state.

$ARGUMENTS
