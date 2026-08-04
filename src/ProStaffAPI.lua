-- =========================================================
-- FS25_ProStaffCoOp - ProStaffAPI (the getter proxy)
-- =========================================================
-- Author: TisonK
-- =========================================================
-- The canonical function list companion mods pull via
-- g_currentMission.proStaffManager:getX(farmId). Every getter returns its
-- NEUTRAL value when ProStaff is disabled, the level is not reached, or the
-- farm has no membership. farmId is optional (defaults to the local player's
-- farm) so a no-arg call from a companion resolves correctly.
--
-- These methods extend the ProStaffManager class (defined in ProStaffManager.lua,
-- sourced first).
-- =========================================================

function ProStaffManager:_resolveFarm(farmId)
    if farmId ~= nil and farmId ~= 0 then return farmId end
    if g_currentMission ~= nil and g_currentMission.getFarmId ~= nil then
        return g_currentMission:getFarmId()
    end
    return 1
end

function ProStaffManager:_farmLevel(farmId)
    if not self.settings.enabled then return 0 end
    local rec = self.farms[self:_resolveFarm(farmId)]
    return (rec ~= nil and rec.level) or 0
end

-- Compute an effect value from its table at the farm's current level.
function ProStaffManager:_effect(effectKey, farmId)
    local eff = ProStaffConstants.EFFECTS[effectKey]
    if eff == nil then return 1.0 end
    local level = self:_farmLevel(farmId)
    if eff.mode == "product" then
        local v = eff.neutral
        for stepLevel, stepVal in pairs(eff.steps) do
            if level >= stepLevel then v = v * stepVal end
        end
        return v
    else
        local best, bestLevel = eff.neutral, -1
        for stepLevel, stepVal in pairs(eff.steps) do
            if level >= stepLevel and stepLevel > bestLevel then
                best, bestLevel = stepVal, stepLevel
            end
        end
        return best
    end
end

function ProStaffManager:_flag(flagKey, farmId)
    local reqLevel = ProStaffConstants.FLAGS[flagKey]
    if reqLevel == nil then return false end
    return self:_farmLevel(farmId) >= reqLevel
end

function ProStaffManager:getLevel(farmId) return self:_farmLevel(farmId) end

-- WorkerCosts
function ProStaffManager:getWageModifier(farmId)      return self:_effect("WAGE", farmId) end
function ProStaffManager:getFatigueMitigation(farmId) return self:_effect("FATIGUE_MITIGATION", farmId) end
function ProStaffManager:getFatigueRecoveryBonus(farmId) return self:_effect("FATIGUE_RECOVERY", farmId) end
function ProStaffManager:getGlobalEffectivenessBonus(farmId) return self:_effect("GLOBAL_EFFECTIVENESS", farmId) end

-- SoilFertilizer + the SF 2.5 disease/fungicide layer (soil-related: disabled under PF)
function ProStaffManager:getFertilizerDiscount(farmId)
    if self.pfActive then return 1.0 end
    return self:_effect("FERTILIZER", farmId)
end
function ProStaffManager:getFungicideDiscount(farmId)
    if self.pfActive then return 1.0 end
    return self:_effect("FUNGICIDE_DISCOUNT", farmId)
end
function ProStaffManager:getFungicideEffectivenessBonus(farmId)
    if self.pfActive then return 1.0 end
    return self:_effect("FUNGICIDE_EFFECT", farmId)
end
function ProStaffManager:getSprayCostModifier(farmId)
    if self.pfActive then return 1.0 end
    return self:_effect("SPRAY_COST", farmId)
end

-- DairyCore / RLRM
function ProStaffManager:getVetSupplyDiscount(farmId)    return self:_effect("VET_SUPPLY", farmId) end
function ProStaffManager:getDairyLogisticsBonus(farmId)  return self:_effect("DAIRY_LOGISTICS", farmId) end
function ProStaffManager:getBulkProcurementBonus(farmId) return self:_effect("BULK_PROCUREMENT", farmId) end
function ProStaffManager:getBulkTransportDiscount(farmId) return self:_effect("BULK_TRANSPORT", farmId) end

-- Report / feature flags
function ProStaffManager:hasMarketIntel(farmId)      return self:_flag("hasMarketIntel", farmId) end
function ProStaffManager:hasForecastAccess(farmId)   return self:_flag("hasForecastAccess", farmId) end
function ProStaffManager:hasPredictiveControl(farmId) return self:_flag("hasPredictiveControl", farmId) end
function ProStaffManager:hasEarlyWarning(farmId)     return self:_flag("hasEarlyWarning", farmId) end
-- [SF-40] Read the Dirt member 4 (K half): a farm at level 10 gets exact
-- numbers (N/P/K/pH) and the precise disease name at the kneel instead of
-- bands and pressure labels. Gates DISPLAY PRECISION only, never data
-- existence; it never bypasses the disease knowledge gate. Neutral-false when
-- the consuming read is absent.
-- RELEASE GATE: the kit flag itself is LOCKED until the player opts into
-- experimental systems. Its consumer (SF's Read the Dirt) is locked on the
-- SoilFertilizer side, so a farm must not earn the L10 kit flag while the
-- system is locked. Fail-open (see ReleaseGate.isSystemLive): the getter
-- behaves exactly as before when the opt-in flag cannot be read.
function ProStaffManager:hasSoilTestKit(farmId)
    if ReleaseGate ~= nil and not ReleaseGate.isSystemLive("soil_test_kit") then
        return false
    end
    return self:_flag("hasSoilTestKit", farmId)
end
