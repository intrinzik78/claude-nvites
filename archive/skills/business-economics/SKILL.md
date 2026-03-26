---
name: business-economics
description: Unit economics modeling. Estimates AI costs per user, breakeven pricing, contribution margin, and runway scenarios using actual code schema data.
---

# Unit Economics Modeler

## Input

$ARGUMENTS can specify:
- No args → full unit economics model
- "cost" → AI cost analysis only
- "pricing" → pricing model scenarios only
- "runway" → runway/burn analysis only
- "refresh" → update existing model with current data

## Data Collection Phase

### From Code Schema (always read)
Read `docs/Architecture.md`:
- Intelligence capabilities: tool count, tier distribution
- Cost visibility contract: what's tracked, what's missing
- Pipeline details: cascade patterns (fire-and-forget = multiplied API calls)

### From Web Search (if available)
Search for current AI model API pricing:
- Per-token costs for each model tier used
- Any batch pricing or volume discounts
- Rate limits that affect usage patterns

If web search is unavailable, note this and use placeholder pricing with clear "UPDATE NEEDED" markers.

### From Workspace Context
- `business-schema.json`: financial claims, pricing claims
- `users/persona-*.md`: engagement patterns, willingness to pay
- `research/competitor-*.md`: competitor pricing for benchmarking

## Output

Create or update `strategy/unit-economics.md`:

```markdown
# Unit Economics

**Modeled:** {date}
**API pricing as of:** {date — critical for accuracy}

## AI Cost Per User

### Tool Distribution by Tier
| Tier | Model | Tools | Estimated calls/user/month | Cost/1K tokens (in/out) |
|------|-------|-------|---------------------------|------------------------|
| T0 | None (CRUD) | {count} | — | $0 |
| T1 | [Tier 1 model] | {count} | | |
| T2 | [Tier 2 model] | {count} | | |
| T3 | [Tier 3 model] | {count} | | |

### Cascade Multiplier
- {N} tools cascade (fire additional API calls on completion)
- Estimated cascade overhead: {multiplier}x on cascading tools

### Monthly AI Cost Per User
| Usage level | Calls/month | Est. tokens | Monthly cost |
|-------------|-------------|-------------|--------------|
| Light | | | |
| Moderate | | | |
| Heavy | | | |

## Breakeven Analysis

### Cost Structure Per User
| Item | Monthly cost |
|------|-------------|
| AI API calls (moderate usage) | |
| Infrastructure (amortized) | |
| Total variable cost | |

### Breakeven Price Points
- **Floor:** ${X}/mo (covers variable costs only)
- **Target:** ${X}/mo (30% contribution margin)
- **Premium:** ${X}/mo (50% contribution margin)

### Competitor Benchmark
[Reference competitor pricing from research/ if available]

## Pricing Scenarios

### Scenario A: {e.g., Flat subscription}
- Price: ${X}/mo
- Margin at moderate usage: {X}%
- Risk: heavy users erode margin

### Scenario B: {e.g., Usage-tiered}
- Tiers: [describe]
- Margin range: {X-Y}%
- Risk: complexity deters adoption

### Scenario C: {e.g., Freemium + paid}
- Free tier: [what's included]
- Paid tier: [what's added]
- Conversion assumption: {X}%

## Runway Scenarios
*If applicable — based on current burn rate and projected revenue*

| Scenario | Users | MRR | Monthly burn | Runway |
|----------|-------|-----|-------------|--------|
| Conservative | | | | |
| Moderate | | | | |
| Optimistic | | | | |

## Assumptions & Risks
- [List every assumption with confidence level]
- [Flag which numbers are real vs. estimated]

## Action Items
- [What data is needed to improve accuracy]
- [Which assumptions should be validated first]

---
*Generated {date}. API pricing is perishable — refresh before any pricing decisions.*
*Token estimates are projections. Validate against actual usage data when available.*
```

## Post-Generation

After creating/updating the model:
1. Read `business-schema.json`
2. Check financial-category claims against findings
3. If the model contradicts claims (e.g., costs are higher than assumed), note it and suggest running `/business-GUARDIAN` to update
4. If `cost-visibility` code contract has improved (more actual data), note that models can be tightened
