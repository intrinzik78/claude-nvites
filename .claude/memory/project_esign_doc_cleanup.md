---
name: ESIGN doc cleanup at end of waiver build
description: Post-waiver-build cleanup — move waiver-esign-map.json to docs/structured-data/, archive DISPATCH_ESIGN_*.md files, review ESIGN_GUIDE.md
type: project
---

At end of waiver build, clean up ESIGN doc artifacts:
- Move `docs/waiver-esign-map.json` → `docs/structured-data/`
- Archive `docs/DISPATCH_ESIGN_SERVER_PHASE2.md` and `docs/DISPATCH_ESIGN_WAIVER.md`
- Review `docs/ESIGN_GUIDE.md` for accuracy against final implementation, update audit date

**Why:** These files were created incrementally across Phase 1 and Phase 2. The dispatches are consumed work. The map belongs with other structured data. The guide needs a final pass once the build is complete.

**How to apply:** Flag when the waiver build is wrapping up. Don't do this cleanup mid-build — the dispatches are still referenced by in-progress surface work.
