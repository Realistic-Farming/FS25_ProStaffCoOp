-- MAINT-142-level_display_name_test.lua
--
-- MAINTENANCE row 142, part 2 (Bob's intake BOB-INTAKE-ROW142-PROSTAFF-L10N-2026-09-25.md,
-- section 3): ProStaffManager:getLevelDisplayName(level), the level's name in the calling
-- machine's language, for a companion (FarmTablet's Pro-Staff app) that cannot read
-- ProStaff's keys through its own i18n.
--
-- THE ENTRY-POINT BAR IS THE WHOLE FILE. The engine loads a mod's scripts into the mod's own
-- environment, whose g_i18n is g_i18n:addModI18N(modName) (mods.lua:453). ProStaffAPI.lua is
-- loaded the same way here: its chunk runs in a ProStaff environment whose g_i18n answers
-- from the REAL translation file, and the getter is then called from a caller whose own
-- g_i18n (FarmTablet's, here the global one) does not carry ProStaff's keys. Nothing
-- hand-writes a level name: every expected text is read from the file.
--
--   G0  the getter exists on the manager after the API file loads
--   G1  de: all 20 levels return the de file's text, not English, called from the caller's
--       environment
--   G2  jp: level 6 returns the jp file's text
--   G3  a key ProStaff's file lacks returns the English name, never the key or "Missing"
--   G4  an i18n that answers an empty string returns the English name
--   G5  not a whole number from 1 to 20 returns nil (0, 21, -1, 2.5, "3", nil)
--
--!load: src/ProStaffConstants.lua, src/ProStaffManager.lua
--!text: src/ProStaffAPI.lua, translations/translation_de.xml, translations/translation_en.xml, translations/translation_jp.xml

local function group(name, fn)
    local ok, err = pcall(fn)
    if not ok then T.ok(name .. " [group raised: " .. tostring(err) .. "]", false) end
end

local function unxml(v)
    return (v:gsub("&quot;", '"'):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&amp;", "&"))
end
local function texts(lang)
    local out = {}
    for k, v in _SOURCE_TEXT["translations/translation_" .. lang .. ".xml"]:gmatch('<text name="([^"]+)"%s+text="([^"]*)"') do
        out[k] = unxml(v)
    end
    return out
end
local DE, EN, JP = texts("de"), texts("en"), texts("jp")

-- An i18n in the engine's shape: hasText is key presence, getText answers "Missing ..."
-- for an absent key (I18N.lua:175-194).
local function i18nOf(file)
    return {
        hasText = function(_, key) return file[key] ~= nil end,
        getText = function(_, key) return file[key] or ("Missing '" .. tostring(key) .. "' in l10n.xml") end,
    }
end

-- ProStaffAPI.lua into a ProStaff environment whose g_i18n is `psI18n`.
local function loadApi(psI18n)
    local modEnv = setmetatable({ g_i18n = psI18n }, { __index = _G })
    local chunk = assert(load(_SOURCE_TEXT["src/ProStaffAPI.lua"], "=ProStaffAPI.lua", "t", modEnv))
    chunk()
end

-- The caller's own i18n (FarmTablet's): it carries none of ProStaff's keys.
g_i18n = i18nOf({ ft_prostaff_level_none = "None" })
local mgr = ProStaffManager.new()

group("G", function()
    loadApi(i18nOf(DE))
    T.eq("G0 [reached] the getter is on the manager after ProStaffAPI.lua loads", type(mgr.getLevelDisplayName), "function")
    local wrong = {}
    for lv = 1, 20 do
        local got = mgr:getLevelDisplayName(lv)
        local key = "ps_level_" .. lv
        if got ~= DE[key] or got == EN[key] then wrong[#wrong + 1] = lv .. "=" .. tostring(got) end
    end
    T.eq("G1 de: all 20 levels return the de file's name, not English, called from an environment whose i18n lacks ProStaff's keys",
        table.concat(wrong, " "), "")

    loadApi(i18nOf(JP))
    T.eq("G2 jp: level 6 returns the jp file's name", tostring(mgr:getLevelDisplayName(6) == JP.ps_level_6 and JP.ps_level_6 ~= EN.ps_level_6), "true")

    local lacking = {}
    for k, v in pairs(DE) do if k ~= "ps_level_5" then lacking[k] = v end end
    loadApi(i18nOf(lacking))
    T.eq("G3 a key ProStaff's file lacks returns the English name, never the key or a Missing text",
        tostring(mgr:getLevelDisplayName(5)), EN.ps_level_5)

    loadApi({ hasText = function() return true end, getText = function() return "" end })
    T.eq("G4 an i18n that answers an empty string returns the English name", tostring(mgr:getLevelDisplayName(7)), EN.ps_level_7)

    loadApi(i18nOf(DE))
    local out = {}
    for _, lv in ipairs({ 0, 21, -1, 2.5, "3" }) do
        local ok, v = pcall(mgr.getLevelDisplayName, mgr, lv)
        out[#out + 1] = tostring(ok) .. ":" .. tostring(v)
    end
    local okNil, vNil = pcall(mgr.getLevelDisplayName, mgr, nil)
    out[#out + 1] = tostring(okNil) .. ":" .. tostring(vNil)
    T.eq("G5 0, 21, -1, 2.5, the string \"3\" and nil each return nil without raising", table.concat(out, " "),
        "true:nil true:nil true:nil true:nil true:nil true:nil")
end)
