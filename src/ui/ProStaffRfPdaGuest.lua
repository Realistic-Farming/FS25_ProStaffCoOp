-- =========================================================
-- FS25_ProStaffCoOp - ProStaffRfPdaGuest (Esc RF PDA Pro Staff module)
-- =========================================================
-- BUILD 00:46 (Ash -> Bob; George CLOSED DESIGN 00:16). Source of truth:
-- ecosystem-dev-tracking/Office Tyson/mods/FS25_ProStaffCoOp/
-- PROSTAFF-COOP-ESC-RF-PDA-WIZARD-UI-BRIEF.md
--
-- Registers the "prostaff" module (title Pro Staff, order 35) on the shared Esc
-- RF registry and paints the generic framework Table sheet (rfFwColA..D,
-- rfFwRow1..8, rfFwMore, rfFwHintTable) as a paged glance: membership, live
-- modifiers grouped Worker Costs / Soil / Dairy, unlock flags, recurring money
-- and the disease flush quote. Every value on the sheet comes from the existing
-- manager getters; nothing here invents a number or a getter.
--
-- Money law on this page:
--   Buy -> ProStaffManager:buyLevel(farmId) and nothing else.
--   Run -> ProStaffManager:requestFarmFlush(farmId) and nothing else.
-- Both are server-authoritative inside the manager (NetworkSync ACTION_BUY /
-- ACTION_FLUSH on a pure client). No addMoney, no local debit, and
-- requestAdminClear is not reachable from this page.
--
-- Host-copy rule: the Esc page that loads is always the HOST mod's copy, and the
-- two action Buttons (rfPsBuyBtn / rfPsFlushBtn) exist only in this mod's door
-- copy. On a door built by another suite mod the glance still paints (text sheet
-- plus the shared pager) and the hint names the Farm Tablet Pro Staff app and
-- the console commands as the way to act.
-- =========================================================

ProStaffRfPdaGuest = ProStaffRfPdaGuest or {}

local MOD_DIR = (ProStaffCoOpModDirectory or g_currentModDirectory)
local MOD_NAME = (ProStaffCoOpModName or g_currentModName)
local PANEL_ID = "prostaff"
local PANEL_ORDER = 35
local MAX_ROWS = 8
local SPECTATOR_FARM_ID = 0

local _registered = false
local _listenerHost = nil
local _pageIndex = 1
local _lastRowCount = 0
-- Result of the last Buy / Run click, painted into the hint until the next page enter.
local _note = nil

-- ============================================================
-- Shared helpers (same shape as the other framework guests)
-- ============================================================

local function tr(key, fallback)
    local modEnv = g_modEnvironments and g_modEnvironments[MOD_NAME]
    local i18n = (modEnv and modEnv.i18n) or g_i18n
    if i18n then
        local ok, text = pcall(function() return i18n:getText(key) end)
        if ok and type(text) == "string" and text ~= "" then
            local lower = text:lower()
            if lower ~= tostring(key):lower()
                and text ~= ("$l10n_" .. key)
                and not lower:find("^missing%s")
                and not lower:find("^missing_")
            then
                return text
            end
        end
    end
    return fallback or key
end

local function getHost()
    if g_currentMission ~= nil and g_currentMission.rfEscModules ~= nil then
        return g_currentMission.rfEscModules
    end
    local env = getfenv(0)
    if env ~= nil and env.g_rfEscModules ~= nil then
        return env.g_rfEscModules
    end
    if RfEscModules ~= nil then
        return RfEscModules.getOrCreate()
    end
    return nil
end

local function getHostPage()
    if g_inGameMenu == nil then return nil end
    return g_inGameMenu.menuRealisticFarming
end

local function findDescendant(root, id)
    if root == nil or id == nil then return nil end
    if root.getDescendantById then
        local el = root:getDescendantById(id)
        if el ~= nil then return el end
    end
    local page = getHostPage()
    if page and page.getDescendantById then
        return page:getDescendantById(id)
    end
    return nil
end

local function setText(el, text)
    if el ~= nil and type(el.setText) == "function" then el:setText(text or "") end
end

local function setVis(el, visible)
    if el ~= nil and type(el.setVisible) == "function" then el:setVisible(visible) end
end

local function setDisabled(el, disabled)
    if el ~= nil and type(el.setDisabled) == "function" then el:setDisabled(disabled) end
end

local function formatMoney(amount)
    if amount == nil then return "--" end
    if g_i18n and g_i18n.formatMoney then return g_i18n:formatMoney(amount, 0, true, true) end
    return string.format("%.0f", amount)
end

--- x0.975 / x0.90 / x1.05: three decimals, one trailing zero dropped.
local function fmtMult(v)
    local s = string.format("%.3f", tonumber(v) or 1)
    if s:sub(-1) == "0" then s = s:sub(1, -2) end
    return "x" .. s
end

local function paintSide(container, key, fallback)
    setVis(findDescendant(container, "wcSideInfoShell"), false)
    setVis(findDescendant(container, "mdSideInfoShell"), false)
    local shell = findDescendant(container, "rfSideInfoShell")
    local body = findDescendant(container, "rfSideInfoBody")
    setVis(shell, true)
    setText(body, tr(key, fallback))
end

local function refreshFwAbs(container)
    local page = getHostPage()
    local host = findDescendant(container, "rfHostPlaceholder") or (page and page.rfHostPlaceholder)
    local shell = findDescendant(container, "rfFrameworkGlanceShell")
    local status = findDescendant(container, "rfFwStatusBlock")
    local tableBlock = findDescendant(container, "rfFwTableBlock")
    for _, el in ipairs({ host, shell, status, tableBlock }) do
        if el ~= nil and type(el.updateAbsolutePosition) == "function" then
            el:updateAbsolutePosition()
        end
    end
end

local function clearHostDupes(container)
    setText(findDescendant(container, "rfHostBody"), "")
    setText(findDescendant(container, "rfHostTitle"), "")
    setText(findDescendant(container, "rfHostBlurb"), "")
    setVis(findDescendant(container, "rfHostTitle"), false)
    setVis(findDescendant(container, "rfHostBlurb"), false)
end

local function showTableMode(container)
    setVis(findDescendant(container, "rfFrameworkGlanceShell"), true)
    setVis(findDescendant(container, "rfFwStatusBlock"), false)
    setVis(findDescendant(container, "rfFwTableBlock"), true)
    refreshFwAbs(container)
end

local function stripButtonGlyph(btn)
    if btn == nil then return end
    btn.inputActionName = nil
    btn.keyDisplayText = nil
    btn.keyOverlay = nil
    btn.hideKeyboardGlyph = true
    btn.hasLoadedInputGlyph = false
    btn.isKeyboardMode = false
    btn.keyGlyphOffsetX = 0
    btn.keyGlyphSize = { 0, 0 }
    btn.iconSize = { 0, 0 }
    btn.icon = {}
end

-- The column grid, applied every show. All Table guests paint into the SAME shared
-- elements, so whoever ran last leaves its geometry behind; each guest states its own
-- grid on entry. Y is held; only X and width are written. Normalised via GuiUtils.
local FW_GRID_COLS = {
    { "A", "10px", "280px" },
    { "B", "310px", "280px" },
    { "C", "610px", "220px" },
    { "D", "850px", "280px" },
}
local FW_GRID_RULES = { "300px", "600px", "840px" }
local _fwGridWarned = false

local function applyFwGrid(container)
    if GuiUtils == nil or type(GuiUtils.getNormalizedXValue) ~= "function"
        or type(GuiUtils.getNormalizedScreenValues) ~= "function" then
        if not _fwGridWarned then
            _fwGridWarned = true
            print("[ProStaff] applyFwGrid: GuiUtils normalizer absent - leaving the XML grid")
        end
        return
    end
    local function place(el, xPx, wPx)
        if el == nil then return end
        if type(el.setPosition) == "function" and el.position ~= nil then
            el:setPosition(GuiUtils.getNormalizedXValue(xPx, 0), el.position[2])
        end
        if wPx ~= nil and type(el.setSize) == "function" and el.size ~= nil then
            local norms = GuiUtils.getNormalizedScreenValues(wPx .. " 1px")
            if type(norms) == "table" and norms[1] ~= nil then
                el:setSize(norms[1], el.size[2])
            end
        end
        if type(el.updateAbsolutePosition) == "function" then el:updateAbsolutePosition() end
    end
    for i = 1, 4 do
        local c = FW_GRID_COLS[i]
        if c ~= nil then
            local letter, xPx, wPx = c[1], c[2], c[3]
            place(findDescendant(container, "rfFwCol" .. letter), xPx, wPx)
            for row = 1, MAX_ROWS do
                place(findDescendant(container, "rfFwRow" .. row .. letter), xPx, wPx)
            end
        end
    end
    for i, xPx in ipairs(FW_GRID_RULES) do
        place(findDescendant(container, "rfFwRuleCol" .. i), xPx, nil)
    end
end

-- rfFwEmptyHint is one element behind every door; Income / Depot shrink it to bay A.
-- Restore the XML numbers every show before the text is set.
local function restoreFwEmptyHintBox(container)
    local el = findDescendant(container, "rfFwEmptyHint")
    if el == nil then return end
    if GuiUtils == nil or type(GuiUtils.getNormalizedXValue) ~= "function"
        or type(GuiUtils.getNormalizedYValue) ~= "function"
        or type(GuiUtils.getNormalizedScreenValues) ~= "function" then
        return
    end
    el.textMaxNumLines = 2
    local norms = GuiUtils.getNormalizedScreenValues("1120px 44px")
    if type(norms) ~= "table" or norms[1] == nil or norms[2] == nil then return end
    if type(el.setSize) == "function" then el:setSize(norms[1], norms[2]) end
    if type(el.setPosition) == "function" then
        el:setPosition(GuiUtils.getNormalizedXValue("10px", 0), GuiUtils.getNormalizedYValue("-68px", 0))
        if type(el.updateAbsolutePosition) == "function" then el:updateAbsolutePosition() end
    end
end

-- rfFwTableTitle is shared; Income drops it to the bottom band. Reassert the baseline.
local function resetFwTableTitlePos(container)
    local el = findDescendant(container, "rfFwTableTitle")
    if el == nil or type(el.setPosition) ~= "function" then return end
    if GuiUtils == nil or type(GuiUtils.getNormalizedXValue) ~= "function"
        or type(GuiUtils.getNormalizedYValue) ~= "function" then
        return
    end
    el:setPosition(GuiUtils.getNormalizedXValue("10px", 0), GuiUtils.getNormalizedYValue("-8px", 0))
    if type(el.updateAbsolutePosition) == "function" then el:updateAbsolutePosition() end
end

-- ============================================================
-- Pro Staff data (read-only, existing getters only)
-- ============================================================

local function getManager()
    if g_currentMission ~= nil and g_currentMission.proStaffManager ~= nil then
        return g_currentMission.proStaffManager
    end
    if g_proStaffCoOp ~= nil then
        return g_proStaffCoOp
    end
    local env = getfenv(0)
    if env ~= nil and env.g_proStaffCoOp ~= nil then
        return env.g_proStaffCoOp
    end
    return nil
end

--- The local player's farm id (FSBaseMission:getFarmId). 0 is the spectator farm.
local function localFarmId()
    if g_currentMission == nil or type(g_currentMission.getFarmId) ~= "function" then
        return SPECTATOR_FARM_ID
    end
    local ok, id = pcall(g_currentMission.getFarmId, g_currentMission)
    if not ok or type(id) ~= "number" then return SPECTATOR_FARM_ID end
    return id
end

local function maxLevel()
    return (ProStaffConstants ~= nil and ProStaffConstants.MAX_LEVEL) or 20
end

local function rungName(level)
    if level == nil or level <= 0 then
        return tr("ps_rf_pda_not_member", "Not a member")
    end
    local names = ProStaffConstants ~= nil and ProStaffConstants.LEVEL_NAMES or nil
    local fallback = (names ~= nil and names[level]) or ("Level " .. tostring(level))
    return tr("ps_level_" .. tostring(level), fallback)
end

--- What the next rung adds, from the brief's rung table. Numbers here are display copy
--- for a level the farm has NOT reached yet; the live rows above use the getters.
local UNLOCK_FALLBACK = {
    [1] = "Office Access (name only, no live effect)",
    [2] = "Fertilizer x0.985, fungicide x0.95, vet supplies x0.95",
    [3] = "Dairy logistics x1.05",
    [4] = "Worker fatigue x0.90",
    [5] = "Wages x0.975 step",
    [6] = "Loading Automation (name only, no live effect)",
    [7] = "Fertilizer x0.96, weather forecast, agronomy report sub starts",
    [8] = "Worker fatigue x0.80",
    [9] = "Wages x0.95 step (personnel rebate not settled)",
    [10] = "Soil test kit (experimental gate), pricing moves to net worth",
    [11] = "Fatigue recovery x1.75",
    [12] = "Fertilizer x0.94, fungicide effect x1.10, vet supplies x0.90",
    [13] = "Spray cost x0.92, worker fatigue x0.65",
    [14] = "Fleet rebate 2500 per month (bulk transport not applied)",
    [15] = "Fertilizer x0.925, bulk procurement x1.05, market intel",
    [16] = "Curriculum Admin (name only, no live effect)",
    [17] = "Wages x0.90 step",
    [18] = "Fatigue recovery x1.85, predictive control",
    [19] = "Effectiveness x1.05",
    [20] = "Effectiveness x1.15 (early warning not applied)",
}

local function unlockLine(level)
    if level == nil or level < 1 or level > maxLevel() then return "" end
    return tr("ps_rf_pda_unlock_" .. tostring(level), UNLOCK_FALLBACK[level] or "")
end

--- One read of everything the page shows. kind is one of
--- absent / disabled / spectator / inactive / member.
local function readState()
    local mgr = getManager()
    if mgr == nil then
        return { kind = "absent" }
    end
    local enabled = mgr.settings ~= nil and mgr.settings.enabled ~= false
    if not enabled then
        return { kind = "disabled", mgr = mgr }
    end
    local farmId = localFarmId()
    if farmId == nil or farmId == SPECTATOR_FARM_ID then
        return { kind = "spectator", mgr = mgr, farmId = farmId }
    end
    local rec = (type(mgr.farms) == "table") and mgr.farms[farmId] or nil
    if rec ~= nil and rec.membershipActive == false then
        return { kind = "inactive", mgr = mgr, farmId = farmId, rec = rec }
    end
    return { kind = "member", mgr = mgr, farmId = farmId, rec = rec }
end

local function callNum(mgr, name, farmId, neutral)
    if mgr == nil or type(mgr[name]) ~= "function" then return neutral end
    local ok, v = pcall(mgr[name], mgr, farmId)
    if not ok or type(v) ~= "number" then return neutral end
    return v
end

local function callBool(mgr, name, farmId)
    if mgr == nil or type(mgr[name]) ~= "function" then return false end
    local ok, v = pcall(mgr[name], mgr, farmId)
    return ok and v == true
end

local function isNeutral(v)
    return v == nil or math.abs(v - 1.0) < 0.0005
end

local function flushQuote(mgr, farmId)
    if mgr == nil or type(mgr.diseaseFlushQuote) ~= "function" then return nil end
    local ok, q = pcall(mgr.diseaseFlushQuote, mgr, farmId)
    if not ok or type(q) ~= "table" then return nil end
    return q
end

local function soilTestKitLive()
    if ReleaseGate == nil or type(ReleaseGate.isSystemLive) ~= "function" then return true end
    local ok, live = pcall(ReleaseGate.isSystemLive, "soil_test_kit")
    return ok and live ~= false
end

local ST_LIVE = function() return tr("ps_rf_pda_st_live", "Live") end
local ST_NOT_APPLIED = function() return tr("ps_rf_pda_st_not_applied", "Not applied") end

local function flushRow(mgr, farmId)
    local q = flushQuote(mgr, farmId)
    local label = tr("ps_rf_pda_row_flush", "Disease flush")
    if q == nil then
        return { label, "--", tr("ps_rf_pda_st_no_quote", "No quote"),
                 tr("ps_rf_pda_note_no_quote", "Soil Fertilizer disease layer not found") }, 0
    end
    local n = tonumber(q.diseasedCount) or 0
    if n <= 0 then
        return { label, tr("ps_rf_pda_flush_none", "No diseased fields"), "--", "" }, 0
    end
    local character = tostring(q.character or "")
    local charText = character == "clear" and tr("ps_rf_pda_flush_clear", "Clear")
        or tr("ps_rf_pda_flush_treat", "Treat")
    return { label, string.format(tr("ps_rf_pda_flush_fields", "%d field(s)"), n),
             charText, formatMoney(q.totalCost) }, n
end

--- The full row list for the current state. Each row is { A, B, C, D }.
local function buildRows(st)
    local rows = {}
    local function add(a, b, c, d) rows[#rows + 1] = { a or "", b or "", c or "", d or "" } end
    local mgr, farmId = st.mgr, st.farmId

    if st.kind == "inactive" then
        add(tr("ps_rf_pda_row_membership", "Membership"), tr("ps_rf_pda_inactive", "Inactive"),
            tr("ps_rf_pda_st_suspended", "Benefits suspended"),
            tr("ps_rf_pda_note_inactive", "Nothing on this page is live"))
        add(tr("ps_rf_pda_row_level_on_record", "Level on record"),
            string.format("L%d %s", tonumber(st.rec.level) or 0, rungName(tonumber(st.rec.level) or 0)), "", "")
        add(tr("ps_rf_pda_row_invested", "Invested"), formatMoney(st.rec.investmentTotal or 0), "", "")
        local fr = flushRow(mgr, farmId)
        add(fr[1], fr[2], fr[3], fr[4])
        return rows
    end
    if st.kind ~= "member" then
        return rows
    end

    local level = callNum(mgr, "getLevel", farmId, 0)
    local rec = st.rec
    local invested = (rec ~= nil and rec.investmentTotal) or 0
    local maxL = maxLevel()

    -- Membership
    add(tr("ps_rf_pda_row_level", "Level"), string.format("L%d %s", level, rungName(level)),
        level > 0 and tr("ps_rf_pda_st_member", "Member") or tr("ps_rf_pda_not_member", "Not a member"), "")
    add(tr("ps_rf_pda_row_invested", "Invested"), formatMoney(invested), "", "")
    if level >= maxL then
        add(tr("ps_rf_pda_row_next_level", "Next level"), tr("ps_rf_pda_max", "MAX (L20)"), "--",
            tr("ps_rf_pda_note_max", "Ladder complete"))
    else
        -- Packet item 3: getNextLevelCost is the price getter. nil here means MAX.
        local cost = nil
        if type(mgr.getNextLevelCost) == "function" then
            local ok, c = pcall(mgr.getNextLevelCost, mgr, farmId)
            if ok then cost = c end
        end
        local nextL = level + 1
        local wealthAt = (ProStaffConstants ~= nil and ProStaffConstants.WEALTH_BRACKET
            and ProStaffConstants.WEALTH_BRACKET.ACTIVATES_AT_LEVEL) or 10
        local note = ""
        if nextL >= wealthAt then
            note = tr("ps_rf_pda_note_wealth", "L10+: priced on net worth, not cash on hand")
        end
        add(tr("ps_rf_pda_row_next_level", "Next level"), string.format("L%d %s", nextL, rungName(nextL)),
            cost ~= nil and formatMoney(cost) or tr("ps_rf_pda_max", "MAX (L20)"), note)
        add(tr("ps_rf_pda_row_next_unlock", "Next unlock"), unlockLine(nextL), "", "")
    end

    -- Live modifiers, neutrals skipped. Worker Costs.
    local grpWc = tr("ps_rf_pda_grp_wc", "Worker Costs")
    local v = callNum(mgr, "getWageModifier", farmId, 1.0)
    if not isNeutral(v) then add(tr("ps_rf_pda_row_wages", "Wages"), fmtMult(v), ST_LIVE(), grpWc) end
    v = callNum(mgr, "getFatigueMitigation", farmId, 1.0)
    if not isNeutral(v) then add(tr("ps_rf_pda_row_fatigue", "Worker fatigue"), fmtMult(v), ST_LIVE(), grpWc) end
    v = callNum(mgr, "getFatigueRecoveryBonus", farmId, 1.0)
    if not isNeutral(v) then add(tr("ps_rf_pda_row_recovery", "Fatigue recovery"), fmtMult(v), ST_LIVE(), grpWc) end
    v = callNum(mgr, "getGlobalEffectivenessBonus", farmId, 1.0)
    if not isNeutral(v) then add(tr("ps_rf_pda_row_effectiveness", "Effectiveness"), fmtMult(v), ST_LIVE(), grpWc) end

    -- Soil. Under Precision Farming the soil-chem getters return 1.0 by design: say so
    -- once instead of silently showing nothing, and keep the ladder rows live.
    local grpSoil = tr("ps_rf_pda_grp_soil", "Soil")
    if mgr.pfActive == true and level >= 2 then
        add(tr("ps_rf_pda_row_soil_chem", "Soil chemistry"), "--", tr("ps_rf_pda_st_stood_down", "Stood down"),
            tr("ps_rf_pda_note_pf", "Precision Farming active; ladder stays live"))
    else
        v = callNum(mgr, "getFertilizerDiscount", farmId, 1.0)
        if not isNeutral(v) then add(tr("ps_rf_pda_row_fert", "Fertilizer cost"), fmtMult(v), ST_LIVE(), grpSoil) end
        v = callNum(mgr, "getFungicideDiscount", farmId, 1.0)
        if not isNeutral(v) then add(tr("ps_rf_pda_row_fung_cost", "Fungicide cost"), fmtMult(v), ST_LIVE(), grpSoil) end
        v = callNum(mgr, "getFungicideEffectivenessBonus", farmId, 1.0)
        if not isNeutral(v) then add(tr("ps_rf_pda_row_fung_effect", "Fungicide effect"), fmtMult(v), ST_LIVE(), grpSoil) end
        v = callNum(mgr, "getSprayCostModifier", farmId, 1.0)
        if not isNeutral(v) then add(tr("ps_rf_pda_row_spray", "Spray cost"), fmtMult(v), ST_LIVE(), grpSoil) end
    end

    -- Dairy.
    local grpDairy = tr("ps_rf_pda_grp_dairy", "Dairy")
    v = callNum(mgr, "getVetSupplyDiscount", farmId, 1.0)
    if not isNeutral(v) then add(tr("ps_rf_pda_row_vet", "Vet supplies"), fmtMult(v), ST_LIVE(), grpDairy) end
    v = callNum(mgr, "getDairyLogisticsBonus", farmId, 1.0)
    if not isNeutral(v) then add(tr("ps_rf_pda_row_dairy_logistics", "Dairy logistics"), fmtMult(v), ST_LIVE(), grpDairy) end
    v = callNum(mgr, "getBulkProcurementBonus", farmId, 1.0)
    if not isNeutral(v) then add(tr("ps_rf_pda_row_bulk_procurement", "Bulk procurement"), fmtMult(v), ST_LIVE(), grpDairy) end

    -- Unlock flags. Only reached flags are listed; the soil test kit is the one the
    -- release gate can hold back after the level is reached.
    local unlocked = tr("ps_rf_pda_st_unlocked", "Unlocked")
    if callBool(mgr, "hasForecastAccess", farmId) then
        add(tr("ps_rf_pda_row_forecast", "Weather forecast"), unlocked, ST_LIVE(), "L7")
    end
    local kitLevel = (ProStaffConstants ~= nil and ProStaffConstants.FLAGS and ProStaffConstants.FLAGS.hasSoilTestKit) or 10
    if callBool(mgr, "hasSoilTestKit", farmId) then
        add(tr("ps_rf_pda_row_soil_kit", "Soil test kit"), unlocked, ST_LIVE(), "L" .. tostring(kitLevel))
    elseif level >= kitLevel and not soilTestKitLive() then
        add(tr("ps_rf_pda_row_soil_kit", "Soil test kit"), tr("ps_rf_pda_st_locked", "Locked"),
            tr("ps_rf_pda_st_gate_off", "Experimental gate off"), "L" .. tostring(kitLevel))
    end
    if callBool(mgr, "hasMarketIntel", farmId) then
        add(tr("ps_rf_pda_row_market_intel", "Market intel"), unlocked, ST_LIVE(), "L15")
    end
    if callBool(mgr, "hasPredictiveControl", farmId) then
        add(tr("ps_rf_pda_row_predictive", "Predictive control"), unlocked, ST_LIVE(), "L18")
    end
    if callBool(mgr, "hasEarlyWarning", farmId) then
        add(tr("ps_rf_pda_row_early_warning", "Early warning"), unlocked, ST_NOT_APPLIED(),
            tr("ps_rf_pda_note_no_payout", "L20; no payout behind it yet"))
    end

    -- Unlocked but not applied. Never shown as live money.
    v = callNum(mgr, "getBulkTransportDiscount", farmId, 1.0)
    if not isNeutral(v) then
        add(tr("ps_rf_pda_row_bulk_transport", "Bulk transport"), fmtMult(v), ST_NOT_APPLIED(),
            tr("ps_rf_pda_note_not_built", "L14; designed, not built"))
    end
    if level >= 9 then
        add(tr("ps_rf_pda_row_personnel_rebate", "Personnel rebate"), "L9", tr("ps_rf_pda_st_not_live", "Not live"),
            tr("ps_rf_pda_note_constant_only", "Constant only; no payout"))
    end

    -- Recurring money (read only; no SettingsHub sliders here).
    local settings = mgr.settings or {}
    local feeLevel = (ProStaffConstants ~= nil and ProStaffConstants.FLAGS and ProStaffConstants.FLAGS.hasForecastAccess) or 7
    local fee = tonumber(settings.agronomyFee) or ((ProStaffConstants ~= nil and ProStaffConstants.AGRONOMY_FEE
        and ProStaffConstants.AGRONOMY_FEE.DEFAULT) or 0)
    local feeStatus
    if settings.subscriptionFeeEnabled ~= true then
        feeStatus = tr("ps_rf_pda_st_off", "Off in settings")
    elseif level >= feeLevel then
        feeStatus = tr("ps_rf_pda_st_active", "Active")
    else
        feeStatus = string.format(tr("ps_rf_pda_st_from_level", "From L%d"), feeLevel)
    end
    add(tr("ps_rf_pda_row_agronomy_fee", "Agronomy report sub"),
        string.format(tr("ps_rf_pda_per_month_minus", "-%s / month"), formatMoney(fee)), feeStatus,
        (ProStaffConstants ~= nil and ProStaffConstants.AGRONOMY_FEE and ProStaffConstants.AGRONOMY_FEE.LABEL) or "")
    local fleet = (ProStaffConstants ~= nil and ProStaffConstants.L14_FLEET_REBATE) or 0
    add(tr("ps_rf_pda_row_fleet_rebate", "Fleet rebate"),
        string.format(tr("ps_rf_pda_per_month_plus", "+%s / month"), formatMoney(fleet)),
        level >= 14 and tr("ps_rf_pda_st_active", "Active") or string.format(tr("ps_rf_pda_st_from_level", "From L%d"), 14),
        (ProStaffConstants ~= nil and ProStaffConstants.LABELS and ProStaffConstants.LABELS.FLEET_REBATE) or "")

    -- Disease flush quote, always.
    local fr = flushRow(mgr, farmId)
    add(fr[1], fr[2], fr[3], fr[4])
    return rows
end

local function emptyText(st)
    if st.kind == "absent" then
        return tr("ps_rf_pda_empty_absent", "Pro Staff Co-Op manager not found. Install and enable FS25_ProStaffCoOp.")
    elseif st.kind == "disabled" then
        return tr("ps_rf_pda_empty_disabled", "Pro Staff is disabled in settings. Nothing on this page is live.")
    elseif st.kind == "spectator" then
        return tr("ps_rf_pda_empty_spectator", "Spectator view: join a farm to see membership. No purchase or flush from here.")
    end
    return ""
end

-- ============================================================
-- Painting
-- ============================================================

local function pageCount(n)
    if n <= 0 then return 1 end
    return math.ceil(n / MAX_ROWS)
end

local function paintPager(container, n, pages)
    local prevEl = findDescendant(container, "rfFwPagePrev")
    local nextEl = findDescendant(container, "rfFwPageNext")
    local multi = n > MAX_ROWS and pages > 1
    stripButtonGlyph(prevEl)
    stripButtonGlyph(nextEl)
    for _, el in ipairs({ prevEl, nextEl }) do
        setVis(el, multi)
        setDisabled(el, not multi)
    end
    if not multi then return end
    if prevEl ~= nil and type(prevEl.setText) == "function" then
        prevEl:setText(tr("ps_rf_pda_page_prev", "< Back"))
        stripButtonGlyph(prevEl)
    end
    if nextEl ~= nil and type(nextEl.setText) == "function" then
        nextEl:setText(string.format(tr("ps_rf_pda_page_next", "More (%d/%d) >"), _pageIndex, pages))
        stripButtonGlyph(nextEl)
    end
end

--- The two action Buttons exist only in this mod's door copy. On a foreign host both
--- lookups return nil and this is a no-op; the hint then carries the Tablet / console route.
--- Returns true when the buttons exist (this door is Pro Staff's own copy).
local function paintActions(container, st, diseased)
    local buyEl = findDescendant(container, "rfPsBuyBtn")
    local flushEl = findDescendant(container, "rfPsFlushBtn")
    if buyEl == nil and flushEl == nil then return false end
    local member = st.kind == "member"
    stripButtonGlyph(buyEl)
    stripButtonGlyph(flushEl)
    setVis(buyEl, member)
    setVis(flushEl, member)
    if not member then
        setDisabled(buyEl, true)
        setDisabled(flushEl, true)
        return true
    end
    local level = callNum(st.mgr, "getLevel", st.farmId, 0)
    local atMax = level >= maxLevel()
    if buyEl ~= nil then
        if atMax then
            setText(buyEl, tr("ps_rf_pda_btn_buy_max", "At MAX"))
        else
            setText(buyEl, string.format(tr("ps_rf_pda_btn_buy", "Buy L%d"), level + 1))
        end
        setDisabled(buyEl, atMax)
        stripButtonGlyph(buyEl)
    end
    if flushEl ~= nil then
        local canFlush = (diseased or 0) > 0
        if canFlush then
            setText(flushEl, tr("ps_rf_pda_btn_flush", "Run disease flush"))
        else
            setText(flushEl, tr("ps_rf_pda_btn_flush_none", "No flush needed"))
        end
        setDisabled(flushEl, not canFlush)
        stripButtonGlyph(flushEl)
    end
    return true
end

function ProStaffRfPdaGuest.onShow(container, lightOnly)
    applyFwGrid(container)
    restoreFwEmptyHintBox(container)
    resetFwTableTitlePos(container)
    clearHostDupes(container)
    showTableMode(container)
    paintSide(container, "ps_rf_pda_side_info",
        "Pro Staff Co-Op\n\nThis screen is the Pro Staff membership glance for your farm. Each line is one item: membership, then every live modifier the ladder currently applies, then recurring money and the disease flush quote.\n\nLevel is your rung on the twenty-step ladder. Invested is what the farm has paid in. Next level shows the price of the next rung; from L10 the price follows net worth, not cash on hand. Next unlock says what that rung adds.\n\nLive means the number is applied right now by Worker Costs, Soil Fertilizer or Dairy. Not applied means the rung is unlocked but nothing pays out yet. Stood down means Precision Farming has taken over soil chemistry; the ladder itself keeps running.\n\nDisease flush quotes the Co-Op treatment of every diseased field you own. Run it here when this door belongs to Pro Staff, otherwise from the Farm Tablet Pro Staff app or the console.\n\nPage with the More and Back buttons or the , and . keys.")

    local st = readState()
    local rows = buildRows(st)
    local n = #rows
    _lastRowCount = n
    local pages = pageCount(n)
    if _pageIndex > pages then _pageIndex = pages end
    if _pageIndex < 1 then _pageIndex = 1 end

    setText(findDescendant(container, "rfFwColA"), tr("ps_rf_pda_col_item", "Item"))
    setText(findDescendant(container, "rfFwColB"), tr("ps_rf_pda_col_value", "Value"))
    setText(findDescendant(container, "rfFwColC"), tr("ps_rf_pda_col_status", "Status"))
    setText(findDescendant(container, "rfFwColD"), tr("ps_rf_pda_col_note", "Note"))

    local first = (_pageIndex - 1) * MAX_ROWS
    for i = 1, MAX_ROWS do
        local row = rows[first + i]
        for c, letter in ipairs({ "A", "B", "C", "D" }) do
            local el = findDescendant(container, "rfFwRow" .. i .. letter)
            setText(el, row ~= nil and row[c] or "")
            setVis(el, row ~= nil)
        end
    end

    local emptyEl = findDescendant(container, "rfFwEmptyHint")
    if n == 0 then
        setText(emptyEl, emptyText(st))
        setVis(emptyEl, true)
    else
        setText(emptyEl, "")
        setVis(emptyEl, false)
    end

    local moreEl = findDescendant(container, "rfFwMore")
    if n > MAX_ROWS then
        local lastRow = math.min(first + MAX_ROWS, n)
        setText(moreEl, string.format(tr("ps_rf_pda_showing_range", "Page %d/%d - showing %d-%d of %d"),
            _pageIndex, pages, first + 1, lastRow, n))
    else
        setText(moreEl, "")
    end
    paintPager(container, n, pages)

    local diseased = 0
    if st.kind == "member" then
        local q = flushQuote(st.mgr, st.farmId)
        diseased = (q ~= nil and tonumber(q.diseasedCount)) or 0
    end
    local ownDoor = paintActions(container, st, diseased)

    local hintEl = findDescendant(container, "rfFwHintTable")
    local hintParts = {}
    if _note ~= nil and _note ~= "" then
        hintParts[#hintParts + 1] = _note
    end
    if ownDoor then
        hintParts[#hintParts + 1] = tr("ps_rf_pda_hint_own_door",
            "Buy pays the next rung through the Co-Op (buyLevel). Run pays the disease flush quote (requestFarmFlush). Both settle on the server.")
    else
        hintParts[#hintParts + 1] = tr("ps_rf_pda_hint_foreign_door",
            "This door was built by another module, so Buy and Run live on the Farm Tablet Pro Staff app or the console (proStaffBuy, diseaseFlush).")
    end
    setText(hintEl, table.concat(hintParts, "  "))
    setVis(hintEl, true)
end

function ProStaffRfPdaGuest.onHide()
    _pageIndex = 1
    _note = nil
end

--- Shared pager step. Returns true when the window moved (host then repaints).
function ProStaffRfPdaGuest.onPageStep(delta)
    local pages = pageCount(_lastRowCount)
    if pages <= 1 then return false end
    local target = _pageIndex + (tonumber(delta) or 0)
    if target > pages then target = 1 end
    if target < 1 then target = pages end
    if target == _pageIndex then return false end
    _pageIndex = target
    return true
end

-- ============================================================
-- Actions: the only two writes reachable from this page
-- ============================================================

--- Buy the next rung. Calls ProStaffManager:buyLevel(farmId) and nothing else; the
--- manager owns the fund check, the debit, the audit and the MP routing.
---@return boolean ok
function ProStaffRfPdaGuest.onBuy()
    local st = readState()
    if st.kind ~= "member" then
        _note = st.kind == "inactive" and tr("ps_rf_pda_msg_inactive", "Membership inactive; nothing to buy.")
            or emptyText(st)
        return false
    end
    local mgr, farmId = st.mgr, st.farmId
    local level = callNum(mgr, "getLevel", farmId, 0)
    if level >= maxLevel() then
        _note = tr("ps_rf_pda_msg_max", "Already at MAX (L20).")
        return false
    end
    if type(mgr.buyLevel) ~= "function" then
        _note = tr("ps_rf_pda_msg_no_api", "buyLevel is not available on this manager.")
        return false
    end
    local cost = nil
    if type(mgr.getNextLevelCost) == "function" then
        local okc, c = pcall(mgr.getNextLevelCost, mgr, farmId)
        if okc then cost = c end
    end
    local ok, result = pcall(mgr.buyLevel, mgr, farmId)
    if not ok then
        _note = string.format(tr("ps_rf_pda_msg_error", "Purchase failed: %s"), tostring(result))
        return false
    end
    local isServer = g_currentMission ~= nil and type(g_currentMission.getIsServer) == "function"
        and g_currentMission:getIsServer() == true
    if result == true then
        if isServer then
            _note = string.format(tr("ps_rf_pda_msg_bought", "Bought L%d for %s."), level + 1, formatMoney(cost))
        else
            _note = string.format(tr("ps_rf_pda_msg_requested", "Requested L%d; the server settles it."), level + 1)
        end
        return true
    end
    -- Denied. Name the reason the manager would have logged: disabled, no network on a
    -- pure client, or funds (the server-side check in _doPurchase).
    if mgr.settings ~= nil and mgr.settings.enabled == false then
        _note = tr("ps_rf_pda_msg_disabled", "Denied: Pro Staff is disabled in settings.")
    elseif not isServer then
        _note = tr("ps_rf_pda_msg_no_network", "Denied: no NetworkSync on this client, so the request cannot reach the server.")
    else
        _note = string.format(tr("ps_rf_pda_msg_funds", "Denied: insufficient funds for %s."), formatMoney(cost))
    end
    return false
end

--- Run the disease flush. Calls ProStaffManager:requestFarmFlush(farmId) and nothing
--- else, for the member farm, only when the quote lists at least one diseased field.
---@return boolean ok
function ProStaffRfPdaGuest.onFlush()
    local st = readState()
    if st.kind ~= "member" then
        _note = st.kind == "inactive" and tr("ps_rf_pda_msg_inactive_flush", "Membership inactive; no flush.")
            or emptyText(st)
        return false
    end
    local mgr, farmId = st.mgr, st.farmId
    local q = flushQuote(mgr, farmId)
    local n = (q ~= nil and tonumber(q.diseasedCount)) or 0
    if n <= 0 then
        _note = tr("ps_rf_pda_msg_flush_none", "No diseased fields; nothing to flush.")
        return false
    end
    if type(mgr.requestFarmFlush) ~= "function" then
        _note = tr("ps_rf_pda_msg_no_flush_api", "requestFarmFlush is not available on this manager.")
        return false
    end
    local ok, res, reason = pcall(mgr.requestFarmFlush, mgr, farmId)
    if not ok then
        _note = string.format(tr("ps_rf_pda_msg_flush_error", "Flush failed: %s"), tostring(res))
        return false
    end
    reason = tostring(reason or "")
    if res == true then
        if reason == "requested" then
            _note = tr("ps_rf_pda_msg_flush_requested", "Flush requested; the server settles it.")
        else
            _note = string.format(tr("ps_rf_pda_msg_flush_done", "Flush done on %d field(s) for %s."), n, formatMoney(q.totalCost))
        end
        return true
    end
    local denied = {
        disabled = tr("ps_rf_pda_msg_disabled", "Denied: Pro Staff is disabled in settings."),
        funds = tr("ps_rf_pda_msg_flush_funds", "Denied: insufficient funds for the flush quote."),
        busy = tr("ps_rf_pda_msg_flush_busy", "A flush is already running for this farm."),
        none = tr("ps_rf_pda_msg_flush_none", "No diseased fields; nothing to flush."),
        no_network = tr("ps_rf_pda_msg_no_network", "Denied: no NetworkSync on this client, so the request cannot reach the server."),
    }
    _note = denied[reason] or string.format(tr("ps_rf_pda_msg_flush_denied", "Flush denied (%s)."), reason)
    return false
end

-- ============================================================
-- Registration
-- ============================================================

local function isAvailable()
    return getManager() ~= nil
end

local function onRegistryChanged()
    -- Nothing to hand back: this guest only paints shared framework elements that the
    -- next Table guest restates on its own show.
end

local function publishHandles()
    local env = getfenv(0)
    if env ~= nil then env.ProStaffRfPdaGuest = ProStaffRfPdaGuest end
    if g_currentMission ~= nil then g_currentMission.proStaffRfPdaGuest = ProStaffRfPdaGuest end
end

function ProStaffRfPdaGuest.tryRegister()
    if RfEscBootstrap ~= nil and type(RfEscBootstrap.ensureDoor) == "function" then
        if MOD_DIR == nil then
            print("[ProStaff] ProStaffRfPdaGuest: WARNING MOD_DIR nil - cannot ensureDoor")
        else
            local doorOk = RfEscBootstrap.ensureDoor(MOD_DIR, {
                profilesXml = MOD_DIR .. "xml/gui/rfEscProfiles.xml",
                iconPath = "textures/ui/menuIcon.dds",
            })
            if not doorOk then print("[ProStaff] ProStaffRfPdaGuest: WARNING ensureDoor failed (will retry)") end
        end
    end
    local host = getHost()
    local registerFn = host and (host.registerModule or host.registerPanel)
    if host == nil or registerFn == nil then return false end
    if not _registered then
        local ok = registerFn(host, {
            id = PANEL_ID,
            title = tr("ps_tab_title", "Pro Staff"),
            blurb = tr("ps_rf_pda_blurb", "Co-Op membership, live modifiers, recurring money and the disease flush quote."),
            order = PANEL_ORDER,
            isAvailable = isAvailable,
            onShow = ProStaffRfPdaGuest.onShow,
            onHide = ProStaffRfPdaGuest.onHide,
            onPageStep = ProStaffRfPdaGuest.onPageStep,
        })
        if ok then
            _registered = true
            publishHandles()
            print("[ProStaff] ProStaffRfPdaGuest: registered module prostaff on rfEscModules")
        else
            return false
        end
    end
    if _listenerHost ~= host and type(host.addChangeListener) == "function" then
        host:addChangeListener(onRegistryChanged)
        _listenerHost = host
    end
    return _registered and g_inGameMenu ~= nil and g_inGameMenu.menuRealisticFarming ~= nil
end

function ProStaffRfPdaGuest.isRegistered() return _registered end

function ProStaffRfPdaGuest.reset()
    _registered = false
    _listenerHost = nil
    _pageIndex = 1
    _lastRowCount = 0
    _note = nil
end
