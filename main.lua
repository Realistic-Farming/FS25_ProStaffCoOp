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

local modDirectory = g_currentModDirectory

source(modDirectory .. "src/Logger.lua")
source(modDirectory .. "src/ReleaseGate.lua")
source(modDirectory .. "src/ProStaffConstants.lua")
source(modDirectory .. "src/ProStaffManager.lua")
source(modDirectory .. "src/ProStaffAPI.lua")

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

if addConsoleCommand ~= nil then
    addConsoleCommand("proStaffStatus", "Show ProStaff per-farm level + next cost",
        "consoleCommandStatus", proStaff)
    addConsoleCommand("proStaffBuy", "Buy the next Co-Op level for the local farm",
        "consoleCommandBuy", proStaff)
    addConsoleCommand("proStaffRelease", "Release gate: show STABLE vs experimental-LOCKED systems",
        "consoleCommandRelease", proStaff)
end
