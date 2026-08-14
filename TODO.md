# TODO: FS25_ProStaffCoOp

> Ecosystem role: **Co-Op services host** · Part of the Realistic Farming connected suite
> Status: kept current.
> Convention: `[ ]` open · `[~]` in progress · `[x]` done · `[!]` blocked. Newest at the top of each section.

## 2026-08-14 (Fred): Disease Flush (C2) mechanism
- [x] Thin server-authoritative flush action (`src/ProStaffDiseaseFlush.lua`): treat via SF `applyNamedFungicide(fieldId, chemId, { charge = false })`, or the easy-preset CLEAR via the server-gated `debugSetDisease(fieldId, 0)` wrapper; per-farm concurrent guard; C5 fee booked server-side via ProStaff's own `addMoney` (MoneyType.OTHER) + TaxMod audit.
- [x] C5 pricing: `(250 + 8 * severity) * economyHatchMultiplier`, read off the Economy dial through the vendored Option-Scaling resolver; neutral 1.0 when the spine is absent.
- [x] Character from the preset; off-diagonal policy confirmed (preset and Economy dial are independent controls, never cross-checked). Clear allowed strictly below realistic; blocked on realistic/punishing and when the spine is absent (fail-safe).
- [x] Chem selection from SF's own report (`getScoutReport().recommend.best`), scouting first (the designed ProStaff reveal path); catalog fallback `PROPICONAZOLE`.
- [x] NetworkSync actions `ProStaffCoOp_diseaseFlush` (member, ownership-checked) + `ProStaffCoOp_adminClear` (admin-gated, difficulty-gated).
- [x] Console commands: `diseaseFlushQuote`, `diseaseFlush`, `diseaseClear`.
- [x] Bench test: 71 assertions in `tools/test/lua/disease_flush_test.lua`. Suite green: 121 assertions, 3 files.

## Features / enhancements
- [ ] FarmTablet Co-Op tab: the ladder surface + the paid flush prompt (the player-facing flush surface is gated here; the mechanism it calls ships).
- [ ] In-game investment GUI (console drives it today).
- [ ] L9 personnel rebate apply site (WorkerCosts; FinanceStats confirm pending).
- [ ] L20 early-warning event feed (MarketDynamics `getEligibleEvents`).

## Cross-mod integration
- [x] StateLedger bridge (`ProStaffCoOp_State`, delegate-when-present).
- [x] NetworkSync bridge (`ProStaffCoOp_Level` + the flush actions).
- [x] Time Guard accruals (agronomy fee, fleet rebate).
- [x] SettingsHub bridge (enabled, baseCost, subscriptionFeeEnabled, agronomyFee, experimentalSystems).
- [x] Vendored Option-Scaling resolver (`src/OptionScalingResolver.lua`).
- [ ] Re-vendor the resolver on a wire-contract bump (`CONTRACT_VERSION 1`).

## Docs / localization
- [ ] 26-language pass on the flush prompt strings when the FarmTablet surface ships (the mechanism itself is console-driven and carries no player strings today).
- [ ] Keep README version in step on every release.
