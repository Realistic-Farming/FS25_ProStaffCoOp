-- =========================================================
-- FS25_ProStaffCoOp - central manager (per-farm progression state)
-- =========================================================
-- Author: TisonK
-- =========================================================
-- Owns the per-farm Co-Op level + investment state, the level-cost formula with
-- the wealth-bracket escalator, and ProStaff's OWN server-authoritative money
-- write for every rung cost / rebate / fee (routed through NetworkSync's action
-- channel in MP; direct on the server). TaxMod recordExpense is audit-only.
-- Recurring money (the agronomy fee, the L14 fleet rebate) settles on the Time
-- Guard calendar tick. The getters live in ProStaffAPI.lua (extends this class).
-- =========================================================

ProStaffManager = {}
local ProStaffManager_mt = Class(ProStaffManager)

function ProStaffManager.new()
    local self = setmetatable({}, ProStaffManager_mt)
    self.farms = {}          -- farmId -> { level, investmentTotal, levelHistory, membershipActive }
    self.pfActive = false
    self.bedrockBound = false
    self.clockBound = false
    self.settings = {
        enabled = true,
        baseCost = ProStaffConstants.DEFAULT_BASE_COST,
        subscriptionFeeEnabled = false,
        agronomyFee = ProStaffConstants.AGRONOMY_FEE.DEFAULT,
    }
    return self
end

-- =========================================================
-- Lifecycle
-- =========================================================

function ProStaffManager:onMissionLoaded()
    -- PF disables ONLY the soil-related (fertilizer/fungicide) modifiers; the
    -- progression and every other modifier stay active.
    self.pfActive = (g_modIsLoaded ~= nil and g_modIsLoaded["FS25_precisionFarming"]) or false
    if self.pfActive then
        PSLogger.info("Precision Farming detected - soil-related modifiers disabled, progression active")
    end

    self:_bindBedrock()
    local ledger = self:_getLedger()
    if ledger == nil then self:_loadOwnFile() end

    self:_subscribeClock()
    PSLogger.info("ProStaff active (%d farm record(s))", self:_countFarms())
end

function ProStaffManager:update(dt)
    if not self.bedrockBound then self:_bindBedrock() end
    if not self.clockBound then self:_subscribeClock() end
end

function ProStaffManager:onMissionDelete()
    self.bedrockBound = false
    self.clockBound = false
end

function ProStaffManager:save()
    if self:_getLedger() ~= nil then return end
    if g_currentMission == nil or not g_currentMission:getIsServer() then return end
    self:_saveOwnFile()
end

function ProStaffManager:_isServer()
    return g_currentMission ~= nil and g_currentMission:getIsServer()
end

function ProStaffManager:_countFarms()
    local n = 0
    for _ in pairs(self.farms) do n = n + 1 end
    return n
end

function ProStaffManager:_getFarmRecord(farmId)
    local rec = self.farms[farmId]
    if rec == nil then
        rec = { level = 0, investmentTotal = 0, levelHistory = {}, membershipActive = true }
        self.farms[farmId] = rec
    end
    return rec
end

-- =========================================================
-- Handles
-- =========================================================
function ProStaffManager:_getLedger()      return (g_currentMission and g_currentMission.stateLedger) or g_stateLedger end
function ProStaffManager:_getNetworkSync()  return (g_currentMission and g_currentMission.networkSync) or g_networkSync end
function ProStaffManager:_getSettingsHub()  return (g_currentMission and g_currentMission.settingsHub) or g_settingsHub end
function ProStaffManager:_getTimeGuard()    return (g_currentMission and g_currentMission.timeGuard) or g_timeGuard end

-- =========================================================
-- Level cost + wealth bracket
-- =========================================================

-- Farm net worth read (balance + assets). Asset-value read is best-effort; the
-- balance is the reliable component, assets a refinement (base-game asset-sum API
-- is not consistently exposed). Cannot be gamed by spending down cash (F5-F).
function ProStaffManager:_netWorth(farmId)
    local worth = 0
    pcall(function()
        local farm = g_farmManager ~= nil and g_farmManager:getFarmById(farmId) or nil
        if farm ~= nil then
            worth = farm.money or 0
            if farm.getBalance ~= nil then worth = farm:getBalance() end
            if type(farm.getFinanceStats) == "function" then
                local ok, assets = pcall(function() return farm:getFinanceStats("assets") end)
                if ok and type(assets) == "number" then worth = worth + assets end
            end
        end
    end)
    return worth
end

function ProStaffManager:wealthBracket(farmId, targetLevel)
    if targetLevel < ProStaffConstants.WEALTH_BRACKET.ACTIVATES_AT_LEVEL then
        return 1.0
    end
    local worth = self:_netWorth(farmId)
    for _, tier in ipairs(ProStaffConstants.WEALTH_BRACKET.TIERS) do
        if worth < tier.max then return tier.mult end
    end
    return ProStaffConstants.WEALTH_BRACKET.TIERS[#ProStaffConstants.WEALTH_BRACKET.TIERS].mult
end

function ProStaffManager:levelCost(farmId, targetLevel)
    if targetLevel > ProStaffConstants.MAX_LEVEL then return nil end
    local base = (targetLevel ^ ProStaffConstants.COST_EXPONENT) * self.settings.baseCost
    return math.floor(base * self:wealthBracket(farmId, targetLevel))
end

function ProStaffManager:getNextLevelCost(farmId)
    farmId = self:_resolveFarm(farmId)
    local rec = self:_getFarmRecord(farmId)
    if rec.level >= ProStaffConstants.MAX_LEVEL then return nil end
    return self:levelCost(farmId, rec.level + 1)
end

-- =========================================================
-- Purchase (ProStaff's own server-authoritative money write)
-- =========================================================

-- Entry point. On the server (incl. SP) it purchases directly; a MP client
-- routes the request through NetworkSync's action channel.
function ProStaffManager:buyLevel(farmId)
    farmId = self:_resolveFarm(farmId)
    if not self.settings.enabled then return false end
    if self:_isServer() then
        return self:_doPurchase(farmId)
    end
    local ns = self:_getNetworkSync()
    if ns ~= nil and ns.requestAction ~= nil then
        ns:requestAction(ProStaffConstants.ACTION_BUY, { farmId = farmId })
        return true
    end
    PSLogger.warning("buyLevel: no server authority and NetworkSync absent - cannot purchase on a pure client")
    return false
end

-- Server-side actual purchase: validate funds, debit, level up, audit, sync.
function ProStaffManager:_doPurchase(farmId)
    if not self:_isServer() then return false end
    local rec = self:_getFarmRecord(farmId)
    if rec.level >= ProStaffConstants.MAX_LEVEL then return false end

    local targetLevel = rec.level + 1
    local cost = self:levelCost(farmId, targetLevel)
    if cost == nil then return false end

    -- Fund check.
    local balance = 0
    pcall(function()
        local farm = g_farmManager ~= nil and g_farmManager:getFarmById(farmId) or nil
        balance = (farm ~= nil and (farm.money or (farm.getBalance and farm:getBalance()))) or 0
    end)
    if balance < cost then
        PSLogger.info("Purchase denied for farm %d: cost %d exceeds balance %d", farmId, cost, balance)
        return false
    end

    -- Debit via base-game addMoney (server-authoritative). Then audit via TaxMod.
    pcall(function()
        g_currentMission:addMoney(-cost, farmId, MoneyType.OTHER, true, true)
    end)
    self:_taxAudit(farmId, -cost, ProStaffConstants.LABELS.INVESTMENT)

    rec.level = targetLevel
    rec.investmentTotal = (rec.investmentTotal or 0) + cost
    table.insert(rec.levelHistory, { level = targetLevel, cost = cost })
    PSLogger.info("Farm %d reached Co-Op Level %d (%s), cost %d",
        farmId, targetLevel, ProStaffConstants.LEVEL_NAMES[targetLevel] or "?", cost)

    self:_markDirty()
    return true
end

function ProStaffManager:_taxAudit(farmId, amount, label)
    pcall(function()
        local tm = g_currentMission ~= nil and g_currentMission.taxManager
        if tm ~= nil and tm.recordExpense ~= nil then
            tm:recordExpense(farmId, amount, label)
        end
    end)
end

-- =========================================================
-- Recurring money (Time Guard accrue-and-settle)
-- =========================================================

function ProStaffManager:_subscribeClock()
    if self.clockBound then return end
    local tg = self:_getTimeGuard()
    if tg == nil or tg.registerAccrual == nil then return end

    -- Agronomy report subscription (difficulty-gated; monthly cadence).
    tg:registerAccrual("ProStaffCoOp_agronomyFee", {
        cadence = ProStaffConstants.AGRONOMY_FEE.CADENCE, flowClass = "calendar",
        firstPeriodPolicy = "skip", priority = ProStaffConstants.SETTLE_PRIORITY,
        onSettle = function(sctx) self:_settleAgronomyFee(sctx) end,
    })
    -- L14 fleet rebate (credit), monthly cadence.
    tg:registerAccrual("ProStaffCoOp_fleetRebate", {
        cadence = "month", flowClass = "calendar",
        firstPeriodPolicy = "skip", priority = ProStaffConstants.SETTLE_PRIORITY,
        onSettle = function(sctx) self:_settleFleetRebate(sctx) end,
    })
    self.clockBound = true
end

function ProStaffManager:_settleAgronomyFee(sctx)
    if not self:_isServer() or not self.settings.subscriptionFeeEnabled then return end
    local n = (sctx and sctx.boundariesCrossed) or 1
    for farmId, rec in pairs(self.farms) do
        if rec.level >= ProStaffConstants.FLAGS.hasForecastAccess then
            local fee = self.settings.agronomyFee * n
            pcall(function() g_currentMission:addMoney(-fee, farmId, MoneyType.OTHER, true, true) end)
            self:_taxAudit(farmId, -fee, ProStaffConstants.AGRONOMY_FEE.LABEL)
        end
    end
end

function ProStaffManager:_settleFleetRebate(sctx)
    if not self:_isServer() then return end
    local n = (sctx and sctx.boundariesCrossed) or 1
    for farmId, rec in pairs(self.farms) do
        if rec.level >= 14 then
            local credit = ProStaffConstants.L14_FLEET_REBATE * n
            pcall(function() g_currentMission:addMoney(credit, farmId, MoneyType.OTHER, true, true) end)
            self:_taxAudit(farmId, credit, ProStaffConstants.LABELS.FLEET_REBATE)
        end
    end
end

-- =========================================================
-- Bedrock (delegate-when-present)
-- =========================================================

function ProStaffManager:_markDirty()
    local ns = self:_getNetworkSync()
    if ns ~= nil and self:_isServer() and ns.markDirty ~= nil then
        ns:markDirty(ProStaffConstants.NETWORK_CHANNEL)
    end
end

function ProStaffManager:_bindBedrock()
    if self.bedrockBound then return end
    local bound = false

    local ledger = self:_getLedger()
    if ledger ~= nil then
        ledger:registerModule(ProStaffConstants.LEDGER_STATE, {
            serialize   = function() return self:_serialize() end,
            deserialize = function(data) self:_deserialize(data) end,
        })
        bound = true
    end

    local ns = self:_getNetworkSync()
    if ns ~= nil then
        ns:registerModule(ProStaffConstants.NETWORK_CHANNEL, {
            channel      = ProStaffConstants.NETWORK_CHANNEL,
            onWriteState = function() return self:_onWriteState() end,
            onReadState  = function(arr) self:_onReadState(arr) end,
        })
        -- The sanctioned client-to-server purchase action (server-authorized).
        if ns.registerAction ~= nil then
            ns:registerAction(ProStaffConstants.ACTION_BUY, {
                adminOnly = false,
                onAction = function(userId, args)
                    if type(args) == "table" and args.farmId ~= nil then
                        self:_doPurchase(args.farmId)
                    end
                end,
            })
        end
        bound = true
    end

    local hub = self:_getSettingsHub()
    if hub ~= nil then
        hub:registerModule("ProStaffCoOp", {
            selfPersisted = true,
            adminSettings = {
                { id = "enabled", type = "bool", default = true, adminOnly = true, label = "Pro Staff Co-Op Enabled" },
                { id = "baseCost", type = "int", default = 260, min = 50, max = 2000, adminOnly = true,
                  label = "Level Base Cost" },
                { id = "subscriptionFeeEnabled", type = "bool", default = false, adminOnly = true,
                  label = "Agronomy Report Sub Fee" },
                { id = "agronomyFee", type = "int", default = 800, min = 0, max = 10000, adminOnly = true,
                  label = "Agronomy Fee (per month)" },
            },
            onChange = function(key, value)
                if key == "enabled" then self.settings.enabled = value ~= false
                elseif key == "baseCost" then self.settings.baseCost = value
                elseif key == "subscriptionFeeEnabled" then self.settings.subscriptionFeeEnabled = value ~= false
                elseif key == "agronomyFee" then self.settings.agronomyFee = value end
            end,
        })
        bound = true
    end

    if bound then self.bedrockBound = true end
end

-- =========================================================
-- Serialization
-- =========================================================

function ProStaffManager:_serialize()
    local out = {}
    for farmId, rec in pairs(self.farms) do
        out[tostring(farmId)] = { level = rec.level, investmentTotal = rec.investmentTotal,
                                  membershipActive = rec.membershipActive ~= false }
    end
    return out
end

function ProStaffManager:_deserialize(data)
    if type(data) ~= "table" then return end
    for key, s in pairs(data) do
        local farmId = tonumber(key) or key
        self.farms[farmId] = { level = s.level or 0, investmentTotal = s.investmentTotal or 0,
                               membershipActive = s.membershipActive ~= false, levelHistory = {} }
    end
end

function ProStaffManager:_onWriteState()
    local arr = {}
    for farmId, rec in pairs(self.farms) do
        arr[#arr + 1] = tostring(farmId)
        arr[#arr + 1] = rec.level or 0
    end
    return arr
end

function ProStaffManager:_onReadState(arr)
    if type(arr) ~= "table" then return end
    local i = 1
    while i + 1 <= #arr do
        local farmId = tonumber(arr[i]) or arr[i]
        local rec = self:_getFarmRecord(farmId)
        rec.level = arr[i + 1]
        i = i + 2
    end
end

-- =========================================================
-- Own-file persistence fallback (only when StateLedger absent)
-- =========================================================

function ProStaffManager:_savePath()
    if g_currentMission == nil or g_currentMission.missionInfo == nil
        or g_currentMission.missionInfo.savegameDirectory == nil then return nil end
    return g_currentMission.missionInfo.savegameDirectory .. "/FS25_ProStaffCoOp.xml"
end

function ProStaffManager:_saveOwnFile()
    local path = self:_savePath()
    if path == nil then return end
    local xml = XMLFile.create("ps_SaveXML", path, "proStaff")
    if xml == nil then return end
    local i = 0
    for farmId, rec in pairs(self.farms) do
        local key = string.format("proStaff.farm(%d)", i)
        xml:setInt(key .. "#id", tonumber(farmId) or 0)
        xml:setInt(key .. "#level", rec.level or 0)
        xml:setInt(key .. "#investment", math.floor(rec.investmentTotal or 0))
        i = i + 1
    end
    xml:save()
    xml:delete()
end

function ProStaffManager:_loadOwnFile()
    local path = self:_savePath()
    if path == nil then return end
    local xml = XMLFile.loadIfExists("ps_SaveXML", path, "proStaff")
    if xml == nil then return end
    xml:iterate("proStaff.farm", function(_, key)
        local id = xml:getInt(key .. "#id", nil)
        if id ~= nil then
            self.farms[id] = { level = xml:getInt(key .. "#level", 0),
                               investmentTotal = xml:getInt(key .. "#investment", 0),
                               membershipActive = true, levelHistory = {} }
        end
    end)
    xml:delete()
end

-- =========================================================
-- Console
-- =========================================================

function ProStaffManager:consoleCommandBuy()
    local farmId = self:_resolveFarm(nil)
    local rec = self:_getFarmRecord(farmId)
    local before = rec.level
    local ok = self:buyLevel(farmId)
    if ok and self:_isServer() then
        return string.format("Farm %d: L%d -> L%d", farmId, before, rec.level)
    elseif ok then
        return "Purchase requested from the server."
    end
    return "Purchase failed (funds, max level, or disabled)."
end

function ProStaffManager:consoleCommandStatus()
    local lines = {}
    table.insert(lines, string.format("ProStaff: %s, pfActive=%s, farms=%d, baseCost=%d, bedrock=%s",
        self.settings.enabled and "enabled" or "disabled", tostring(self.pfActive),
        self:_countFarms(), self.settings.baseCost, tostring(self.bedrockBound)))
    for farmId, rec in pairs(self.farms) do
        local nextCost = self:getNextLevelCost(farmId)
        table.insert(lines, string.format("  farm %s: L%d (%s), invested=%d, next=%s",
            tostring(farmId), rec.level, ProStaffConstants.LEVEL_NAMES[rec.level] or "-",
            math.floor(rec.investmentTotal or 0), nextCost ~= nil and tostring(nextCost) or "MAX"))
    end
    return table.concat(lines, "\n")
end
