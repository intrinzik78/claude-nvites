---
name: business-competitor
description: Competitive teardown. Analyzes competitors with feature matrix, pricing, strengths, weaknesses, and data flywheel comparison.
---

# Competitor Teardown

## Input

$ARGUMENTS should specify either:
- A competitor name
- Or "landscape" to produce a market landscape overview
- Or "audit" to review existing teardowns for gaps

If no argument given, ask the user which competitor to analyze.

## Research Phase

Use web search extensively:
- Official website: pricing pages, feature lists, about page
- Review sites: G2, Capterra, Trustpilot
- Social media presence and user sentiment
- Funding/company size if available
- Recent product announcements or pivots

If web search is unavailable, note this clearly and produce analysis from available workspace context only. Mark all claims as low-confidence.

## Output — Single Competitor

Create the file `research/competitor-{name}.md` (lowercase, hyphenated) with this structure:

```markdown
# Competitor: {Name}

**Researched:** {date}
**Sources:** {list URLs with access dates}

## Overview
- **What they do:** [1-2 sentences]
- **Founded:** [year]
- **Company size:** [employees/funding if known]
- **Target user:** [who they sell to]

## Pricing
- **Model:** [subscription/per-use/freemium/etc.]
- **Tiers:** [list tiers with prices]
- **Free tier:** [yes/no, what's included]

## Feature Matrix

| Feature | {Competitor} | [Product] (current) | [Product] (planned) |
|---------|-------------|----------------------|----------------------|
| [key feature 1] | | | |
| [key feature 2] | | | |
| [add relevant features] | | | |

## Strengths
1. [What they do well — be specific]

## Weaknesses
1. [Where they fall short — be specific]

## Data Flywheel Comparison
*Does this competitor have a data flywheel? How does it compare to [Product]'s approach?*
- **Data collection:** [what data do they collect from usage?]
- **AI/ML usage:** [do they use accumulated data to improve the product?]
- **Network effects:** [does more usage make the product better for everyone?]
- **Flywheel strength:** [none/weak/moderate/strong]

## [Product] Differentiation
- **Where [Product] wins:** [specific advantages]
- **Where [Product] loses:** [specific disadvantages — be honest]
- **Strategic response:** [how should [Product] position against this competitor?]

---
*Generated {date}. Review/update recommended every 90 days.*
```

## Output — Landscape Mode

When invoked with "landscape", create `research/competitive-landscape.md`:

```markdown
# Competitive Landscape

**Researched:** {date}

## Market Segments
[Group competitors by category — direct, adjacent, potential]

## Comparison Matrix
[Feature matrix across all analyzed competitors + [Product]]

## Market Gaps
[Opportunities no competitor is addressing well]

## Threat Assessment
[Which competitors are the biggest threat and why]

## [Product] Positioning
[Where [Product] should position based on the landscape]
```

This pulls from all existing `research/competitor-*.md` files plus web search for any major players not yet analyzed.

## Post-Generation

After creating the teardown:
1. Read `business-schema.json` if it exists
2. Check competitive-category claims against findings
3. If research contradicts a claim, note it and suggest running `/business-GUARDIAN` to update

## Audit Mode

When invoked with "audit":
1. List all existing competitor teardowns in `research/`
2. Flag any older than 90 days as needing refresh
3. Use web search to identify major competitors not yet analyzed
4. Suggest which teardowns to create or refresh next
