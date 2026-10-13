-- =========================================================
-- FS25_ProStaffCoOp - mod entry point
-- =========================================================
-- Author: TisonK
-- =========================================================
-- Loads the ProStaff modules, publishes the g_currentMission.proStaffManager
-- handle, and hooks the FS25 mission lifecycle. The 20-level Co-Op progression
-- backbone: companion mods PULL its ProStaffAPI getters. ProStaff owns its own
-- server-authoritative money write and rides the Time Guard clock for recurring
-- money. StateLedger persists per-farm state; NetworkSync syncs level.
--
-- Load order: ProStaffManager defines the class; ProStaffAPI extends it with the
-- getters, so ProStaffManager is sourced BEFORE ProStaffAPI.
-- =========================================================

-- Hot-reload latch (FuelCosts reference): g_currentModDirectory and
-- g_currentModName are nil on a live re-source, so they are latched into
-- module globals on first load, with a g_modsDirectory loose-folder fallback.
ProStaffCoOpModDirectory = ProStaffCoOpModDirectory
    or g_currentModDirectory
    or (g_modsDirectory ~= nil and (g_modsDirectory .. "FS25_ProStaffCoOp/") or nil)
ProStaffCoOpModName = ProStaffCoOpModName or g_currentModName or "FS25_ProStaffCoOp"
local modDirectory = ProStaffCoOpModDirectory

source(modDirectory .. "src/Logger.lua")
source(modDirectory .. "src/ReleaseGate.lua")
source(modDirectory .. "src/ProStaffConstants.lua")
source(modDirectory .. "src/ProStaffManager.lua")
source(modDirectory .. "src/ProStaffAPI.lua")
-- The vendored Option-Scaling resolver (C5 economy-dial reads) before the flush.
source(modDirectory .. "src/OptionScalingResolver.lua")
-- The Co-Op disease flush (C2): extends ProStaffManager, so it is sourced last.
source(modDirectory .. "src/ProStaffDiseaseFlush.lua")

-- Esc RF PDA door (BUILD 00:46): the shared chrome (registry, page class, equal
-- bootstrap) vendored the way the other joiners carry it, then the Pro Staff
-- guest that paints the "prostaff" module. Lua only here; the page XML and the
-- profiles are loaded by RfEscBootstrap.ensureDoor at mission start, not sourced.
source(modDirectory .. "src/ui/RfEscModules.lua")
source(modDirectory .. "src/ui/RfPdaMenuPage.lua")
source(modDirectory .. "src/ui/RfEscBootstrap.lua")
source(modDirectory .. "src/ui/PsGuideDialog.lua")
source(modDirectory .. "src/ui/ProStaffRfPdaGuest.lua")

local proStaff = ProStaffManager.new()
getfenv(0)["g_proStaffCoOp"] = proStaff

local function onMissionLoad(mission)
    if mission ~= nil then
        mission.proStaffManager = proStaff
    end
    PSLogger.info("ProStaff loaded")
end

local function onMissionLoadedFinished()
    proStaff:onMissionLoaded()
end

local function onMissionUpdate(mission, dt)
    proStaff:update(dt)
end

local function onMissionSave()
    proStaff:save()
end

local function onMissionDelete()
    proStaff:onMissionDelete()
    getfenv(0)["g_proStaffCoOp"] = nil
    if g_currentMission ~= nil then
        g_currentMission.proStaffManager = nil
    end
end

Mission00.load = Utils.appendedFunction(Mission00.load, onMissionLoad)
Mission00.loadMission00Finished = Utils.appendedFunction(Mission00.loadMission00Finished, onMissionLoadedFinished)
FSBaseMission.update = Utils.appendedFunction(FSBaseMission.update, onMissionUpdate)

if FSCareerMissionInfo ~= nil and FSCareerMissionInfo.saveToXMLFile ~= nil then
    FSCareerMissionInfo.saveToXMLFile = Utils.appendedFunction(
        FSCareerMissionInfo.saveToXMLFile,
        function() onMissionSave() end
    )
else
    PSLogger.warning("FSCareerMissionInfo.saveToXMLFile not found - ProStaff state will NOT be saved (unless StateLedger present)")
end

FSBaseMission.delete = Utils.prependedFunction(FSBaseMission.delete, onMissionDelete)

local function _rfEscTryRegister()
    if ProStaffRfPdaGuest ~= nil and type(ProStaffRfPdaGuest.tryRegister) == "function" then
        pcall(ProStaffRfPdaGuest.tryRegister)
    end
end

-- Esc RF PDA: register the Pro Staff module after mission/door ready (retry-safe).
if Mission00 ~= nil then
    Mission00.loadMission00Finished = Utils.appendedFunction(Mission00.loadMission00Finished, function()
        _rfEscTryRegister()
    end)
end
if FSBaseMission ~= nil then
    FSBaseMission.onStartMission = Utils.appendedFunction(FSBaseMission.onStartMission, function()
        _rfEscTryRegister()
    end)
end

if FSBaseMission ~= nil then
    FSBaseMission.delete = Utils.appendedFunction(FSBaseMission.delete, function()
        if ProStaffRfPdaGuest ~= nil and type(ProStaffRfPdaGuest.reset) == "function" then
            ProStaffRfPdaGuest.reset()
        end
    end)
end

if addConsoleCommand ~= nil then
    addConsoleCommand("proStaffStatus", "Show ProStaff per-farm level + next cost",
        "consoleCommandStatus", proStaff)
    addConsoleCommand("proStaffBuy", "Buy the next Co-Op level for the local farm",
        "consoleCommandBuy", proStaff)
    addConsoleCommand("proStaffRelease", "Release gate: show STABLE vs experimental-LOCKED systems",
        "consoleCommandRelease", proStaff)
    addConsoleCommand("diseaseFlushQuote", "Show the Co-Op disease flush quote for the local farm",
        "consoleCommandFlushQuote", proStaff)
    addConsoleCommand("diseaseFlush", "Run the Co-Op disease flush for the local farm",
        "consoleCommandFlush", proStaff)
    addConsoleCommand("diseaseClear", "Admin hard-clear of a farm's disease (easy presets only)",
        "consoleCommandClear", proStaff)
end
