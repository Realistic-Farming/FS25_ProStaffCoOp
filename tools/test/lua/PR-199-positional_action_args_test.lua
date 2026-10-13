-- PR-199-positional_action_args_test.lua
--
-- PLAYER-REPORTS row 199 (J. Duke): a joined client's Co-Op level purchase silently did
-- nothing. The three NetworkSync actions (buy, disease flush, admin clear) sent a keyed
-- table, and the transport writes args[1..#args], which for a keyed table is nothing;
-- the server's handler then bailed on the nil. A host never saw it, because
-- requestAction applies in memory there. The senders now send a positional array and
-- the handlers read args[1] as a positive number (a spectator's farm is 0).
--
-- THE ENTRY-POINT BAR DRIVES THE REAL TRANSPORT: a pure client's requestAction, then the
-- real RealisticFarmingActionEvent:writeStream into readStream on the server, then run,
-- then NetworkSync:_applyAction, then the handler ProStaff registered. The transport is
-- FS25_NetworkSync's own code, verbatim at 9e599be (tools/test/lua/networksync_fixture).
-- A bench that handed the table straight to the handler is how this shipped, so no row
-- here does that. The world is engine state (users, farms, balances, a money book); the
-- manager's records are written by the real purchase and flush.
--
--!load: tools/test/lua/networksync_fixture/engine_stubs.lua, tools/test/lua/networksync_fixture/Logger.lua, tools/test/lua/networksync_fixture/RealisticFarmingSyncEvent.lua, tools/test/lua/networksync_fixture/NetworkSync.lua, src/Logger.lua, src/ProStaffConstants.lua, src/OptionScalingResolver.lua, src/ProStaffManager.lua, src/ProStaffAPI.lua, src/ProStaffDiseaseFlush.lua

local WARN = {}
PSLogger.warning = function(fmt, ...) WARN[#WARN + 1] = string.format(fmt, ...) end
PSLogger.info = function() end
PSLogger.debug = function() end
NSLogger.warning = function() end
NSLogger.debug = function() end
NSLogger.error = function(fmt, ...) WARN[#WARN + 1] = "NS " .. string.format(fmt, ...) end

local function group(name, fn)
    local ok, err = pcall(fn)
    if not ok then T.ok(name .. " [group raised: " .. tostring(err) .. "]", false) end
end
local function warned(needle)
    local n = 0
    for _, l in ipairs(WARN) do if l:find(needle, 1, true) then n = n + 1 end end
    return n
end

-- ── engine state ────────────────────────────────────────────────────────────
-- Users: 1 is an admin in farm 1, 2 a member of farm 2, 3 a spectator (farm 0,
-- as FarmManager:getFarmByUserId answers for a user in no farm, FarmManager.lua:201).
local function user(id, farmId, master)
    return { id = id, farmId = farmId, master = master == true,
        getId = function(self) return self.id end,
        getIsMasterUser = function(self) return self.master end,
        getNickname = function(self) return "user" .. self.id end }
end
local USERS = { [1] = user(1, 1, true), [2] = user(2, 2, false), [3] = user(3, 0, false) }
local function conn(u) return { user = u } end
local FROM_ADMIN1, FROM_MEMBER2, FROM_SPECTATOR, UNPLAYERED = conn(USERS[1]), conn(USERS[2]), conn(USERS[3]), conn(nil)

local W = {}
local PRESET = "realistic"   -- the admin clear is granted on the easy presets only ("relaxed")
local hub = {
    registerModule = function() return true end,   -- the settings hub's registration, not the subject
    getValue = function(_, mod, key)
        if mod ~= OptionScalingResolver.MODULE then return nil end
        if key == OptionScalingResolver.PRESET_KEY then return PRESET end
        if key == OptionScalingResolver.dialKey("economy") then return 1.0 end
        if key == OptionScalingResolver.switchKey("economy") then return true end
        return nil
    end,
}
-- Fields for the flush: 101 (diseased) and 102 belong to farm 1, 201 (diseased) to farm 2,
-- and 301 (diseased) is unowned: the farmland manager lists it under owner 0, the value
-- FarmlandManager.NO_OWNER_FARM_ID shares with the spectator farm, which is why a
-- spectator's 0 must never reach the flush.
local function fieldData()
    return { [101] = { activeDisease = "septoria_tritici", diseasePressure = 60, fungicideDaysLeft = 0, discovered = true },
             [102] = { activeDisease = nil, diseasePressure = 5, fungicideDaysLeft = 0 },
             [201] = { activeDisease = "late_blight", diseasePressure = 30, fungicideDaysLeft = 0, discovered = true },
             [301] = { activeDisease = "late_blight", diseasePressure = 45, fungicideDaysLeft = 0, discovered = true } }
end
local OWNED = { [0] = { 301 }, [1] = { 101, 102 }, [2] = { 201 } }
local function soilSystemFor(fd)
    local function owns(farmId, fieldId)
        for _, id in ipairs(OWNED[farmId] or {}) do if id == fieldId then return true end end
        return false
    end
    return {
        fieldData = fd,
        getScoutReport = function(_, fieldId)
            local f = fd[fieldId]
            if not f or not f.activeDisease then return { fieldId = fieldId, enabled = true, discovered = f ~= nil and f.discovered == true, pressure = (f and f.diseasePressure) or 0, tier = "none" } end
            if not f.discovered then return { fieldId = fieldId, enabled = true, discovered = false, pressure = f.diseasePressure, tier = "unknown" } end
            return { fieldId = fieldId, enabled = true, discovered = true, pressure = f.diseasePressure, tier = "mild", diseaseId = f.activeDisease,
                     recommend = { best = "TEBUCONAZOLE", second = "PROPICONAZOLE", budget = "MANCOZEB" } }
        end,
        scoutField = function(self, fieldId, farmId)
            if owns(farmId, fieldId) and fd[fieldId] then fd[fieldId].discovered = true end
            return self:getScoutReport(fieldId)
        end,
        applyNamedFungicide = function(_, fieldId, chemId, opts)
            W.applied[#W.applied + 1] = { fieldId = fieldId, chemId = chemId, farmId = opts and opts.farmId }
            local f = fd[fieldId]
            if f then f.diseasePressure = math.max(0, (f.diseasePressure or 0) - 60) end
            return true, "sf_treat_done", {}
        end,
        debugSetDisease = function(_, fieldId, pressure)
            W.cleared[#W.cleared + 1] = { fieldId = fieldId, pressure = pressure }
            if fd[fieldId] then fd[fieldId].diseasePressure = pressure or 0 end
            return true, {}
        end,
    }
end
--- The server world: NetworkSync's core with ProStaff bound to it, users, farms with
--- money, a money book. Returns the server's manager.
local function serverWorld()
    W.debits, W.applied, W.cleared, W.sent = {}, {}, {}, {}
    W.nsServer = NetworkSync.new()
    W.fields = fieldData()
    W.serverMission = {
        _isServer = true, getIsServer = function(self) return self._isServer end,
        getFarmId = function() return 1 end,
        userManager = { getUserByConnection = function(_, c) return c and c.user or nil end },
        addMoney = function(_, amount, farmId, moneyType) W.debits[#W.debits + 1] = { amount = amount, farmId = farmId } end,
        soilFertilityManager = { soilSystem = soilSystemFor(W.fields) },
        settingsHub = hub, networkSync = W.nsServer,
    }
    g_currentMission = W.serverMission
    g_networkSync = W.nsServer
    g_server = { broadcastEvent = function() end }
    g_client = nil
    g_farmManager = {
        getFarmById = function(_, id) return { farmId = id, money = 50000, getBalance = function() return 50000 end } end,
        getFarmByUserId = function(_, userId) local u = USERS[userId] if u == nil then return nil end return { farmId = u.farmId } end,
    }
    g_farmlandManager = { getOwnedFarmlandIdsByFarmId = function(_, farmId) return OWNED[farmId] or {} end }
    local ms = ProStaffManager.new()
    ms.settings.enabled = true
    ms:_bindBedrock()
    ms:bindDiseaseFlush()
    W.ms = ms
    return ms
end
--- A pure client of farm `farmId` (0 for a spectator): its own NetworkSync core and
--- manager; what it sends is recorded.
local function asClient(farmId, fn)
    local nsClient = NetworkSync.new()
    local mission = { _isServer = false, getIsServer = function(self) return self._isServer end,
                      getFarmId = function() return farmId end, settingsHub = hub, networkSync = nsClient }
    local saved = { g_currentMission, g_networkSync, g_server, g_client }
    g_currentMission, g_networkSync, g_server = mission, nsClient, nil
    g_client = { getServerConnection = function() return { sendEvent = function(_, ev) W.sent[#W.sent + 1] = ev end } end }
    local mc = ProStaffManager.new()
    mc.settings.enabled = true
    local ok, err = pcall(fn, mc)
    g_currentMission, g_networkSync, g_server, g_client = saved[1], saved[2], saved[3], saved[4]
    if not ok then error(err, 0) end
end
--- The engine's delivery of what the client sent: the sender's writeStream, the
--- server's readStream (which runs, applies through NetworkSync and reaches the
--- handler). Returns the received event and the stream's faults.
local function deliver(ev, connection)
    local s = NewTypedStream()
    ev:writeStream(s, nil)
    local rx = RealisticFarmingActionEvent.emptyNew()
    rx:readStream(s, connection)
    return rx, TypedStreamFaults(s)
end
local function debits()
    local out = {}
    for _, d in ipairs(W.debits) do out[#out + 1] = d.farmId .. ":" .. d.amount end
    return table.concat(out, ",")
end
local function level(farmId) local r = W.ms.farms[farmId] return r and r.level or 0 end

-- ══════════════════════════════════════════════════════════════════════════
-- A. THE WIRE CARRIES THE FARM
-- ══════════════════════════════════════════════════════════════════════════
group("A", function()
    serverWorld()
    asClient(1, function(mc) mc:buyLevel(1) end)
    local ev = W.sent[1]
    T.eq("A1 a client's purchase sends one action event whose args are a positional array of one farm id",
        #W.sent .. "/" .. tostring(ev and ev.actionId) .. "/" .. tostring(ev and #ev.args) .. "/" .. tostring(ev and ev.args[1]), "1/" .. ProStaffConstants.ACTION_BUY .. "/1/1")
    local s = NewTypedStream()
    ev:writeStream(s, nil)
    local rx = RealisticFarmingActionEvent.emptyNew()
    rx.actionId = streamReadString(s)
    local n = streamReadInt32(s)
    T.eq("A2 the transport writes that one value (a keyed table wrote none)", n .. "/" .. tostring(RealisticFarmingSyncEvent.readValue(s)) .. "/" .. TypedStreamFaults(s), "1/1/0")
end)

-- ══════════════════════════════════════════════════════════════════════════
-- B. THE PURCHASE THROUGH THE REAL TRANSPORT
-- ══════════════════════════════════════════════════════════════════════════
group("B", function()
    serverWorld()
    asClient(1, function(mc) mc:buyLevel(1) end)
    local _, faults = deliver(W.sent[1], FROM_ADMIN1)
    local cost = W.ms:levelCost(1, 1)
    T.eq("B1 a member buying for its own farm: the level is bought once and its farm is charged the level's cost",
        level(1) .. "/" .. debits() .. "/" .. faults, "1/1:-" .. cost .. "/0")
    asClient(1, function(mc) mc:buyLevel(2) end)
    deliver(W.sent[2], FROM_ADMIN1)
    T.eq("B2 a member naming another farm is refused: nothing bought, nothing charged, the refusal logged",
        level(2) .. "/" .. #W.debits .. "/" .. warned("ACTION_BUY rejected"), "0/1/1")
    asClient(0, function(mc) mc:buyLevel(0) end)
    local ev = W.sent[3]
    deliver(ev, FROM_SPECTATOR)
    T.eq("B3 a spectator (farm 0) sends 0 and is refused before the ownership equality could pass",
        tostring(ev.args[1]) .. "/" .. tostring(W.ms.farms[0]) .. "/" .. #W.debits, "0/nil/1")
    asClient(1, function(mc) mc:buyLevel(1) end)
    deliver(W.sent[4], UNPLAYERED)
    T.eq("B4 a connection with no user is refused", level(1) .. "/" .. #W.debits, "1/1")
    W.ms:buyLevel(1)
    T.eq("B5 the host's own path is unchanged: applied in memory, no event", level(1) .. "/" .. #W.debits .. "/" .. #W.sent, "2/2/4")
    asClient(1, function(mc) mc:buyLevel(1) mc:buyLevel(1) end)
    T.eq("B6 one press sends one request (two presses, two)", #W.sent, 6)
end)

-- ══════════════════════════════════════════════════════════════════════════
-- C. THE FLUSH AND THE ADMIN CLEAR
-- ══════════════════════════════════════════════════════════════════════════
group("C", function()
    serverWorld()
    asClient(1, function(mc) mc:requestFarmFlush(1) end)
    deliver(W.sent[1], FROM_ADMIN1)
    T.eq("C1 a member's flush of its own farm treats its diseased field and charges its farm",
        #W.applied .. "/" .. tostring(W.applied[1] and W.applied[1].fieldId) .. "/" .. tostring(W.debits[1] and W.debits[1].farmId), "1/101/1")
    asClient(2, function(mc) mc:requestFarmFlush(1) end)
    deliver(W.sent[2], FROM_MEMBER2)
    T.eq("C2 a member of farm 2 flushing farm 1 is refused", #W.applied .. "/" .. #W.debits .. "/" .. warned("ACTION_FLUSH rejected"), "1/1/1")
    -- A fresh world (field 101 diseased again): a 0 that reached the flush would resolve to
    -- the host's farm (_resolveFarm) and treat farm 1's field at farm 1's cost.
    serverWorld()
    asClient(0, function(mc) mc:requestFarmFlush(0) end)
    deliver(W.sent[1], FROM_SPECTATOR)
    T.eq("C3 a spectator's flush of farm 0 is refused before it could resolve to the host's farm: nothing treated, nothing charged", #W.applied .. "/" .. #W.debits, "0/0")
    -- A fresh world for the clear: C1 already treated field 101 below the flush onset.
    serverWorld()
    PRESET = "relaxed"
    asClient(1, function(mc) mc:requestAdminClear(1) end)
    deliver(W.sent[1], FROM_ADMIN1)
    T.eq("C4 an admin's clear of farm 1 (on an easy preset) clears its diseased field", #W.cleared .. "/" .. tostring(W.cleared[1] and W.cleared[1].fieldId), "1/101")
    asClient(2, function(mc) mc:requestAdminClear(2) end)
    deliver(W.sent[2], FROM_MEMBER2)
    T.eq("C5 a non-admin's clear is denied by NetworkSync's admin gate", #W.cleared, 1)
    PRESET = "realistic"
end)

T.summary()
