---
name: business-strategy
description: Multi-mode business strategy skill. Generates positioning, pricing models, and go-to-market plans. Cross-references code schema for feasibility.
---

# Business Strategy

## Modes

$ARGUMENTS determines the mode:

- `positioning` → produces `strategy/positioning.md`
- `pricing` → produces `strategy/pricing-model.md`
- `gtm` → produces `strategy/go-to-market.md`
- No args → ask the user which mode

## Pre-Read (all modes)

Before generating any strategy document, read all available workspace context:
1. `business-schema.json` — claims, confidence levels, risks, open questions
2. All files in `strategy/`, `research/`, `users/` — build on existing work
3. `docs/Architecture.md` — current technical architecture and capabilities
4. `DECISIONS.md` if it exists — relevant technical decisions

## Mode: Positioning

Output `strategy/positioning.md`:

```markdown
# Positioning

**Generated:** {date}

## Positioning Statement
For [target user] who [need], [Product] is a [category] that [key benefit].
Unlike [alternatives], we [differentiator].

## Category Definition
- **Category:** [what market category does this product create or enter?]
- **Adjacent categories:** [what related categories exist?]
- **Category maturity:** [emerging/growing/mature/declining]

## Value Propositions
### Primary
[The single most compelling reason to use this product]

### Secondary
1. [Value prop 2]
2. [Value prop 3]

## Competitive Position
[Reference competitor research if available. Where does [Product] sit in the market?]

## Messaging Pillars
1. **[Pillar]:** [supporting point]
2. **[Pillar]:** [supporting point]
3. **[Pillar]:** [supporting point]

## Confidence Assessment
[Which parts of this positioning are validated vs. assumed? Reference claim IDs.]

## Code Feasibility
[Can the product currently deliver on these positioning claims? Cross-reference code contracts.]
```

## Mode: Pricing

Output `strategy/pricing-model.md`:

```markdown
# Pricing Model

**Generated:** {date}

## Recommended Model
[Subscription/freemium/usage-based/etc. with rationale]

## Tier Structure
| Tier | Price | Includes | Target user |
|------|-------|----------|-------------|
| | | | |

## Unit Economics Reference
[Pull from strategy/unit-economics.md if it exists, otherwise note the gap]

## Competitor Pricing
[Pull from research/competitor-*.md if they exist]

## Price Sensitivity Analysis
[Pull from users/persona-*.md willingness-to-pay data if available]

## Risks
[What could make this pricing wrong? Reference challenged/untested claims.]
```

## Mode: Go-to-Market

Output `strategy/go-to-market.md`:

```markdown
# Go-to-Market Plan

**Generated:** {date}

## Launch Strategy
- **Type:** [beta/soft launch/full launch]
- **Timeline:** [relative to current product state]
- **Initial target:** [specific segment of target market]

## Channels
| Channel | Approach | Cost | Expected reach |
|---------|----------|------|----------------|
| | | | |

## Launch Prerequisites
### Product
[What must be built? Cross-reference code contracts and their confidence levels.]
- [Feature]: code contract {id} — confidence: {level}

### Business
[What must be validated? Reference untested/assumed claims.]
- [Claim]: {id} — confidence: {level}

## Milestones
1. [Milestone with success criteria]
2. [Next milestone]

## Risks & Mitigations
[Reference business-schema.json risks section]
```

## Post-Generation

After creating any strategy document:
1. Check if the strategy introduces assumptions not captured in `business-schema.json`
2. If so, list them and suggest running `/business-GUARDIAN` to add as claims
3. Flag any strategy that depends on `unbuilt` code contracts

$ARGUMENTS
