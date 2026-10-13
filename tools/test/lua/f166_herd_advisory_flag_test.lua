-- f166_herd_advisory_flag_test.lua - RSF-F166: the ProStaff half of the herd
-- advisory rung. Exercises the REAL src getters against the REAL constant table.
--
-- ProStaff's whole contribution to F166 is one boolean at L12. Everything that
-- makes the feature safe (which barns, which farm, which facts) lives in
-- DairyCore. So these rows are about the flag behaving like every other ordinary
-- flag, and about ONE hazard that ProStaff deliberately does not fix.
--!load: src/ProStaffConstants.lua, src/ProStaffManager.lua, src/ProStaffAPI.lua

local function newMgr() return ProStaffManager.new() end
local function setFarm(m, id, lvl, active)
  m.farms[id] = { level = lvl, investmentTotal = 0, levelHistory = {},
                  membershipActive = active }
end

-- Every call to the new getter goes through this, so that a build WITHOUT the
-- fix produces named failing rows instead of dying on the first nil method.
-- A mutation killed by a crash is unattributable: the file aborts, the runner
-- reports one line, and nobody can tell which row caught it.
local MISSING = "<no hasHerdAdvisory method>"
local function advisory(mgr, farmId)
  if mgr.hasHerdAdvisory == nil then return MISSING end
  local ok, v = pcall(mgr.hasHerdAdvisory, mgr, farmId)
  if not ok then return "<error: " .. tostring(v) .. ">" end
  return v
end

local m = newMgr()

T.ok("getter exists on the manager", m.hasHerdAdvisory ~= nil,
     "ProStaffAPI must publish hasHerdAdvisory; every row below depends on it")

-- The rung itself: first active at 12, exactly as declared.
T.eq("flag declared at L12", ProStaffConstants.FLAGS.hasHerdAdvisory, 12)

setFarm(m, 1, 11, true); T.eq("L11 no advisory",        advisory(m, 1), false)
setFarm(m, 1, 12, true); T.eq("L12 advisory",           advisory(m, 1), true)
setFarm(m, 1, 20, true); T.eq("L20 still advisory",     advisory(m, 1), true)
setFarm(m, 1, 0,  true); T.eq("L0 no advisory",         advisory(m, 1), false)

-- The three ordinary ways a flag goes quiet. Each is _farmLevel's, not ours.
setFarm(m, 1, 20, true)
m.settings.enabled = false
T.eq("provider disabled",        advisory(m, 1), false)
m.settings.enabled = true

m.farms[7] = nil
T.eq("no record for that farm",  advisory(m, 7), false)

setFarm(m, 1, 20, false)
T.eq("membership inactive",      advisory(m, 1), false)
setFarm(m, 1, 20, true)

-- It is an ORDINARY flag. hasSoilTestKit carries an extra ReleaseGate lock that
-- belongs to SF-40 alone, and the brief says not to copy it. Prove the new flag
-- does NOT consult the gate: with every system locked it must still answer on
-- level alone, the way hasMarketIntel does.
local gateWas = ReleaseGate
ReleaseGate = { isSystemLive = function() return false end }
setFarm(m, 1, 12, true)
T.eq("not gated by ReleaseGate",  advisory(m, 1), true)
T.eq("soil kit still is gated",   m:hasSoilTestKit(1),  false)
ReleaseGate = gateWas

-- Unrelated flags are untouched by the addition, at their own thresholds.
setFarm(m, 1, 12, true)
T.eq("market intel still L15",    m:hasMarketIntel(1),      false)
T.eq("forecast still L7",         m:hasForecastAccess(1),   true)
T.eq("predictive still L18",      m:hasPredictiveControl(1), false)
T.eq("early warning still L20",   m:hasEarlyWarning(1),     false)
setFarm(m, 1, 20, true)
T.eq("market intel at L20",       m:hasMarketIntel(1),      true)
T.eq("early warning at L20",      m:hasEarlyWarning(1),     true)

-- Cross-farm: the flag answers about the farm it was asked about, and nothing
-- borrows from a neighbour.
setFarm(m, 1, 12, true)
setFarm(m, 2, 3,  true)
T.eq("farm 1 entitled",           advisory(m, 1), true)
T.eq("farm 2 not entitled",       advisory(m, 2), false)

-- THE HAZARD THIS FILE DOES NOT FIX, PINNED SO IT STAYS VISIBLE.
--
-- _resolveFarm treats nil and 0 as "ask the mission", and the mission answers 1.
-- So a nil farm id does not fail closed here: it becomes farm 1 and reports farm
-- 1's entitlement. Worse, DairyCore reaches this through _proStaff, which builds
-- `local args = {...}` and unpacks it, so a nil third argument truncates the call
-- to zero arguments and lands in exactly this branch.
--
-- ProStaff is NOT the right place to close it. _resolveFarm is shared by every
-- getter and every existing caller relies on the fallback; changing it here would
-- be a silent behaviour change across the whole API for the sake of one new flag.
-- The rejection belongs in DairyCore, before the provider call, and the DairyCore
-- half of F166 is where it is built.
--
-- These rows exist so that the hazard is recorded as CURRENT BEHAVIOUR rather
-- than as an oversight, and so that anyone who later "fixes" it here has to
-- delete an assertion that says why it is deliberate.
setFarm(m, 1, 12, true)
setFarm(m, 2, 3,  true)
T.eq("nil farm resolves to mission farm 1 (deliberate)",  advisory(m, nil), true)
T.eq("zero farm resolves the same way (deliberate)",      advisory(m, 0),   true)

-- A garbage id fails closed for a different reason: it misses self.farms and
-- _farmLevel returns 0. Nil is the only one that fails OPEN.
T.eq("unknown numeric id fails closed",  advisory(m, 99),      false)
T.eq("string id fails closed",           advisory(m, "1"),     false)
-- The NaN row asserts the VALUE is a NaN before relying on it. Bob's MINOR on
-- this file: nothing here proved 0/0 produced one, and a row that assumes its
-- own fixture is the shape it needs is the same move as a guard that works by
-- coincidence. Cheap to prove, so prove it.
local nan = 0 / 0
T.ok("the NaN fixture really is NaN", nan ~= nan)
T.eq("nan id fails closed",              advisory(m, nan),     false)
T.eq("inf id fails closed",              advisory(m, math.huge), false)
T.eq("non-integer id fails closed",      advisory(m, 1.5),     false)

-- The getter is a read. Asking does not create a record or move a level.
local before = m.farms[2].level
advisory(m, 2); advisory(m, 2); advisory(m, 55)
T.eq("read did not move a level",        m.farms[2].level, before)
T.eq("read did not create a record",     m.farms[55], nil)
