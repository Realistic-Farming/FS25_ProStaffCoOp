# FS25_ProStaffCoOp

**Realistic Farming - Pro Staff Co-Op** is a 20-level cooperative progression backbone for the Realistic Farming mod ecosystem. Each farm invests to climb the Co-Op ladder, and every rung unlocks economic modifiers that companion mods read through a shared getter API. It owns its own server-authoritative money write and rides the shared **Time Guard** economic clock for recurring fees and rebates. Every cross-mod edge is handle-gated and pcall-wrapped, so it degrades gracefully when a companion mod is absent.

**Version:** 1.0.0.0

## What it does

- **20-level per-farm progression.** Level cost scales with the level reached (`level ^ 2.2 * baseCost`) and, from Level 10 up, a wealth-bracket escalator keyed on the farm's **net worth** (capped at 1.35x). You cannot game it by spending down cash.
- **Server-authoritative purchases.** ProStaff writes its own money via the base-game `addMoney`; a multiplayer client routes the request through NetworkSync's action channel. TaxMod `recordExpense` is audit-only, never the payment.
- **Economic modifiers, pulled by companion mods** via `g_currentMission.proStaffManager`:
  - *WorkerCosts* — wage modifier (multiplicative across reached steps), fatigue mitigation, fatigue recovery, global effectiveness.
  - *SoilFertilizer* (and the SF 2.5 disease/fungicide layer) — fertilizer discount, fungicide discount and effectiveness, spray-cost modifier. These four stand down when Precision Farming is present; the progression itself stays active.
  - *DairyCore / Realistic Livestock* — vet supply discount, dairy logistics bonus, bulk procurement bonus.
  - *Report flags* — forecast access (L7), market intel (L15), predictive control (L18), early warning (L20).
- **Recurring money on the Time Guard clock** via `registerAccrual`: an optional monthly agronomy-report subscription fee (gated on forecast access) and the L14 fleet rebate. Server-only, idempotent across save/reload.

## Handles

```
g_currentMission.proStaffManager   -- cross-mod handle, set in Mission00.load, nil on delete
g_proStaffCoOp                     -- getfenv(0) same-mod fallback
```

## Getter API (companion consumers)

Every getter takes an optional `farmId` (defaults to the local player's farm) and returns its neutral value when ProStaff is disabled, the level is not reached, or the farm has no membership.

```
getLevel(farmId)
getWageModifier / getFatigueMitigation / getFatigueRecoveryBonus / getGlobalEffectivenessBonus
getFertilizerDiscount / getFungicideDiscount / getFungicideEffectivenessBonus / getSprayCostModifier
getVetSupplyDiscount / getDairyLogisticsBonus / getBulkProcurementBonus / getBulkTransportDiscount
hasForecastAccess / hasMarketIntel / hasPredictiveControl / hasEarlyWarning
```

## Core API connections (delegate-when-present, neutral when absent)

- **Time Guard** — the recurring accrue-and-settle scheduler (agronomy fee, fleet rebate).
- **StateLedger** — per-farm level + investment state (own-XML fallback `FS25_ProStaffCoOp.xml` when absent).
- **NetworkSync** — level sync to clients plus the sanctioned client-to-server purchase action.
- **SettingsHub** — four admin settings (enable, level base cost, subscription fee, agronomy fee).

## Notes

- Zero Precision Farming: PF disables only the fertilizer/fungicide getters; the progression and every other modifier stay active.
- The L20 early-warning flag and the L9 herdsman-wage rebate are wired but inert pending their companion apply sites (MarketDynamics event feed, WorkerCosts herdsman-wage read). All numbers ride the balance pass.
- The in-game investment GUI is not built yet; the console commands drive it for now. The getter API that companion mods consume is complete.
- 26 languages ship from day one. Console commands: `proStaffStatus`, `proStaffBuy`.
