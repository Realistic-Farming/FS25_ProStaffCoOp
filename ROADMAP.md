# Roadmap: FS25_ProStaffCoOp

> Ecosystem role: **Co-Op services host** (progression backbone + recovery hatches) · Part of the Realistic Farming connected suite
> Status: v1.0.0.2 (development). Ladder shipped v1.0.0.0 (2026-07-18); the Co-Op disease flush (C2) mechanism built on development 2026-08-14.
> Forward-looking only. Shipped history lives in the releases and the tracking workspace README.

## How to use this file
- Each item should be small enough to map to a `TODO.md` entry.
- Keep it honest: near-term is committed, mid-term is intended, long-term is aspirational.

## Current baseline
- Version at baseline: 1.0.0.2 (development); the C2 disease-flush MECHANISM built on the shipped 20-level ladder.
- The player-facing flush surface (the Co-Op prompt) is GATED on the FarmTablet app tab, which is not built; console commands drive the mechanism today.
- Audit reference: ecosystem-dev-tracking `Office Tyson/mods/FS25_ProStaffCoOp/` (build briefs + README).

## Near-term (next release cycle)
- [x] Disease Flush (C2) mechanism (2026-08-14): the thin server-authoritative flush action hosted on ProStaff. Treats (hard presets / spine-absent fail-safe) ride SF's own `applyNamedFungicide` with `charge=false`; the easy-preset CLEAR rides the server-gated `debugSetDisease` wrapper (difficulty-blocked on realistic and up). The C5 fee `(250 + 8 * severity) * economyHatchMultiplier` is booked server-side via ProStaff's own money write; the Economy dial resolves through the vendored Option-Scaling resolver (neutral 1.0 when the spine is absent). A per-farm concurrent guard stops double-fires. 71 assertions in `disease_flush_test.lua`. Built on development, PR open.
- [ ] FarmTablet Co-Op app tab: the ladder surface + the paid flush prompt. Gated on FarmTablet's AppRegistry; the flush surface calls the mechanism `diseaseFlushQuote` / `requestFarmFlush`.

## Mid-term (this season)
- [ ] In-game investment GUI (the ladder is console-driven today).
- [ ] L9 personnel rebate apply site (WorkerCosts; base-game FinanceStats confirm pending).
- [ ] L20 early-warning event feed (MarketDynamics `getEligibleEvents`).

## Cross-mod / ecosystem dependencies
- [ ] FarmTablet app tab (the flush surface; Wizard lane owns the UI).
- [ ] SF side: the treat/clear surface is verified and shipped (2.5 disease layer); nothing owed. The Co-Op report reveal path is the designed-in `scoutField` consumer.
- [ ] Option-Scaling Spine: C5 hatch pricing rides the vendored resolver (`CONTRACT_VERSION 1`); neutral when absent. Re-vendor on a wire-contract bump.
- [ ] NetworkSync: flush actions (`ProStaffCoOp_diseaseFlush` member, `ProStaffCoOp_adminClear` admin).

## Deferred / parked
- Precision Farming: the soil getters stand down under PF by design; the flush reads SF's own disease state and is unaffected (SF's disease sim runs independently of the getter discounts).
