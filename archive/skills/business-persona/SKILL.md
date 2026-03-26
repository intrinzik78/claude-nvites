---
name: business-persona
description: Structured persona generation. Produces user personas with demographics, goals, pain points, data generation profiles, and willingness to pay.
---

# Persona Generator

## Input

$ARGUMENTS should specify either:
- A persona name/type (e.g., a specific user role or job title)
- Or "audit" to review existing personas for gaps

If no argument given, ask the user what persona to create.

## Research Phase

Use web search to gather real data on the persona type:
- Industry demographics (age, gender distribution, income)
- Common tools and workflows
- Market size estimates
- Professional associations and certifications
- Typical workload and pricing

If web search is unavailable, note this clearly and produce the persona from available workspace context only.

## Output

Create the file `users/persona-{name}.md` (lowercase, hyphenated) with this structure:

```markdown
# Persona: {Name}

## Demographics
- **Age range:**
- **Gender distribution:**
- **Education:**
- **Income range:**
- **Practice/team size:** (solo/small/enterprise)
- **Workload:** (typical volume)
- **Years in role:**

## Goals
1. [Primary professional goal]
2. [Secondary goals — 2-3 items]

## Pain Points
1. [Primary pain point]
2. [Secondary pain points — 2-4 items]

## Current Tools
- [What they use today]
- [Gaps in current tooling]

## Willingness to Pay
- **Current software spend:** [monthly estimate]
- **Price sensitivity:** [high/medium/low]
- **Value triggers:** [what would make them pay more]
- **Deal breakers:** [what kills a sale]

## Engagement Pattern
- **Frequency:** [daily/weekly/per-session]
- **Primary device:** [desktop/tablet/phone]
- **Session context:** [when and where they'd use the tool]

## Data Generation Profile
*How much flywheel data would this persona produce?*
- **Volume:** [high/medium/low — based on workload and session frequency]
- **Richness:** [what types of data — notes, assessments, outcomes]
- **Consistency:** [likely to maintain regular input, or sporadic?]
- **AI value curve:** [how quickly would accumulated data produce useful insights?]

## Product Fit
- **Alignment with product:** [how well does this persona match current capabilities?]
- **Adoption barriers:** [what would prevent this persona from using the product?]
- **Key feature needs:** [what must exist for this persona to get value?]

---
*Generated {date}. Sources: {list sources with dates, or "workspace context only" if no web search}.*
```

## Post-Generation

After creating the persona:
1. Read `business-schema.json` if it exists
2. Check if any claims relate to this persona (especially user-category claims)
3. If the persona research contradicts a claim, note it and suggest running `/business-GUARDIAN` to update

## Audit Mode

When invoked with "audit":
1. List all existing personas in `users/`
2. Read `business-schema.json` claims with category "user" or "market"
3. Identify persona gaps — claims that assume a user type with no corresponding persona
4. Suggest which personas to create next
