-- =========================================================
-- FS25_ProStaffCoOp - Disease Flush (C2), the recovery hatch
-- =========================================================
-- Author: TisonK
-- =========================================================
-- The buildable core of the disease-flush safety net (DISEASE-FLUSH-C2): a thin
-- SERVER-AUTHORITATIVE ProStaff action that triggers SoilFertilizer's OWN
-- treat/clear across a farm's diseased fields and books the locked C5 fee
-- server-side.
--
--   * TREAT (hard presets, and the fail-safe when the spine is absent): per
--     diseased field, scout (the Co-Op flush IS the ProStaff report path that
--     reveals an infection, designed in at SoilFertilitySystem.lua:2321), pick
--     the recommended fungicide, then
--     applyNamedFungicide(fieldId, chemId, { charge = false, farmId = farmId }).
--     SF's real treatment REDUCES pressure by its own effectiveness and clears
--     the named infection only below onset (a severe field may need a repeat
--     flush, cheaper as severity drops). We never bill SF's own chem price;
--     the flush books the C5 price itself.
--   * CLEAR (easy presets only): the server-gated wrapper around SF's
--     debugSetDisease(fieldId, 0), which is NOT client-safe, so the wrapper is
--     server-only. Difficulty-gated: allowed strictly below the realistic preset
--     rank, blocked on realistic/punishing, and blocked when the spine is absent
--     (fail-safe: no hard-clear without an explicit easy preset).
--   * ONE PRICE, THE C5 CURVE: (250 + 8 * severity) * economyHatchMultiplier,
--     booked via ProStaff's own server-authoritative addMoney (MoneyType.OTHER,
--     the same type as the membership investment) and audited through TaxMod.
--     Neutral 1.0 multiplier when the spine is absent. Fund-checked like a
--     purchase; denied without the balance.
--   * PER-FARM CONCURRENT GUARD: a transient flag per farm, set on entry, cleared
--     on resolution, so a double-fire cannot double-charge or double-treat.
--
-- The player-facing paid flush surface (the Co-Op prompt) is GATED on FarmTablet;
-- this module is the mechanism that surface calls. Console commands drive it today.
--
-- This module EXTENDS the ProStaffManager class (sourced after ProStaffManager.lua
-- and ProStaffAPI.lua, and after the vendored OptionScalingResolver.lua).
-- =========================================================

-- =========================================================
-- Entry points (client or server)
-- =========================================================

--- Client-to-server / server-direct request to run the Co-Op disease flush for a
--- farm: treat (hard presets / spine absent) or clear (easy presets), at the C5
--- price. A client routes the request through NetworkSync's action channel; the
--- server applies it directly.
---@param farmId number|nil farm id (defaults to the local farm)
---@return boolean ok, string reason
function ProStaffManager:requestFarmFlush(farmId)
    farmId = self:_resolveFarm(farmId)
    if not self.settings.enabled then return false, "disabled" end
    if self:_isServer() then
        return self:_doFarmFlush(farmId)
    end
    local ns = self:_getNetworkSync()
    if ns ~= nil and ns.requestAction ~= nil then
        ns:requestAction(ProStaffConstants.ACTION_FLUSH, { farmId = farmId })
        return true, "requested"
    end
    PSLogger.warning("requestFarmFlush: no server authority and NetworkSync absent - cannot flush on a pure client")
    return false, "no_network"
end

--- Admin-gated request to hard-clear a farm's disease (the server wrapper around
--- SF's debugSetDisease). Difficulty-gated to the easy presets only.
---@param farmId number|nil
---@return boolean ok, string reason
function ProStaffManager:requestAdminClear(farmId)
    farmId = self:_resolveFarm(farmId)
    if not self.settings.enabled then return false, "disabled" end
    if self:_isServer() then
        return self:_doAdminClear(farmId)
    end
    local ns = self:_getNetworkSync()
    if ns ~= nil and ns.requestAction ~= nil then
        ns:requestAction(ProStaffConstants.ACTION_CLEAR, { farmId = farmId })
        return true, "requested"
    end
    PSLogger.warning("requestAdminClear: no server authority and NetworkSync absent")
    return false, "no_network"
end

-- =========================================================
-- Quote (pure read - safe for console / a future FarmTablet surface)
-- =========================================================

--- A read-only quote for the flush: which fields, the per-field C5 fee, the total,
--- and the character. The chem shown is best-effort (SF's report only names the
--- recommendation once a field is scouted); the execution re-selects after scouting.
---@param farmId number|nil
---@return table quote { character, economyMultiplier, clearAllowed, fields = { {fieldId, pressure, diseaseId, chemId, fee} }, diseasedCount, totalCost }
function ProStaffManager:diseaseFlushQuote(farmId)
    farmId = self:_resolveFarm(farmId)
    local character = self:_flushCharacter()
    local mult = self:_economyHatchMultiplier()
    local fields = {}
    local total = 0
    for _, f in ipairs(self:_farmDiseaseReport(farmId)) do
        local fee = self:_flushFee(f.pressure, mult)
        total = total + fee
        fields[#fields + 1] = {
            fieldId = f.fieldId,
            pressure = f.pressure,
            diseaseId = f.diseaseId,
            chemId = self:_chemFor(f.fieldId),
            fee = fee,
        }
    end
    return {
        character = character,
        economyMultiplier = mult,
        clearAllowed = self:_flushClearAllowed(),
        fields = fields,
        diseasedCount = #fields,
        totalCost = total,
    }
end

-- =========================================================
-- Server-authoritative execution
-- =========================================================

--- Server-side flush: guard, price, fund-check, book the C5 fee, then treat (or
--- clear on easy presets) every diseased field through SF's own surface.
---@param farmId number
---@return boolean ok, string reason
function ProStaffManager:_doFarmFlush(farmId)
    if not self:_isServer() then return false, "server_only" end
    farmId = self:_resolveFarm(farmId)
    if self.flushGuard[farmId] then
        PSLogger.info("Flush skipped for farm %d: a flush is already running", farmId)
        return false, "busy"
    end
    self.flushGuard[farmId] = true
    local results = { pcall(function() return self:_flushLocked(farmId) end) }
    self.flushGuard[farmId] = nil
    if not results[1] then
        PSLogger.warning("Flush failed for farm %d: %s", farmId, tostring(results[2]))
        return false, "error"
    end
    return results[2], results[3]
end

--- The actual flush work, run with the per-farm guard held.
function ProStaffManager:_flushLocked(farmId)
    local character = self:_flushCharacter()
    local mult = self:_economyHatchMultiplier()
    local fields = self:_farmDiseaseReport(farmId)
    if #fields == 0 then return false, "none" end

    local total = 0
    for _, f in ipairs(fields) do
        total = total + self:_flushFee(f.pressure, mult)
    end

    -- Fund-check like any ProStaff purchase; the flush is a service the farm buys.
    if not self:_farmHasFunds(farmId, total) then
        PSLogger.info("Flush denied for farm %d: C5 fee %d exceeds balance", farmId, total)
        return false, "funds"
    end

    -- Book the fee up front (pay per treatment; the fee itself is the anti-abuse).
    if total > 0 then
        self:_bookFlushFee(farmId, total)
    end

    if character == "clear" then
        for _, f in ipairs(fields) do
            self:_sfDebugClear(f.fieldId)
        end
    else
        for _, f in ipairs(fields) do
            self:_sfTreat(f.fieldId, farmId)
        end
    end

    PSLogger.info("Farm %d disease flush: %s, %d field(s), C5 fee %d (mult %.2f)",
        farmId, character, #fields, total, mult)
    return true, "done"
end

--- Admin hard-clear wrapper (server-only): the difficulty-gated, fee-free admin
--- tool around SF's debugSetDisease. Blocked unless an easy preset grants it.
---@param farmId number
---@return boolean ok, string reason
function ProStaffManager:_doAdminClear(farmId)
    if not self:_isServer() then return false, "server_only" end
    farmId = self:_resolveFarm(farmId)
    if not self:_flushClearAllowed() then
        PSLogger.info("Admin clear denied for farm %d: the hard-clear is easy-preset only", farmId)
        return false, "blocked"
    end
    if self.flushGuard[farmId] then return false, "busy" end
    self.flushGuard[farmId] = true
    local results = { pcall(function()
        local fields = self:_farmDiseaseReport(farmId)
        for _, f in ipairs(fields) do
            self:_sfDebugClear(f.fieldId)
        end
        return #fields > 0, (#fields > 0) and "done" or "none"
    end) }
    self.flushGuard[farmId] = nil
    if not results[1] then
        PSLogger.warning("Admin clear failed for farm %d: %s", farmId, tostring(results[2]))
        return false, "error"
    end
    return results[2], results[3]
end

-- =========================================================
-- The C5 price + the difficulty character
-- =========================================================

--- The C5 per-field fee for a severity, times the locked hatch multiplier.
---@param severity number SF pressure 0-100
---@param economyMultiplier number|nil 1.0 when nil
---@return number fee (floored, >= 0)
function ProStaffManager:_flushFee(severity, economyMultiplier)
    local base = ProStaffConstants.DISEASE_FLUSH.PER_FIELD_BASE
    local rate = ProStaffConstants.DISEASE_FLUSH.SEVERITY_RATE
    local mult = economyMultiplier or 1.0
    if mult < 0 then mult = 0 end
    return math.floor(math.max(0, (base + rate * (severity or 0)) * mult))
end

--- Is the difficulty-gated hard-clear (debugSetDisease to 0) allowed? Allowed
--- strictly below the realistic preset rank. FAIL-SAFE: blocked when the spine is
--- absent (a hard-clear needs an explicit easy preset, never a default).
---@return boolean
function ProStaffManager:_flushClearAllowed()
    local profile = self:_spineProfile()
    if profile == nil then return false end
    local rank = ProStaffConstants.DISEASE_FLUSH.PRESET_RANK[profile.preset]
    if rank == nil then rank = ProStaffConstants.DISEASE_FLUSH.PRESET_RANK.standard end
    return rank < ProStaffConstants.DISEASE_FLUSH.PRESET_RANK.realistic
end

--- The flush character from the preset: "clear" on easy presets, "treat"
--- otherwise (realistic/punishing and the spine-absent fail-safe).
---@return string "clear" | "treat"
function ProStaffManager:_flushCharacter()
    if self:_flushClearAllowed() then return "clear" end
    return "treat"
end

--- The C5 recovery-hatch multiplier off the Economy dial, resolved through the
--- vendored Option-Scaling resolver (delegate-when-present). NEUTRAL 1.0 when the
--- spine is absent, the dial is switched off, or the resolve throws.
---@return number multiplier
function ProStaffManager:_economyHatchMultiplier()
    local profile = self:_spineProfile()
    if profile == nil then return 1.0 end
    local resolver = self:_spineResolver()
    if resolver == nil or type(resolver.resolve) ~= "function" then return 1.0 end
    local curve = (type(resolver.ECONOMY_HATCH_CURVE) == "table")
        and resolver.ECONOMY_HATCH_CURVE or ProStaffConstants.DISEASE_FLUSH.ECONOMY_HATCH_CURVE
    local ok, mult = pcall(resolver.resolve, {
        dial = "economy",
        base = 1.0,
        neutral = 1.0,
        curve = curve,
    }, profile)
    if not ok or type(mult) ~= "number" or mult < 0 then return 1.0 end
    return mult
end

-- =========================================================
-- The spine (vendored resolver, delegate-when-present)
-- =========================================================

--- The vendored Option-Scaling resolver: the in-mod copy first (the ecosystem's
--- documented consume pattern), then any mission/global handle published by a
--- newer SettingsHub. Nil when neither is reachable.
---@return table|nil
function ProStaffManager:_spineResolver()
    if type(OptionScalingResolver) == "table"
       and type(OptionScalingResolver.readProfile) == "function" then
        return OptionScalingResolver
    end
    local ok, resolver = pcall(function()
        return (g_currentMission and g_currentMission.optionScalingResolver)
            or getfenv(0)["g_OptionScalingResolver"]
    end)
    if ok and type(resolver) == "table" and type(resolver.readProfile) == "function" then
        return resolver
    end
    return nil
end

--- The current spine profile ({ dials, switches, preset }) or nil when the spine
--- is absent. A nil profile means every read falls to neutral.
---@return table|nil
function ProStaffManager:_spineProfile()
    local resolver = self:_spineResolver()
    if resolver == nil then return nil end
    local hub = (g_currentMission and g_currentMission.settingsHub) or g_settingsHub
    local ok, profile = pcall(resolver.readProfile, hub)
    if not ok then return nil end
    return profile
end

-- =========================================================
-- SF reads + writes (the verified SoilFertilizer surface)
-- =========================================================

--- The cross-mod SF handle: g_currentMission.soilFertilityManager.soilSystem
--- (the only handle that crosses the mod boundary; g_SoilFertilityManager is
--- per-mod scoped). Nil when SF is absent.
---@return table|nil
function ProStaffManager:_sfSystem()
    local sfm = g_currentMission and g_currentMission.soilFertilityManager
    if sfm == nil or type(sfm.soilSystem) ~= "table" then return nil end
    return sfm.soilSystem
end

--- The farm's diseased fields, from SF's own per-farmland state (SF keys its
--- field data by farmland id; farmland ids are the same values FS25 uses
--- throughout). A field is diseased when it carries a NAMED active infection at
--- or above the onset threshold.
---@param farmId number
---@return table fields { {fieldId, pressure, diseaseId} } ascending by fieldId
function ProStaffManager:_farmDiseaseReport(farmId)
    local soil = self:_sfSystem()
    if soil == nil or type(soil.fieldData) ~= "table" then return {} end
    local farmlandIds = self:_farmFieldIds(farmId)
    local onset = ProStaffConstants.DISEASE_FLUSH.MIN_PRESSURE
    local out = {}
    for _, fieldId in ipairs(farmlandIds) do
        local field = soil.fieldData[fieldId]
        if field ~= nil then
            local pressure = field.diseasePressure or 0
            local diseaseId = field.activeDisease
            if diseaseId ~= nil and pressure >= onset then
                out[#out + 1] = { fieldId = fieldId, pressure = pressure, diseaseId = diseaseId }
            end
        end
    end
    table.sort(out, function(a, b) return a.fieldId < b.fieldId end)
    return out
end

--- The farmland ids a farm owns (base-game, verified at FarmlandManager.lua:494).
---@param farmId number
---@return table list of farmland ids
function ProStaffManager:_farmFieldIds(farmId)
    local fam = g_farmlandManager
    if fam == nil or type(fam.getOwnedFarmlandIdsByFarmId) ~= "function" then return {} end
    local ok, ids = pcall(fam.getOwnedFarmlandIdsByFarmId, fam, farmId)
    if not ok or type(ids) ~= "table" then return {} end
    return ids
end

--- The recommended fungicide for a field, from SF's own report (recommend carries
--- SF's catalog selection, best control for the active disease). Falls back to the
--- locked broad-spectrum catalog id when the report cannot name one (an unscouted
--- field; the execution scouts first so this is the honest belt, not the norm).
---@param fieldId number
---@param soil table|nil
---@return string chemId
function ProStaffManager:_chemFor(fieldId, soil)
    soil = soil or self:_sfSystem()
    if soil ~= nil and type(soil.getScoutReport) == "function" then
        local ok, report = pcall(soil.getScoutReport, soil, fieldId)
        if ok and type(report) == "table" and type(report.recommend) == "table"
           and type(report.recommend.best) == "string" then
            return report.recommend.best
        end
    end
    return ProStaffConstants.DISEASE_FLUSH.FALLBACK_CHEM
end

--- The grounded TREAT: scout (the Co-Op report reveals the infection, a designed
--- ProStaff reveal path) then applyNamedFungicide with charge=false so SF never
--- bills its own per-hectare chem price. Server-only wrapper.
---@param fieldId number
---@param farmId number
---@return boolean ok
function ProStaffManager:_sfTreat(fieldId, farmId)
    local soil = self:_sfSystem()
    if soil == nil or type(soil.applyNamedFungicide) ~= "function" then return false end
    if type(soil.scoutField) == "function" then
        pcall(soil.scoutField, soil, fieldId)
    end
    local chemId = self:_chemFor(fieldId, soil)
    local ok, applyOk = pcall(soil.applyNamedFungicide, soil, fieldId, chemId, {
        charge = false,
        farmId = farmId,
    })
    return ok and applyOk == true
end

--- The hard-CLEAR wrapper: debugSetDisease(fieldId, 0) through SF's surface.
--- debugSetDisease is server/SP authoritative and NOT client-safe, which is why
--- every caller of this wrapper is server-gated.
---@param fieldId number
---@return boolean ok
function ProStaffManager:_sfDebugClear(fieldId)
    local soil = self:_sfSystem()
    if soil == nil or type(soil.debugSetDisease) ~= "function" then return false end
    local ok = pcall(soil.debugSetDisease, soil, fieldId, 0)
    return ok == true
end

-- =========================================================
-- Fee booking + funds (ProStaff's own server-authoritative money write)
-- =========================================================

--- Balance check mirroring the membership purchase (buyLevel). A flush that
--- cannot be afforded is denied whole, never partially.
---@param farmId number
---@param cost number
---@return boolean
function ProStaffManager:_farmHasFunds(farmId, cost)
    if cost <= 0 then return true end
    local balance = 0
    pcall(function()
        local farm = g_farmManager ~= nil and g_farmManager:getFarmById(farmId) or nil
        if farm ~= nil then
            if farm.getBalance ~= nil then
                balance = farm:getBalance()
            else
                balance = farm.money or 0
            end
        end
    end)
    return balance >= cost
end

--- Book the C5 fee: ProStaff's own server-authoritative debit (MoneyType.OTHER,
--- the same type as the membership investment), audited through TaxMod.
---@param farmId number
---@param cost number
function ProStaffManager:_bookFlushFee(farmId, cost)
    pcall(function()
        g_currentMission:addMoney(-cost, farmId, MoneyType.OTHER, true, true)
    end)
    self:_taxAudit(farmId, -cost, ProStaffConstants.DISEASE_FLUSH.LABEL)
end

-- =========================================================
-- Bedrock: the sanctioned actions (NetworkSync)
-- =========================================================

--- Register the flush actions with NetworkSync. ACTION_FLUSH is a member action
--- (a farm flushes its OWN farm only, ownership-checked like buyLevel); ACTION_CLEAR
--- is admin-gated and difficulty-gated server-side.
function ProStaffManager:bindDiseaseFlush()
    if self.diseaseFlushBound then return end
    local ns = self:_getNetworkSync()
    if ns == nil or type(ns.registerAction) ~= "function" then return end

    ns:registerAction(ProStaffConstants.ACTION_FLUSH, {
        adminOnly = false,
        onAction = function(userId, args)
            if type(args) ~= "table" or args.farmId == nil then return end
            -- Ownership: a client may only flush a farm it belongs to (same rule
            -- as ACTION_BUY). Without it a client could send another farm's id
            -- and spend that farm's money.
            local farm = g_farmManager ~= nil and g_farmManager:getFarmByUserId(userId) or nil
            if farm == nil or farm.farmId ~= args.farmId then
                PSLogger.warning("ACTION_FLUSH rejected: userId %s is not a member of farm %s",
                    tostring(userId), tostring(args.farmId))
                return
            end
            self:_doFarmFlush(args.farmId)
        end,
    })

    ns:registerAction(ProStaffConstants.ACTION_CLEAR, {
        adminOnly = true,
        onAction = function(_userId, args)
            if type(args) ~= "table" or args.farmId == nil then return end
            self:_doAdminClear(args.farmId)
        end,
    })

    self.diseaseFlushBound = true
end

-- =========================================================
-- Console
-- =========================================================

function ProStaffManager:consoleCommandFlushQuote()
    local farmId = self:_resolveFarm(nil)
    local q = self:diseaseFlushQuote(farmId)
    local lines = { string.format(
        "Disease flush (farm %d): character=%s, economyMult=%.2f, clearAllowed=%s, fields=%d, total=%d",
        farmId, q.character, q.economyMultiplier, tostring(q.clearAllowed), q.diseasedCount, q.totalCost) }
    for _, f in ipairs(q.fields) do
        lines[#lines + 1] = string.format("  field %d: pressure %d, %s -> %s (%d)",
            f.fieldId, f.pressure, tostring(f.diseaseId), f.chemId, f.fee)
    end
    return table.concat(lines, "\n")
end

function ProStaffManager:consoleCommandFlush()
    local farmId = self:_resolveFarm(nil)
    local ok, reason = self:requestFarmFlush(farmId)
    if self:_isServer() then
        if ok then return string.format("Farm %d flushed.", farmId) end
        return string.format("Flush failed: %s.", tostring(reason))
    end
    return ok and "Flush requested from the server."
        or ("Flush request failed: " .. tostring(reason))
end

function ProStaffManager:consoleCommandClear()
    local farmId = self:_resolveFarm(nil)
    local ok, reason = self:requestAdminClear(farmId)
    if self:_isServer() then
        if ok then return string.format("Farm %d disease hard-cleared (admin).", farmId) end
        return string.format("Admin clear failed: %s.", tostring(reason))
    end
    return ok and "Admin clear requested from the server."
        or ("Admin clear request failed: " .. tostring(reason))
end
