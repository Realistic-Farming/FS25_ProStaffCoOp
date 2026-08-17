-- disease_flush_test.lua - the Co-Op disease flush (C2) mechanism.
--
-- Exercises the buildable core of the disease-flush safety net against the REAL
-- vendored Option-Scaling resolver and a mock SF soil system (the treat/clear
-- surface is source-verified against the current SF clone:
-- getScoutReport / scoutField / applyNamedFungicide / debugSetDisease).
--
-- Covers: the C5 fee formula, the preset character + the off-diagonal policy
-- (preset picks character, Economy dial picks cost, never cross-checked), the
-- spine-absent fail-safe, the economy-dial multiplier through the real resolver,
-- the per-farm concurrent guard, the treat path (charge=false + correct chem +
-- C5 booking), the clear path (debugSetDisease + C5 booking), the funds denial,
-- the admin-clear difficulty gate, and the NetworkSync action registration.
--!load: src/ProStaffConstants.lua, src/OptionScalingResolver.lua, src/ProStaffManager.lua, src/ProStaffAPI.lua, src/ProStaffDiseaseFlush.lua

local m = ProStaffManager.new()
m.settings.enabled = true

-- ---- SF mock (the verified surface) ----
local applied, cleared, scoutLog, debits = {}, {}, {}, {}
local fieldData = {
  [101] = { activeDisease = "septoria_tritici", diseasePressure = 60, fungicideDaysLeft = 0 },
  [102] = { activeDisease = nil,                 diseasePressure = 5,  fungicideDaysLeft = 0 },
  [103] = { activeDisease = "late_blight",        diseasePressure = 30, fungicideDaysLeft = 0 },
}
local soilSystem = {
  fieldData = fieldData,
  getScoutReport = function(_, fieldId)
    local f = fieldData[fieldId]
    if not f or not f.activeDisease then
      return { fieldId = fieldId, enabled = true, discovered = true,
               pressure = (f and f.diseasePressure) or 0, tier = "none" }
    end
    return { fieldId = fieldId, enabled = true, discovered = true,
             pressure = f.diseasePressure, tier = "mild", diseaseId = f.activeDisease,
             recommend = { best = "PROPICONAZOLE", second = "TEBUCONAZOLE", budget = "MANCOZEB" } }
  end,
  scoutField = function(self, fieldId)
    scoutLog[#scoutLog + 1] = fieldId
    return self:getScoutReport(fieldId)
  end,
  applyNamedFungicide = function(_, fieldId, chemId, opts)
    applied[#applied + 1] = { fieldId = fieldId, chemId = chemId, opts = opts }
    local f = fieldData[fieldId]
    if f then f.diseasePressure = math.max(0, (f.diseasePressure or 0) - 60) end
    return true, "sf_treat_done", {}
  end,
  debugSetDisease = function(_, fieldId, pressure)
    cleared[#cleared + 1] = { fieldId = fieldId, pressure = pressure }
    local f = fieldData[fieldId]
    if f then f.diseasePressure = pressure or 0 end
    return true, {}
  end,
}

-- ---- Spine mock: a real settingsHub-shaped table read by the vendored resolver ----
local preset, dial = "realistic", 1.5
local hub = {
  getValue = function(_, mod, key)
    if mod ~= OptionScalingResolver.MODULE then return nil end
    if key == OptionScalingResolver.PRESET_KEY then return preset end
    if key == OptionScalingResolver.dialKey("economy") then return dial end
    if key == OptionScalingResolver.switchKey("economy") then return true end
    return nil
  end,
}

local mission = {
  getFarmId = function() return 1 end,
  getIsServer = function() return true end,
  addMoney = function(_, amount, farmId, moneyType)
    debits[#debits + 1] = { amount = amount, farmId = farmId, moneyType = moneyType }
  end,
  soilFertilityManager = { soilSystem = soilSystem },
  settingsHub = hub,
}
local prevMission, prevFarmland, prevFarm = g_currentMission, g_farmlandManager, g_farmManager
g_currentMission = mission
g_farmlandManager = { getOwnedFarmlandIdsByFarmId = function() return { 101, 102, 103 } end }
g_farmManager = { getFarmById = function() return { money = 50000, getBalance = function() return 50000 end } end }

local function resetLogs()
  applied, cleared, scoutLog, debits = {}, {}, {}, {}
  fieldData[101] = { activeDisease = "septoria_tritici", diseasePressure = 60, fungicideDaysLeft = 0 }
  fieldData[102] = { activeDisease = nil,                 diseasePressure = 5,  fungicideDaysLeft = 0 }
  fieldData[103] = { activeDisease = "late_blight",       diseasePressure = 30, fungicideDaysLeft = 0 }
end

local function setSpine(p, d)
  preset, dial = p, d
end

-- ── C5 fee formula (locked numbers) ──────────────────────────────────────────
T.eq("fee severity 60 x1.0", m:_flushFee(60, 1.0), 730)      -- 250 + 8*60
T.eq("fee severity 60 x0.2", m:_flushFee(60, 0.2), 146)
T.eq("fee severity 0", m:_flushFee(0, 1.0), 250)
T.eq("fee severity 10 x2.75", m:_flushFee(10, 2.75), 907)    -- 330*2.75 = 907.5 -> floor
T.eq("fee nil mult neutral", m:_flushFee(60, nil), 730)
T.eq("fee negative mult clamps to 0", m:_flushFee(10, -1), 0)

-- ── Spine absent = neutral + fail-safe ───────────────────────────────────────
mission.settingsHub = nil
T.eq("mult neutral when spine absent", m:_economyHatchMultiplier(), 1.0)
T.ok("clear blocked when spine absent", not m:_flushClearAllowed())
T.eq("character treat when spine absent", m:_flushCharacter(), "treat")
mission.settingsHub = hub

-- ── Character from the preset (through the real vendored resolver) ───────────
setSpine("relaxed", 0.0)
T.ok("clear allowed relaxed", m:_flushClearAllowed())
T.eq("character clear relaxed", m:_flushCharacter(), "clear")
setSpine("standard", 1.0)
T.ok("clear allowed standard", m:_flushClearAllowed())
T.eq("character clear standard", m:_flushCharacter(), "clear")
setSpine("custom", 1.0)
T.ok("clear allowed custom (standard rank)", m:_flushClearAllowed())
setSpine("realistic", 1.5)
T.ok("clear blocked realistic", not m:_flushClearAllowed())
T.eq("character treat realistic", m:_flushCharacter(), "treat")
setSpine("punishing", 2.0)
T.ok("clear blocked punishing", not m:_flushClearAllowed())

-- ── Economy dial through the REAL resolver curveEval (C5 hatch curve) ────────
setSpine("relaxed", 0.0)
T.near("mult dial 0 -> 0.2", m:_economyHatchMultiplier(), 0.2)
setSpine("standard", 1.0)
T.near("mult dial 1 -> 1.0", m:_economyHatchMultiplier(), 1.0)
setSpine("realistic", 1.5)
T.near("mult dial 1.5 -> 1.875", m:_economyHatchMultiplier(), 1.875)
setSpine("punishing", 2.0)
T.near("mult dial 2 -> 2.75", m:_economyHatchMultiplier(), 2.75)

-- ── Quote (pure read; realistic preset) ──────────────────────────────────────
setSpine("realistic", 1.5)
local q = m:diseaseFlushQuote(1)
T.eq("quote character treat", q.character, "treat")
T.eq("quote mult", q.economyMultiplier, 1.875)
T.eq("quote clearAllowed false", q.clearAllowed, false)
T.eq("quote 2 diseased fields", q.diseasedCount, 2)
T.eq("quote total floor(730*1.875)+floor(490*1.875)", q.totalCost, 2286)

-- ── Treat path (realistic): correct chem, charge=false, C5 fee, no clear ─────
setSpine("realistic", 1.5)
resetLogs()
T.eq("flush treat ok", m:_doFarmFlush(1), true)
T.eq("treated 2 fields", #applied, 2)
T.eq("field 101 treated first (asc)", applied[1].fieldId, 101)
T.eq("field 103 treated second", applied[2].fieldId, 103)
T.eq("treat chem from report", applied[1].chemId, "PROPICONAZOLE")
T.eq("treat charge false", applied[1].opts.charge, false)
T.eq("treat passes farmId", applied[1].opts.farmId, 1)
T.eq("no clear calls on treat", #cleared, 0)
T.eq("scouted before treating", #scoutLog, 2)
T.eq("fee booked once", #debits, 1)
T.eq("fee amount 1368+918", debits[1].amount, -2286)
T.eq("fee farmId", debits[1].farmId, 1)
T.eq("fee MoneyType.OTHER", debits[1].moneyType, MoneyType.OTHER)
T.eq("guard cleared after run", m.flushGuard[1], nil)

-- ── Per-farm concurrent guard blocks a double-fire ───────────────────────────
resetLogs()
m.flushGuard[1] = true
T.eq("double-fire blocked", m:_doFarmFlush(1), false)
T.eq("no fee on blocked double-fire", #debits, 0)
T.eq("no treat on blocked double-fire", #applied, 0)
m.flushGuard[1] = nil

-- ── Clear path (relaxed): debugSetDisease(0) + C5 fee at the low dial ────────
setSpine("relaxed", 0.0)
resetLogs()
T.eq("flush clear ok", m:_doFarmFlush(1), true)
T.eq("cleared 2 fields", #cleared, 2)
T.eq("clear field order", cleared[1].fieldId, 101)
T.eq("clear pressure zero", cleared[1].pressure, 0)
T.eq("no treat calls on clear", #applied, 0)
T.eq("clear fee booked", #debits, 1)
T.eq("clear fee (730+490)*0.2", debits[1].amount, -244)
T.eq("guard cleared after clear", m.flushGuard[1], nil)

-- ── Funds denial: a flush that cannot be afforded is denied whole ────────────
setSpine("realistic", 1.5)
resetLogs()
g_farmManager = { getFarmById = function() return { money = 100, getBalance = function() return 100 end } end }
T.eq("flush denied on funds", m:_doFarmFlush(1), false)
T.eq("no fee when denied", #debits, 0)
T.eq("no treat when denied", #applied, 0)
g_farmManager = { getFarmById = function() return { money = 50000, getBalance = function() return 50000 end } end }

-- ── Admin-clear difficulty gate (the server-gated CLEAR wrapper) ─────────────
setSpine("realistic", 1.5)
resetLogs()
T.eq("admin clear blocked realistic", m:_doAdminClear(1), false)
T.eq("no debugSetDisease when blocked", #cleared, 0)
setSpine("relaxed", 0.0)
resetLogs()
T.eq("admin clear allowed relaxed", m:_doAdminClear(1), true)
T.eq("admin clear hard-clears 2 fields", #cleared, 2)
T.eq("admin clear books no fee", #debits, 0)
mission.settingsHub = nil
resetLogs()
T.eq("admin clear blocked spine absent (fail-safe)", m:_doAdminClear(1), false)
T.eq("no clear spine absent", #cleared, 0)
mission.settingsHub = hub

-- ── Nothing to flush: no charge, no calls ────────────────────────────────────
setSpine("standard", 1.0)
resetLogs()
fieldData[101].activeDisease = nil
fieldData[101].diseasePressure = 5
fieldData[103].activeDisease = nil
fieldData[103].diseasePressure = 5
T.eq("no diseased fields -> no flush", m:_doFarmFlush(1), false)
T.eq("no fee with no disease", #debits, 0)
T.eq("no treat with no disease", #applied, 0)

-- ── SF absent: the flush degrades to nothing (delegate-when-present) ─────────
resetLogs()
local prevSfm = mission.soilFertilityManager
mission.soilFertilityManager = nil
T.eq("no SF -> no flush", m:_doFarmFlush(1), false)
T.eq("no SF -> no fee", #debits, 0)
mission.soilFertilityManager = prevSfm

-- ── NetworkSync action registration ──────────────────────────────────────────
local registered = {}
mission.networkSync = { registerAction = function(_, id, spec) registered[id] = spec end }
m.diseaseFlushBound = false
m:bindDiseaseFlush()
T.ok("flush action registered", registered[ProStaffConstants.ACTION_FLUSH] ~= nil)
T.ok("clear action registered", registered[ProStaffConstants.ACTION_CLEAR] ~= nil)
T.eq("flush action is member (not admin)", registered[ProStaffConstants.ACTION_FLUSH].adminOnly, false)
T.eq("clear action is admin-gated", registered[ProStaffConstants.ACTION_CLEAR].adminOnly, true)
T.ok("bind is idempotent", m.diseaseFlushBound == true)
mission.networkSync = nil

-- restore the prelude globals (fresh fengari state per file, but stay tidy)
g_currentMission, g_farmlandManager, g_farmManager = prevMission, prevFarmland, prevFarm
