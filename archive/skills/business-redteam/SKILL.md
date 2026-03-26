---
name: business-redteam
description: Challenges business assumptions. Checks every claim and principle in business-schema.json. Cross-checks against code reality. Uses web search for counter-evidence.
---

# Business Red Team

## Input

$ARGUMENTS can specify:
- No args → full schema audit (all claims and principles)
- A specific claim ID → focused challenge of that claim
- "strategy" → red team all strategy/ documents against claims
- A proposed change → challenge that change against the schema

## Process

### 1. Load Context
- Read `business-schema.json` from project root
- Read `docs/Architecture.md` for cross-reference checks
- Read all files in `strategy/`, `research/`, `users/` for supporting/contradicting evidence

### 2. Challenge Every Claim

For each claim in `business-schema.json`:

**Evidence check:**
- Is the evidence real or circular? ("We believe X because we're building for X" is circular.)
- Are external sources dated? Flag undated or >90-day evidence.
- Does the evidence actually support the confidence level?

**Counter-evidence search:**
- Use web search to find contradicting data (competitor moves, market shifts, failed similar products)
- If web search is unavailable, challenge from logic and existing workspace context only

**Cross-reference check:**
- If the claim has `refs` to code contracts, verify those contracts exist
- Check code contract confidence — business assumptions built on unbuilt code are fragile
- Flag any claim that assumes a code capability that doesn't yet exist

**Dependency check:**
- Would this claim failing cascade to other claims?
- Are there claims that are logically dependent but not explicitly linked?

### 3. Challenge Every Principle

For each principle:
- Is there a scenario where following this principle would harm the business?
- Are any current claims or strategies in tension with this principle?

## Output Format

```
## Business Red Team

**Date:** {date}
**Scope:** {full audit / specific claim / strategy review}

### Claims

- **{claim-id}** ({confidence}): PASS — [evidence holds, no counter-evidence found]
- **{claim-id}** ({confidence}): FAIL — [what's wrong, what counter-evidence exists]
- **{claim-id}** ({confidence}): WARN — [not wrong but fragile, what to watch]

### Principles

- **{principle-id}**: PASS — [no current tension]
- **{principle-id}**: WARN — [tension with claim X or strategy Y]

### Cross-Reference Health

- **{claim-id}** refs **{code-contract-id}**: OK / MISMATCH / MISSING
  [details if not OK]

### Counter-Evidence Found
[Any web search results that challenge existing claims — with URLs and dates]

### Recommended Actions
1. [Most urgent — claims that should be downgraded or validated]
2. [Important — gaps in evidence or cross-references]
3. [Nice-to-have — improvements to claim coverage]
```

## Rules

- FAIL means the claim's evidence doesn't support its confidence level, or direct counter-evidence exists. Be specific.
- WARN means the claim isn't wrong but is fragile — evidence is thin, dated, or logically dependent on untested assumptions.
- PASS means the claim was actively challenged and held up.
- Every claim and principle must appear exactly once.
- Be harder on `validated` and `supported` claims — these assert real evidence exists.
- Be constructive — a FAIL should come with a suggestion (downgrade confidence, gather specific evidence, or reframe the claim).
