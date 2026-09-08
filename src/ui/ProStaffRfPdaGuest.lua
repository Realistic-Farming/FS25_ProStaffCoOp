-- =========================================================
-- FS25_ProStaffCoOp - ProStaffRfPdaGuest (Esc RF PDA Pro Staff module)
-- =========================================================
-- BUILD 00:46 (Ash -> Bob; George CLOSED DESIGN 00:16) built the module.
-- BUILD 09:37 (Ash -> Bob; George CLOSED DESIGN 09:08) replaced the paged
-- text sheet with the one-page level ladder. Source of truth:
-- ecosystem-dev-tracking/Office Tyson/mods/FS25_ProStaffCoOp/
-- PROSTAFF-COOP-ESC-RF-PDA-WIZARD-UI-BRIEF.md
--
-- Registers the "prostaff" module (title Pro Staff, order 35) on the shared Esc
-- RF registry and paints the twenty-card level ladder that every door XML
-- carries (rfPsHeaderLine1/2, rfPsCard1..20, rfPsRecurring, rfPsNote): rung,
-- name and benefit per card, the marker bar on the rung the farm is at, the
-- membership line (rung, invested, next price or MAX), the honesty line
-- (net-worth pricing from L10, Precision Farming stand-down, soil kit gate),
-- and the recurring line (agronomy sub, L14 fleet rebate, disease flush quote).
-- Every value comes from the existing manager getters; nothing here invents a
-- number or a getter. No paging: the shared More / Back pager is hidden and
-- onPageStep always answers false.
--
-- Money law on this page:
--   Buy -> ProStaffManager:buyLevel(farmId) and nothing else.
--   Run -> ProStaffManager:requestFarmFlush(farmId) and nothing else.
-- Both are server-authoritative inside the manager (NetworkSync ACTION_BUY /
-- ACTION_FLUSH on a pure client). No addMoney, no local debit, and
-- requestAdminClear is not reachable from this page.
--
-- Any host (BUILD 14:35, Wizard: build Buy / Run like the other modules): the Esc
-- page that loads is always the HOST mod's copy, and since BUILD 14:35 every suite
-- door copy carries the two action Buttons (rfPsBuyBtn / rfPsFlushBtn) plus the
-- onClickPsBuy / onClickPsFlush host clicks, so Buy and Run paint and act whichever
-- mod built the door. The only door without them is a stale copy that predates
-- this build; there the ladder still paints in full and the note says so.
-- =========================================================

ProStaffRfPdaGuest = ProStaffRfPdaGuest or {}

local MOD_DIR = (ProStaffCoOpModDirectory or g_currentModDirectory)
local MOD_NAME = (ProStaffCoOpModName or g_currentModName)
local PANEL_ID = "prostaff"
local PANEL_ORDER = 35
local MAX_ROWS = 8 -- shared Table rows this module hides on show
local SPECTATOR_FARM_ID = 0

local _registered = false
local _listenerHost = nil
-- Result of the last Buy / Run click, painted into the note until the next page enter.
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

--- BUILD 17:58: extra (optional) is appended after the teach; the honesty notes that used to
--- sit on rfPsHeaderLine2 land here, so they stay readable while the cards fill the bay.
local function paintSide(container, key, fallback, extra)
    setVis(findDescendant(container, "wcSideInfoShell"), false)
    setVis(findDescendant(container, "mdSideInfoShell"), false)
    local shell = findDescendant(container, "rfSideInfoShell")
    local body = findDescendant(container, "rfSideInfoBody")
    setVis(shell, true)
    local text = tr(key, fallback)
    if type(extra) == "string" and extra ~= "" then
        text = text .. "\n\n" .. extra
    end
    setText(body, text)
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

-- ============================================================
-- BUILD 00:06 (LAW Wizard Esc overlay-chip buttons 2026-09-05, George CLOSED DESIGN 23:12): every
-- created button on this page paints as a vanilla key chip, the CsRfPdaGuest setPivotBtn /
-- renderPivotChip / wirePivotChipPaint chain vendored. Idle = dark plate, lime text; latched =
-- lime plate, dark text; gated = grey, no lime. The Button keeps its own hit box and onClick
-- (RF_CsPivotBtn: buttonActivate chrome, hideKeyboardGlyph, no global-action trigger, so SPACE
-- never confirms); its TextElement text stays "" so the chip is the only paint.
-- ============================================================
-- The engine text colour setter, captured here (no file-local helper shadows the name in this
-- file, but the 20:36 Market crash is the reason this is never called by its bare name).
local engineSetTextColor = setTextColor
local CHIP_TEXT = { 0.22323, 0.40724, 0.00368 }
local CHIP_BG = { 0.00913, 0.01033, 0.00651 }
local CHIP_GATED_TEXT = { 0.62, 0.64, 0.66 }
local CHIP_GATED_BG = { 0.06, 0.06, 0.065 }

--- Store the chip state on the Button and blank its text. enabled=false paints the grey chip
--- and disables the Button; latched inverts the live chip.
local function setChipBtn(el, label, enabled, latched)
    if el == nil then return end
    if type(el.setText) == "function" then el:setText("") end
    el.rfChipLabel = label
    el.rfChipEnabled = enabled and true or false
    el.rfChipLatched = latched and true or false
    if type(el.setDisabled) == "function" then el:setDisabled(not enabled) end
end

local function renderChip(el, overlay)
    local label = el.rfChipLabel
    if label == nil or label == "" then return end
    if el.absPosition == nil or el.absSize == nil or el.visible == false then return end
    local height = el.absSize[2] * 0.72
    if height <= 0 then return end
    local t, b, ta, ba
    if el.rfChipEnabled and el.rfChipLatched then
        t, b, ta, ba = CHIP_BG, CHIP_TEXT, 1.0, 1.0
    elseif el.rfChipEnabled then
        t, b, ta, ba = CHIP_TEXT, CHIP_BG, 1.0, 1.0
    else
        t, b, ta, ba = CHIP_GATED_TEXT, CHIP_GATED_BG, 0.45, 0.55
    end
    overlay:setColor(t[1], t[2], t[3], ta, b[1], b[2], b[3], ba)
    local width = overlay:getButtonWidth(label, height)
    local x = el.absPosition[1] + (el.absSize[1] - width) * 0.5
    local y = el.absPosition[2] + (el.absSize[2] - height) * 0.5
    overlay:renderButton(label, x, y, height, true)
end

--- Wrap one already-visible parent's draw once (guard flag on the element) so the listed chips
--- repaint every frame the parent draws. lookup(root, id) resolves each Button. The colour reset
--- at the end is the ENGINE global captured above, never an element helper.
local function wireChipPaint(parent, ids, flag, lookup)
    if parent == nil or parent[flag] then return end
    parent[flag] = true
    local prevDraw = parent.draw
    function parent:draw(...)
        if prevDraw ~= nil then prevDraw(self, ...) end
        local idm = g_inputDisplayManager
        if idm == nil or type(idm.getKeyboardKeyOverlay) ~= "function" then return end
        local overlay = idm:getKeyboardKeyOverlay()
        if overlay == nil or type(overlay.renderButton) ~= "function" then return end
        for _, id in ipairs(ids) do
            local el = lookup(self, id)
            if el ~= nil then
                pcall(renderChip, el, overlay)
            end
        end
        setTextBold(false)
        setTextAlignment(RenderText.ALIGN_LEFT)
        setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_BASELINE)
        if type(engineSetTextColor) == "function" then
            engineSetTextColor(1, 1, 1, 1)
        end
    end
end

local PS_CHIP_IDS = { "rfPsBuyBtn", "rfPsFlushBtn" }

--- The wrap goes on rfFwTableBlock, the bay the ladder and the action strip sit in.
local function wirePsChipPaint(container)
    wireChipPaint(findDescendant(container, "rfFwTableBlock"), PS_CHIP_IDS, "_rfPsChipWired", function(root, id)
        return findDescendant(root, id) or findDescendant(container, id)
    end)
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
-- Painting: the one-page level ladder (BUILD 09:37)
-- ============================================================
-- The sheet is twenty fixed cards in the door XML (rfPsCard1..20, byte-same in all ten
-- door copies) plus two header lines, a recurring-money line and a note line. Nothing
-- pages: every rung is on screen at once, the rung the farm is at carries the marker bar
-- and the lit background, reached rungs sit a shade quieter and future rungs quieter
-- still. The generic Table chrome (column headers, hairlines, rows, More, pager) is
-- hidden on the way in and handed back the moment another module is active.

local CARD_COUNT = 20

-- Card palette. Bg is the card's blank-slice Bitmap, Mark the 6px bar on the left edge,
-- Title the rung number and name, Body the two-line benefit.
local CARD_STYLE = {
    current = { bg = { 0.196, 0.290, 0.141, 0.95 }, mark = true,
                title = { 1.0, 1.0, 1.0, 1.0 }, body = { 0.90, 0.92, 0.90, 1.0 } },
    reached = { bg = { 0.145, 0.157, 0.173, 0.85 }, mark = false,
                title = { 0.85, 0.85, 0.85, 1.0 }, body = { 0.659, 0.678, 0.702, 1.0 } },
    future  = { bg = { 0.118, 0.129, 0.141, 0.85 }, mark = false,
                title = { 0.55, 0.57, 0.60, 1.0 }, body = { 0.45, 0.47, 0.50, 1.0 } },
}

local function setTextColor(el, c)
    if el ~= nil and c ~= nil and type(el.setTextColor) == "function" then
        el:setTextColor(c[1], c[2], c[3], c[4])
    end
end

local function setImageColor(el, c)
    if el ~= nil and c ~= nil and type(el.setImageColor) == "function" then
        el:setImageColor(nil, c[1], c[2], c[3], c[4])
    end
end

--- Element lookup that also works with no container (registry callbacks carry none).
local function findOnPage(root, id)
    if root ~= nil then return findDescendant(root, id) end
    local page = getHostPage()
    if page ~= nil and page.getDescendantById then
        return page:getDescendantById(id)
    end
    return nil
end

-- The shared Table chrome this module hides while it is on screen. Rows and the two
-- pager Buttons are restated by whichever Table guest paints next; the column headers
-- and hairlines are not, so exactly those go back on hand-back (same list as Dairy).
local SHEET_STATIC = {
    "rfFwColA", "rfFwColB", "rfFwColC", "rfFwColD",
    "rfFwRuleHead", "rfFwRuleRow1", "rfFwRuleRow2", "rfFwRuleRow3", "rfFwRuleRow4",
    "rfFwRuleRow5", "rfFwRuleRow6", "rfFwRuleRow7",
    "rfFwRuleCol1", "rfFwRuleCol2", "rfFwRuleCol3",
}
local LADDER_STATIC = { "rfPsHeaderLine1", "rfPsHeaderLine2", "rfPsRecurring", "rfPsNote",
    -- BUILD 14:35: the action strip goes dark with the ladder on hand-back, so Buy / Run
    -- never linger on a host copy whose every-refresh hide predates this build.
    "rfPsBuyBtn", "rfPsFlushBtn" }
local _chromeHidden = false

local function hideSheetChrome(container)
    for _, id in ipairs(SHEET_STATIC) do
        setVis(findOnPage(container, id), false)
    end
    -- BUILD 17:21: the shared table's rows now live in this list, so the list goes dark with the
    -- rest of the sheet. Nil-safe: an older door copy has no such id.
    setVis(findOnPage(container, "rfFwSheetBox"), false)
    for i = 1, MAX_ROWS do
        for _, c in ipairs({ "A", "B", "C", "D" }) do
            setVis(findOnPage(container, "rfFwRow" .. i .. c), false)
        end
    end
    setText(findOnPage(container, "rfFwMore"), "")
    setText(findOnPage(container, "rfFwTableTitle"), "")
    setVis(findOnPage(container, "rfFwTableTitle"), false)
    setText(findOnPage(container, "rfFwHintTable"), "")
    setVis(findOnPage(container, "rfFwHintTable"), false)
    _chromeHidden = true
end

local function hideLadder(container)
    for k = 1, CARD_COUNT do
        setVis(findOnPage(container, "rfPsCard" .. k), false)
    end
    for _, id in ipairs(LADDER_STATIC) do
        setVis(findOnPage(container, id), false)
    end
end

local function restoreSheetChrome(container)
    for _, id in ipairs(SHEET_STATIC) do
        setVis(findOnPage(container, id), true)
    end
    setVis(findOnPage(container, "rfFwHintTable"), true)
    hideLadder(container)
    _chromeHidden = false
end

local function handBackChromeIfLeft()
    if not _chromeHidden then return end
    local host = getHost()
    if host ~= nil and host.activeModuleId == PANEL_ID then return end
    restoreSheetChrome(nil)
end

--- The shared pager never applies here: one page, both Buttons dark and inert.
local function hidePager(container)
    for _, id in ipairs({ "rfFwPagePrev", "rfFwPageNext" }) do
        local el = findOnPage(container, id)
        stripButtonGlyph(el)
        setVis(el, false)
        setDisabled(el, true)
    end
end

--- The two action Buttons, painted whenever the ids exist, whichever mod built the door
--- (every suite door copy carries them since BUILD 14:35). Only a stale door copy that
--- predates that build has neither; then this is a no-op and the note says so.
--- Returns true when the buttons exist.
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
    -- BUILD 00:06 (overlay-chip law): the labels ride the chip; gated grey when there is
    -- nothing to buy / flush. Same strings as before.
    if buyEl ~= nil then
        if atMax then
            setChipBtn(buyEl, tr("ps_rf_pda_btn_buy_max", "At MAX"), false, false)
        else
            setChipBtn(buyEl, string.format(tr("ps_rf_pda_btn_buy", "Buy L%d"), level + 1), true, false)
        end
        stripButtonGlyph(buyEl)
    end
    if flushEl ~= nil then
        local canFlush = (diseased or 0) > 0
        if canFlush then
            setChipBtn(flushEl, tr("ps_rf_pda_btn_flush", "Run disease flush"), true, false)
        else
            setChipBtn(flushEl, tr("ps_rf_pda_btn_flush_none", "No flush needed"), false, false)
        end
        stripButtonGlyph(flushEl)
    end
    return true
end

--- One card. state is current / reached / future.
local function paintCard(container, k, state, mgr, farmId)
    local style = CARD_STYLE[state] or CARD_STYLE.future
    local id = "rfPsCard" .. k
    local numEl = findOnPage(container, id .. "Num")
    local nameEl = findOnPage(container, id .. "Name")
    local bodyEl = findOnPage(container, id .. "Benefit")
    setText(numEl, "L" .. tostring(k))
    setText(nameEl, rungName(k))
    setText(bodyEl, unlockLine(k))
    setTextColor(numEl, style.title)
    setTextColor(nameEl, style.title)
    setTextColor(bodyEl, style.body)
    -- BUILD 17:58 (George CLOSED DESIGN 17:25): the rung's price at the farm's current net worth,
    -- from the existing ProStaffManager:levelCost(farmId, targetLevel) (nil past MAX -> "--").
    -- The same getter feeds the header's Next price, so the two always agree. Stale doors
    -- without rfPsCardNExtra get a nil element and the helpers no-op.
    local extraEl = findOnPage(container, id .. "Extra")
    local costText = "--"
    if mgr ~= nil and farmId ~= nil and type(mgr.levelCost) == "function" then
        local ok, c = pcall(mgr.levelCost, mgr, farmId, k)
        if ok and type(c) == "number" then
            costText = formatMoney(c)
        end
    end
    setText(extraEl, string.format(tr("ps_rf_pda_card_cost", "Cost: %s"), costText))
    setTextColor(extraEl, style.body)
    setImageColor(findOnPage(container, id .. "Bg"), style.bg)
    setVis(findOnPage(container, id .. "Mark"), style.mark)
    setVis(findOnPage(container, id), true)
end

--- All twenty cards for a level. markLevel nil paints the whole ladder quiet (inactive
--- membership: nothing is live, so no rung is lit and no marker shows).
local function paintLadder(container, level, markLevel, mgr, farmId)
    for k = 1, CARD_COUNT do
        local state = "future"
        if markLevel ~= nil then
            if k == markLevel then
                state = "current"
            elseif k < level then
                state = "reached"
            end
        end
        paintCard(container, k, state, mgr, farmId)
    end
end

--- Header line 1: rung | invested | next (or MAX). Line 2: the honesty strip.
local function paintHeader(container, st, level, invested)
    local mgr, farmId = st.mgr, st.farmId
    local maxL = maxLevel()
    local parts = {}
    if st.kind == "inactive" then
        parts[#parts + 1] = string.format(tr("ps_rf_pda_hdr_on_record", "On record: L%d %s"), level, rungName(level))
    elseif level <= 0 then
        parts[#parts + 1] = tr("ps_rf_pda_not_member", "Not a member")
    else
        parts[#parts + 1] = string.format(tr("ps_rf_pda_hdr_rung", "Your rung: L%d %s"), level, rungName(level))
    end
    parts[#parts + 1] = string.format(tr("ps_rf_pda_hdr_invested", "Invested %s"), formatMoney(invested))
    local honesty = {}
    if st.kind == "inactive" then
        parts[#parts + 1] = tr("ps_rf_pda_inactive", "Inactive")
        honesty[#honesty + 1] = tr("ps_rf_pda_hdr_inactive", "Membership inactive: benefits suspended, nothing on this page is live")
    elseif level >= maxL then
        parts[#parts + 1] = tr("ps_rf_pda_hdr_max", "MAX (L20): ladder complete")
    else
        -- Packet item 3: getNextLevelCost is the price getter. nil here means MAX.
        local cost = nil
        if type(mgr.getNextLevelCost) == "function" then
            local ok, c = pcall(mgr.getNextLevelCost, mgr, farmId)
            if ok then cost = c end
        end
        local nextL = level + 1
        parts[#parts + 1] = string.format(tr("ps_rf_pda_hdr_next", "Next L%d %s %s"), nextL, rungName(nextL),
            cost ~= nil and formatMoney(cost) or tr("ps_rf_pda_max", "MAX (L20)"))
        local wealthAt = (ProStaffConstants ~= nil and ProStaffConstants.WEALTH_BRACKET
            and ProStaffConstants.WEALTH_BRACKET.ACTIVATES_AT_LEVEL) or 10
        if nextL >= wealthAt then
            honesty[#honesty + 1] = tr("ps_rf_pda_note_wealth", "L10+: priced on net worth, not cash on hand")
        end
    end
    if st.kind == "member" then
        -- Under Precision Farming the soil-chem getters return 1.0 by design: say so once.
        if mgr.pfActive == true and level >= 2 then
            honesty[#honesty + 1] = tr("ps_rf_pda_hdr_pf", "Precision Farming active: soil chemistry stood down, ladder stays live")
        end
        local kitLevel = (ProStaffConstants ~= nil and ProStaffConstants.FLAGS and ProStaffConstants.FLAGS.hasSoilTestKit) or 10
        if level >= kitLevel and not callBool(mgr, "hasSoilTestKit", farmId) and not soilTestKitLive() then
            honesty[#honesty + 1] = tr("ps_rf_pda_hdr_kit_gate", "Soil test kit: experimental gate off")
        end
    end
    if #honesty == 0 then
        honesty[#honesty + 1] = tr("ps_rf_pda_hdr_line2_default",
            "Twenty rungs: the green bar marks your rung, lit cards are reached, dim cards are ahead")
    end
    local l1 = findOnPage(container, "rfPsHeaderLine1")
    local l2 = findOnPage(container, "rfPsHeaderLine2")
    setText(l1, table.concat(parts, "  |  "))
    -- BUILD 17:58: line 2 stays declared but hidden; the cards took its band. The honesty
    -- strip is returned and lands at the end of the side info (onShow).
    setText(l2, "")
    setVis(l1, true)
    setVis(l2, false)
    return honesty
end

--- Footer line: agronomy sub, fleet rebate (both read only) and the flush quote.
local function paintRecurring(container, st, level)
    local mgr, farmId = st.mgr, st.farmId
    local parts = {}
    if st.kind == "member" then
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
        parts[#parts + 1] = string.format("%s %s (%s)", tr("ps_rf_pda_row_agronomy_fee", "Agronomy report sub"),
            string.format(tr("ps_rf_pda_per_month_minus", "-%s / month"), formatMoney(fee)), feeStatus)
        local fleet = (ProStaffConstants ~= nil and ProStaffConstants.L14_FLEET_REBATE) or 0
        parts[#parts + 1] = string.format("%s %s (%s)", tr("ps_rf_pda_row_fleet_rebate", "Fleet rebate"),
            string.format(tr("ps_rf_pda_per_month_plus", "+%s / month"), formatMoney(fleet)),
            level >= 14 and tr("ps_rf_pda_st_active", "Active") or string.format(tr("ps_rf_pda_st_from_level", "From L%d"), 14))
    end
    local fr, diseased = flushRow(mgr, farmId)
    local flushBits = { fr[1] .. ": " .. fr[2] }
    if fr[3] ~= "" and fr[3] ~= "--" then flushBits[#flushBits + 1] = fr[3] end
    if fr[4] ~= "" then flushBits[#flushBits + 1] = fr[4] end
    parts[#parts + 1] = table.concat(flushBits, ", ")
    -- BUILD 17:58: rfPsNote is gone from the door XML (the cards took its band), so the Buy /
    -- Run result rides this line. A stale door that still has rfPsNote keeps it there (paintNote).
    if findOnPage(container, "rfPsNote") == nil and _note ~= nil and _note ~= "" then
        parts[#parts + 1] = _note
    end
    local el = findOnPage(container, "rfPsRecurring")
    setText(el, table.concat(parts, "  |  "))
    setVis(el, true)
    return diseased
end

local function paintNote(container, hasActions)
    local parts = {}
    if _note ~= nil and _note ~= "" then
        parts[#parts + 1] = _note
    end
    if hasActions then
        parts[#parts + 1] = tr("ps_rf_pda_hint_own_door",
            "Buy pays the next rung through the Co-Op (buyLevel). Run pays the disease flush quote (requestFarmFlush). Both settle on the server.")
    else
        parts[#parts + 1] = tr("ps_rf_pda_hint_stale_door",
            "This door copy predates the Buy and Run buttons; update the mod that built it. Until then the console commands proStaffBuy and diseaseFlush do the same job.")
    end
    local el = findOnPage(container, "rfPsNote")
    setText(el, table.concat(parts, "  "))
    setVis(el, true)
end

-- BUILD 17:58: the side teach, painted once on show and again with the honesty notes appended.
local SIDE_FALLBACK = "Pro Staff Co-Op\n\nThis screen is the Pro Staff level ladder for your farm: all twenty rungs on one page, four across and five down, in the order they are bought.\n\nThe green bar and the lit card mark the rung you are at. Lit cards below it are reached; dim cards are still ahead. Each card names the rung and says what buying it adds. Name only means the rung exists but changes nothing live; not applied means the rung is unlocked but nothing pays out yet.\n\nThe top line shows your rung, what the farm has invested and the price of the next rung; from L10 that price follows net worth, not cash on hand. Each card also shows the rung's price at your current net worth (Invested is what you actually paid). Honesty notes - net-worth pricing, Precision Farming standing soil chemistry down, the soil test kit gate - are listed at the end of this box.\n\nThe bottom line shows the agronomy report subscription, the L14 fleet rebate and the disease flush quote for every diseased field you own. Buy and Run sit under the ladder on every Realistic Farming door, whichever mod built it: Buy pays the next rung through the Co-Op and Run pays the disease flush quote, both settled on the server."

function ProStaffRfPdaGuest.onShow(container, lightOnly)
    restoreFwEmptyHintBox(container)
    resetFwTableTitlePos(container)
    clearHostDupes(container)
    showTableMode(container)
    hideSheetChrome(container)
    hidePager(container)
    wirePsChipPaint(container)
    paintSide(container, "ps_rf_pda_side_info", SIDE_FALLBACK)

    local st = readState()
    local emptyEl = findDescendant(container, "rfFwEmptyHint")
    if st.kind ~= "member" and st.kind ~= "inactive" then
        hideLadder(container)
        setText(emptyEl, emptyText(st))
        setVis(emptyEl, true)
        paintActions(container, st, 0)
        return
    end
    setText(emptyEl, "")
    setVis(emptyEl, false)

    local level, invested, markLevel
    if st.kind == "inactive" then
        level = tonumber(st.rec.level) or 0
        invested = st.rec.investmentTotal or 0
        markLevel = nil
    else
        level = callNum(st.mgr, "getLevel", st.farmId, 0)
        invested = (st.rec ~= nil and st.rec.investmentTotal) or 0
        markLevel = level
    end
    local honesty = paintHeader(container, st, level, invested)
    paintLadder(container, level, markLevel, st.mgr, st.farmId)
    if type(honesty) == "table" and #honesty > 0 then
        paintSide(container, "ps_rf_pda_side_info", SIDE_FALLBACK, table.concat(honesty, "\n"))
    end
    local diseased = paintRecurring(container, st, level)
    local hasActions = paintActions(container, st, diseased)
    paintNote(container, hasActions)
end

function ProStaffRfPdaGuest.onHide()
    _note = nil
end

--- One page: the shared pager step never moves anything and never asks for a repaint.
function ProStaffRfPdaGuest.onPageStep(delta)
    return false
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

--- Availability poll. Every host refresh asks through getModules(), and
--- applyHomeModuleQuiet does not notify, so this is also the belt for handing the
--- sheet chrome back once another module is active.
local function isAvailable()
    if _chromeHidden then pcall(handBackChromeIfLeft) end
    return getManager() ~= nil
end

--- Registry change: selectModule / registerModule / unregisterModule all notify. If this
--- module was the last painter and is no longer active, the sheet chrome goes back now
--- and every ladder element goes dark so the next module's sheet is clean.
local function onRegistryChanged()
    handBackChromeIfLeft()
end

local function publishHandles()
    local env = getfenv(0)
    if env ~= nil then env.ProStaffRfPdaGuest = ProStaffRfPdaGuest end
    if g_currentMission ~= nil then g_currentMission.proStaffRfPdaGuest = ProStaffRfPdaGuest end
end

--- BUILD 19:15: the Esc Help footer asks whichever module is showing to open its own guide, so
--- every companion ships and owns its own help instead of borrowing Soil's.
---@param container table|nil
function ProStaffRfPdaGuest.onOpenHelp(container)
    if PsGuideDialog ~= nil and type(PsGuideDialog.show) == "function" then
        PsGuideDialog.show()
    end
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
            -- BUILD 19:15 (George CLOSED DESIGN 18:55 item 5): load this mod's Field Guide at the
            -- same moment the door itself loads. A GUI loaded from a mod directory later, once the
            -- mod's own file system context has closed, fails to open.
            if PsGuideDialog ~= nil and type(PsGuideDialog.register) == "function" then
                pcall(PsGuideDialog.register, MOD_DIR)
            end
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
            onOpenHelp = ProStaffRfPdaGuest.onOpenHelp,
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
    _chromeHidden = false
    _note = nil
end
