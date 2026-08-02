-- effects_test.lua - ProStaff effect math, wealth bracket, level cost, flags.
-- Exercises the real src getters against the real constant tables.
--!load: src/ProStaffConstants.lua, src/ProStaffManager.lua, src/ProStaffAPI.lua

local function newMgr() return ProStaffManager.new() end
local function setLevel(m, lvl)
  m.farms[1] = { level = lvl, investmentTotal = 0, levelHistory = {}, membershipActive = true }
end

local m = newMgr()

-- WAGE: multiplicative product of every reached step ([5]=.975 [9]=.95 [17]=.90).
setLevel(m, 4);  T.near("wage L4 neutral",         m:getWageModifier(1), 1.0)
setLevel(m, 5);  T.near("wage L5",                 m:getWageModifier(1), 0.975)
setLevel(m, 9);  T.near("wage L9 = L5*L9",         m:getWageModifier(1), 0.975 * 0.95)
setLevel(m, 17); T.near("wage L17 product 0.833",  m:getWageModifier(1), 0.975 * 0.95 * 0.90)
setLevel(m, 20); T.near("wage L20 same product",   m:getWageModifier(1), 0.975 * 0.95 * 0.90)

-- FERTILIZER: step = value of the highest reached step ([2] [7] [12] [15]).
setLevel(m, 1);  T.near("fert L1 neutral",         m:getFertilizerDiscount(1), 1.0)
setLevel(m, 13); T.near("fert L13 -> L12 step",    m:getFertilizerDiscount(1), 0.94)
setLevel(m, 15); T.near("fert L15 step",           m:getFertilizerDiscount(1), 0.925)

-- VET_SUPPLY: L12 (0.90) supersedes L2 (0.95).
setLevel(m, 11); T.near("vet L11",                 m:getVetSupplyDiscount(1), 0.95)
setLevel(m, 12); T.near("vet L12 supersede",       m:getVetSupplyDiscount(1), 0.90)

-- Disabled -> neutral / level 0 everywhere.
setLevel(m, 20); m.settings.enabled = false
T.near("disabled wage neutral",  m:getWageModifier(1), 1.0)
T.eq  ("disabled level 0",       m:getLevel(1), 0)
m.settings.enabled = true

-- Precision Farming gate: soil getters stand down, progression getters stay live.
setLevel(m, 15); m.pfActive = true
T.near("PF fert neutral",        m:getFertilizerDiscount(1), 1.0)
T.near("PF fungicide neutral",   m:getFungicideDiscount(1), 1.0)
T.near("PF wage still active",   m:getWageModifier(1), 0.975 * 0.95)
m.pfActive = false

-- Feature flags (first active at level).
setLevel(m, 6);  T.ok("forecast L6 false",       not m:hasForecastAccess(1))
setLevel(m, 7);  T.ok("forecast L7 true",            m:hasForecastAccess(1))
setLevel(m, 18); T.ok("predictive L18 true",         m:hasPredictiveControl(1))
setLevel(m, 19); T.ok("earlyWarning L19 false",  not m:hasEarlyWarning(1))
setLevel(m, 20); T.ok("earlyWarning L20 true",       m:hasEarlyWarning(1))

-- [SF-40] Soil test kit: exact numbers at the kneel from L10 (Read the Dirt member 4).
setLevel(m, 9);  T.ok("soilTestKit L9 false",  not m:hasSoilTestKit(1))
setLevel(m, 10); T.ok("soilTestKit L10 true",       m:hasSoilTestKit(1))
setLevel(m, 20); T.ok("soilTestKit L20 true",       m:hasSoilTestKit(1))
setLevel(m, 5);  T.ok("soilTestKit below L10 false", not m:hasSoilTestKit(1))

-- Wealth bracket: inactive below L10, then net-worth tiers, capped at 1.35.
local worth = 0
g_farmManager = { getFarmById = function(_, _id) return { money = worth } end }
setLevel(m, 10)
worth = 400000;   T.near("bracket L10 <500k",  m:wealthBracket(1, 10), 1.00)
worth = 1000000;  T.near("bracket L10 <2M",    m:wealthBracket(1, 10), 1.10)
worth = 3000000;  T.near("bracket L10 <5M",    m:wealthBracket(1, 10), 1.20)
worth = 10000000; T.near("bracket L10 cap",    m:wealthBracket(1, 10), 1.35)
T.near("bracket L9 inactive",  m:wealthBracket(1, 9), 1.00)

-- Level cost: base at L1, exponent ratio, and wealth escalation on an L10 rung.
T.eq  ("cost L1 = base 260",           m:levelCost(1, 1), 260)
T.near("cost exponent L2/L1 = 2^2.2",  m:levelCost(1, 2) / m:levelCost(1, 1), 2 ^ 2.2, 0.02)
worth = 400000;   local lo = m:levelCost(1, 10)
worth = 10000000; local hi = m:levelCost(1, 10)
T.near("cost wealth escalation L10",   hi / lo, 1.35, 0.01)
