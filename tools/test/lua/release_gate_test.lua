-- release_gate_test.lua - the release gate (STABLE vs experimental-LOCKED).
--
-- The gate is orthogonal to difficulty and mirrors the bypass lock, but on the
-- release axis. Arissani's certification (2026-08-03): the SF-40 soil test kit
-- flag is LOCKED because its consumer, Read the Dirt, is locked on the
-- SoilFertilizer side. Releasing is a deliberate act, never a default.
--!load: src/ReleaseGate.lua, src/ProStaffConstants.lua, src/ProStaffManager.lua, src/ProStaffAPI.lua

-- Sanity: the certified row exists.
T.ok("soil_test_kit registered", ReleaseGate.EXPERIMENTAL.soil_test_kit ~= nil)

-- isReleased: a non-experimental system is always released regardless of opt-in.
T.ok("stable system released with no opt-in", ReleaseGate.isReleased("wageModifier", nil) == true)
T.ok("stable system released with opt-in on", ReleaseGate.isReleased("wageModifier", true) == true)
T.ok("stable system released with opt-in off", ReleaseGate.isReleased("wageModifier", false) == true)

-- isReleased: soil_test_kit is LOCKED until the explicit opt-in.
T.ok("soil_test_kit LOCKED by default", ReleaseGate.isReleased("soil_test_kit", nil) == false)
T.ok("soil_test_kit LOCKED with opt-in off", ReleaseGate.isReleased("soil_test_kit", false) == false)
T.ok("soil_test_kit released when opt-in on", ReleaseGate.isReleased("soil_test_kit", true) == true)

-- lockMessage: nil when released, a refusal string when locked.
T.eq("no lock message for a stable system", ReleaseGate.lockMessage("wageModifier", nil), nil)
T.eq("no lock message when opted in", ReleaseGate.lockMessage("soil_test_kit", true), nil)
local msg = ReleaseGate.lockMessage("soil_test_kit", false)
T.ok("lock message when locked", msg ~= nil)
T.ok("message names the not-released state", string.find(msg, "not released", 1, true) ~= nil)

-- status: player-friendly, short, one line per system.
local st = ReleaseGate.status(false)
T.ok("status says OFF when not opted in", string.find(st, "OFF", 1, true) ~= nil)
T.ok("status lists LOCKED systems", string.find(st, "LOCKED", 1, true) ~= nil)
local stOn = ReleaseGate.status(true)
T.ok("status says ON when opted in", string.find(stOn, "ON", 1, true) ~= nil)

-- ── SIM-WIRING GATE: hasSoilTestKit respects the live opt-in ──────────────
-- The getter must return false at L10 when the player has not opted in, true
-- when they have, and FAIL OPEN when the opt-in cannot be read.

local function newMgr()
    local m = ProStaffManager.new()
    m.farms[1] = { level = 10, investmentTotal = 0, levelHistory = {}, membershipActive = true }
    return m
end

local function withOptIn(optIn, fn)
    local prev = g_proStaffCoOp
    g_proStaffCoOp = newMgr()
    g_proStaffCoOp.settings.experimentalSystems = optIn
    local ok, res = pcall(fn)
    g_proStaffCoOp = prev
    if not ok then error(res, 0) end
    return res
end

T.ok("kit flag LOCKED at L10 with opt-in off",
    withOptIn(false, function() return not g_proStaffCoOp:hasSoilTestKit(1) end))
T.ok("kit flag granted at L10 with opt-in on",
    withOptIn(true, function() return g_proStaffCoOp:hasSoilTestKit(1) end))

-- Fail-open: no manager registered behaves exactly as before the gate.
g_proStaffCoOp = nil
local m = newMgr()
T.ok("kit flag granted at L10 with no manager (fail-open)", m:hasSoilTestKit(1))
T.ok("kit flag still level-gated below L10", function()
    m.farms[1].level = 9
    return not m:hasSoilTestKit(1)
end)
